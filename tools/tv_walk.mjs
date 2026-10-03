#!/usr/bin/env node
// Walk every top-level route ON THE TELEVISION by remote-key presses (through
// Chii) and report, per press, any focus that is lost or outside the 5%
// overscan-safe band — the on-device twin of tv_follow_focus.mjs.
//   node tools/tv_walk.mjs [routes...]      default: every nav route
import { connect } from './tv_chii.mjs'
const ROUTES = process.argv.slice(2).length ? process.argv.slice(2)
  : ['#/', '#/browse', '#/channels', '#/surprise', '#/search', '#/library', '#/collections', '#/about']
const KEYS = { left: 37, up: 38, right: 39, down: 40 }
const PLAN = ['down','down','down','down','down','down','right','right','right','down','down','down','down','up','up','left','left','down','down','down','down','down','down','down']
const tv = await connect()
const probe = `(() => { const a=document.activeElement; if(!a||a===document.body) return {lost:true};
  const r=a.getBoundingClientRect(); const lab=(a.getAttribute('aria-label')||a.textContent||a.tagName).trim().replace(/\\s+/g,' ').slice(0,40);
  return { lab, out: r.left<96||r.right>1824||r.top<54||r.bottom>1026, r:[r.left|0,r.top|0,r.width|0,r.height|0], vis: r.width>0&&r.height>0 } })()`
let problems = 0
for (const route of ROUTES) {
  await tv.evaluate(`(async () => { const d=document.querySelector('dialog[open]'); d&&d.close(); location.hash=${JSON.stringify(route)}; await new Promise(r=>setTimeout(r,3500)); return 1 })()`)
  const seen = new Set(); const issues = []
  let p = await tv.evaluate(probe)
  if (p.lost) issues.push('arrival: nothing focused')
  for (const k of PLAN) {
    await tv.evaluate(`(async () => { window.dispatchEvent(new KeyboardEvent('keydown',{keyCode:${KEYS[k]},which:${KEYS[k]},bubbles:true,cancelable:true})); await new Promise(r=>setTimeout(r,60)); window.dispatchEvent(new KeyboardEvent('keyup',{keyCode:${KEYS[k]},bubbles:true})); await new Promise(r=>setTimeout(r,450)); return 1 })()`)
    p = await tv.evaluate(probe)
    if (p.lost) { issues.push(`${k}: focus lost`); continue }
    seen.add(p.lab)
    if (p.out) issues.push(`${k}: "${p.lab}" outside safe ${p.r}`)
  }
  problems += issues.length
  console.log(`${route.padEnd(15)} ${seen.size} distinct stops${issues.length ? '  ISSUES: ' + issues.join(' | ') : '  ok'}`)
}
tv.close()
process.exit(problems ? 1 : 0)
