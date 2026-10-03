// Shared: connect to the app on the television through Chii and evaluate JS.
// See docs/tizen-signing.md (2026-10-03). Used by tv_inspect.mjs and tv_press.mjs.
export async function connect(server = process.env.CHII || 'http://127.0.0.1:8080') {
  const targets = (await (await fetch(server + '/targets')).json()).targets || []
  if (!targets.length) throw new Error('no Chii targets — is the debug package running on the TV?')
  // A relaunched app leaves its old target listed; take the newest live one.
  const live = targets.filter(t => !t.ws || t.ws._readyState === 1)
  const target = (live.length ? live : targets)[(live.length ? live : targets).length - 1]
  const ws = new WebSocket(server.replace(/^http/, 'ws') + '/client/' +
    Math.random().toString(36).slice(2) + '?target=' + target.id)
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej })
  let id = 0
  const pending = new Map()
  ws.onmessage = ev => {
    const m = JSON.parse(ev.data)
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) }
  }
  const send = (method, params = {}) => new Promise(res => {
    const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params }))
  })
  async function evaluate(js, timeoutMs = 20000) {
    const expr = `(async () => { const v = await (${js}); return JSON.stringify(v) })()`
    let timer
    const r = await Promise.race([
      send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true }),
      new Promise(res => { timer = setTimeout(() => res({ error: { message: 'timeout' } }), timeoutMs) }),
    ])
    clearTimeout(timer)   // or every call waits out the full timeout before exiting
    if (r.error) throw new Error(r.error.message)
    if (r.result?.exceptionDetails) throw new Error(JSON.stringify(r.result.exceptionDetails).slice(0, 400))
    const v = r.result?.result?.value
    return v === undefined ? undefined : JSON.parse(v)
  }
  return { target, evaluate, close: () => ws.close() }
}
