#!/usr/bin/env python3
"""The TV build runs on Samsung's 2022 TVs (Tizen 6.5, Chromium 85).

Owner, 2026-10-03: "I'd like to be able to support everything from 2022
onward." Each rule below is a feature newer than Chromium 85 that broke a real
render of the TV layer in a Chromium 85 build (docs/tizen-submission.md,
"Older Samsung TVs"). The control at the end plants each one and expects a
failure, so a check that cannot fail does not pass.
"""
import re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CSS = ['watch.css', 'tv.css']

def strip_comments(s):
    return re.sub(r'/\*.*?\*/', '', s, flags=re.S)

def css_problems(name, s):
    s = strip_comments(s)
    out = []
    for m in re.finditer(r'(?<![-\w])(inset|padding-inline|margin-inline|padding-block|margin-block)\s*:', s):
        out.append(f'{name}: `{m.group(1)}` shorthand needs Chromium 87; write top/right/bottom/left')
    for sel in re.findall(r'([^{}]+)\{', s):
        if ':focus-visible' in sel and (',' in sel or name == 'tv.css'):
            out.append(f'{name}: `{sel.strip()[:60]}` — Chromium 85 drops a rule list holding :focus-visible')
    # color-mix() outside an @supports block: with var() inside it voids the fallback
    depth_supports = [m.start() for m in re.finditer(r'@supports[^{]*color-mix', s)]
    for m in re.finditer(r'color-mix\(', s):
        if not any(m.start() > d for d in depth_supports):
            out.append(f'{name}: color-mix() outside @supports (Chromium 111)')
    if re.search(r'overflow\s*:\s*clip', s) and not re.search(r'@supports\s*\(overflow:\s*clip\)', s):
        out.append(f'{name}: overflow: clip outside @supports (Chromium 90)')
    return out

def js_problems():
    out = []
    compat = (ROOT / 'js/compat.js').read_text()
    for api in ('AbortSignal.timeout', 'replaceChildren'):
        if api.split('.')[-1] not in compat:
            out.append(f'js/compat.js no longer fills {api}')
    idx = (ROOT / 'index.html').read_text()
    a, b = idx.find('js/compat.js'), idx.find('js/api.js')
    if a < 0 or a > b:
        out.append('index.html must load js/compat.js before every other script')
    return out

def main():
    probs = js_problems()
    for f in CSS:
        probs += css_problems(f, (ROOT / f).read_text())
    # control: each planted feature must be caught
    plants = ['.a{inset:0}', '.a{padding-inline:4px}', '.a:focus-visible,.b{x:1}',
              '.a{background:color-mix(in srgb,red 5%,blue)}', '.a{overflow:clip}']
    missed = [p for p in plants if not css_problems('control.css', p)]
    if missed:
        print('FAIL control: these plants went undetected:', missed); return 1
    if probs:
        print('FAIL'); [print('  ' + p) for p in probs]; return 1
    print(f'PASS: TV layer stays inside Chromium 85 ({len(plants)} controls caught)'); return 0

sys.exit(main())
