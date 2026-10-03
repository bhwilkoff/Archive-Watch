#!/usr/bin/env node
// Press keys on the Samsung TV over its own remote-control socket — the same
// key events as the physical remote, delivered by the platform (Back, OK,
// arrows, media keys), not synthesized inside the app.
//
//   node tools/samsung_remote.mjs [--host 10.0.0.203] KEY_DOWN KEY_ENTER wait:800 KEY_RETURN
//
// The first connection makes the TV ask "Allow connection?"; the token it
// returns is kept in ~/.config/archivewatch/samsung-token and reused, so the
// prompt appears once. Requires Node 22+ (global WebSocket). The set's
// certificate is self-signed, hence NODE_TLS_REJECT_UNAUTHORIZED=0 below —
// for this one local connection only.
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0'
const args = process.argv.slice(2)
let host = '10.0.0.203'
const hi = args.indexOf('--host')
if (hi >= 0) { host = args[hi + 1]; args.splice(hi, 2) }
const tokenFile = path.join(os.homedir(), '.config/archivewatch/samsung-token')
const token = fs.existsSync(tokenFile) ? fs.readFileSync(tokenFile, 'utf8').trim() : ''
const name = Buffer.from('Archive Watch Test').toString('base64')
const port = process.env.AW_SAMSUNG_PORT || '8002'
const url = `${port === '8001' ? 'ws' : 'wss'}://${host}:${port}/api/v2/channels/samsung.remote.control?name=${name}` +
  (token ? `&token=${token}` : '')

const sleep = ms => new Promise(r => setTimeout(r, ms))
const ws = new WebSocket(url)
ws.onopen = () => console.log('socket open — waiting for the TV')
const ready = new Promise((resolve, reject) => {
  const t = setTimeout(() => reject(new Error('no answer in 90 s — was the prompt accepted?')), 90000)
  ws.onmessage = ev => {
    const m = JSON.parse(ev.data)
    if (process.env.AW_VERBOSE) console.log('<<', String(ev.data).slice(0, 300))
    if (m.event === 'ms.channel.connect') {
      const tok = m.data?.token
      if (tok && tok !== token) { fs.writeFileSync(tokenFile, tok); console.log('token saved') }
      clearTimeout(t); resolve()
    } else if (m.event === 'ms.channel.unauthorized') {
      clearTimeout(t); reject(new Error('the TV refused the connection'))
    }
  }
  ws.onclose = e => console.log('closed', e.code, e.reason)
  ws.onerror = e => { clearTimeout(t); reject(new Error('socket error: ' + (e.message || e.type))) }
})
await ready
for (const a of args) {
  if (a.startsWith('wait:')) { await sleep(Number(a.slice(5))); continue }
  ws.send(JSON.stringify({ method: 'ms.remote.control', params: {
    Cmd: 'Click', DataOfCmd: a, Option: 'false', TypeOfRemote: 'SendRemoteKey' } }))
  console.log('pressed', a)
  await sleep(350)
}
await sleep(200)
ws.close()
