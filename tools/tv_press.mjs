#!/usr/bin/env node
// Press remote keys INSIDE the app on the television (through Chii) and print,
// after each press, what is focused, where, and whether it sits inside the
// 5% overscan-safe band (tv_overscan_safe_band: 96..1824 x 54..1026).
//
//   node tools/tv_press.mjs down down right ok wait:2000 back
//
// Keys (prefix hold: to hold 800 ms): left right up down ok back play pause playpause stop ff rew chup chdown
// red green yellow blue, or a number (a raw keyCode). These are dispatched to
// window as keydown events — the path tv.js handles — so this proves the APP's
// handling on the real set; the platform's own key delivery (registerKey) is
// a separate fact a physical remote confirms.
import { connect } from './tv_chii.mjs'
const CODES = { left: 37, up: 38, right: 39, down: 40, ok: 13, enter: 13, back: 10009,
  play: 415, pause: 19, playpause: 10252, stop: 413, ff: 417, rew: 412,
  chup: 427, chdown: 428, red: 403, green: 404, yellow: 405, blue: 406 }
const probe = `(() => {
  const a = document.activeElement
  if (!a || a === document.body) return { focus: 'NOTHING' }
  const r = a.getBoundingClientRect()
  const label = (a.getAttribute('aria-label') || a.textContent || a.value || a.tagName).trim().replace(/\\s+/g, ' ').slice(0, 60)
  const out = r.left < 96 || r.right > 1824 || r.top < 54 || r.bottom > 1026
  return { focus: a.tagName.toLowerCase() + (a.id ? '#' + a.id : '') + (a.className && typeof a.className === 'string' ? '.' + a.className.split(' ')[0] : ''),
           label, rect: [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)],
           outsideSafe: out, route: location.hash || '#/' }
})()`
const tv = await connect()
console.log('start', JSON.stringify(await tv.evaluate(probe)))
for (const k of process.argv.slice(2)) {
  if (k.startsWith('wait:')) { await new Promise(r => setTimeout(r, Number(k.slice(5)))); continue }
  // hold:ok — key down, held 800 ms, then up (a held OK opens Player Options).
  const held = k.startsWith('hold:')
  const name = held ? k.slice(5) : k
  const code = CODES[name] ?? Number(name)
  const down = `window.dispatchEvent(new KeyboardEvent('keydown', { keyCode: ${code}, which: ${code}, bubbles: true, cancelable: true }))`
  const up = `window.dispatchEvent(new KeyboardEvent('keyup', { keyCode: ${code}, which: ${code}, bubbles: true }))`
  await tv.evaluate(held
    ? `(async () => { ${down}; await new Promise(r => setTimeout(r, 800)); ${up}; return true })()`
    // A real remote's key is down for ~80 ms; a same-tick up is not a press.
    : `(async () => { ${down}; await new Promise(r => setTimeout(r, 80)); ${up}; return true })()`)
  await new Promise(r => setTimeout(r, 450))
  console.log(k.padEnd(6), JSON.stringify(await tv.evaluate(probe)))
}
tv.close()
