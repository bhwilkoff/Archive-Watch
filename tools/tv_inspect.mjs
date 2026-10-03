#!/usr/bin/env node
// Evaluate JavaScript INSIDE the app running on the television, through Chii.
//   node tools/tv_inspect.mjs "document.activeElement.outerHTML.slice(0,200)"
//   node tools/tv_inspect.mjs --list
// See docs/tizen-signing.md (2026-10-03) for the debug package this needs.
import { connect } from './tv_chii.mjs'
const args = process.argv.slice(2)
if (args[0] === '--list' || !args.length) {
  const t = (await (await fetch((process.env.CHII || 'http://127.0.0.1:8080') + '/targets')).json()).targets || []
  for (const x of t) console.log(x.id, x.title, x.url)
  process.exit(t.length ? 0 : 2)
}
const tv = await connect()
try { console.log(JSON.stringify(await tv.evaluate(args.join(' '), Number(process.env.AW_EVAL_MS || 60000)), null, 1)) }
catch (e) { console.error(String(e.message || e)); process.exitCode = 1 }
tv.close()
