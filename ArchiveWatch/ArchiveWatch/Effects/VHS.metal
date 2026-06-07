//  VHS.metal
//  A native Metal layer-effect that emulates the look of analog NTSC/VHS
//  playback: chroma bleed, scanlines, tape grain, line jitter, a slow rolling
//  tracking band, head-switching noise, a mild color cast and vignette.
//
//  Why this exists: classic public-domain TV and film were authored for analog
//  CRT/tape. Presenting them with a faithful (optional) analog veneer is part of
//  "the best way to watch" them. The algorithm is an original Metal
//  reimplementation; its artifact taxonomy is informed by the MIT/ISC-licensed
//  ntsc-rs project (github.com/ntsc-rs/ntsc-rs) — no code is copied.
//
//  Applied via SwiftUI `.layerEffect` (see VHSEffect.swift). GPU-only, so it is
//  cheap enough for the cover-art wall on Apple TV; the CPU signal-accurate
//  model in ntsc-rs would not be.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// value noise, smooth interpolation
static float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Procedural overlay variant for surfaces a layer effect can't SAMPLE — most
// importantly live video (AVPlayerViewController renders into its own layer that
// SwiftUI cannot rasterize for `.layerEffect`). This generates the analog
// artifacts as a translucent layer composited OVER the video: scanlines and a
// vignette darken, a rolling tracking band + dropout streaks + grain brighten,
// with a faint warm tape cast. No chroma bleed / geometric wobble here (those
// need to sample the source, which we can't over video). Applied via
// `.colorEffect` on a filled rectangle (see VHSVideoOverlay). Returns
// premultiplied RGBA so it blends correctly with the video beneath.
[[ stitchable ]]
half4 vhsOverlay(float2 pos, half4 color, float2 size, float time, float amount) {
    float2 uv = pos / max(size, float2(1.0));

    // darkening: CRT scanlines + vignette
    float scan = 0.5 + 0.5 * sin(pos.y * 3.14159265);
    float2 dd = uv - 0.5;
    float vig = 1.0 - smoothstep(0.25, 0.95, dot(dd, dd) * 2.2);
    float d = (0.12 * scan + 0.28 * vig) * amount;

    // brightening: rolling tracking band + dropout streaks + positive grain
    float band = fract(uv.y + time * 0.06);
    float bandWarp = smoothstep(0.965, 0.99, band) * smoothstep(1.0, 0.99, band);
    float head = smoothstep(0.975, 1.0, uv.y) * (0.5 + 0.5 * vnoise(float2(pos.y, time * 50.0)));
    float streak = step(0.9975, vnoise(float2(floor(pos.y * 0.5), floor(time * 9.0))));
    float grain = max(0.0, vnoise(pos * float2(0.7, 1.3) + time * 60.0) - 0.5);
    float b = (bandWarp * 0.22 + head * 0.18 + streak * 0.5 + grain * 0.10) * amount;

    d = clamp(d, 0.0, 1.0);
    b = clamp(b, 0.0, 1.0);
    // single premultiplied "over" layer: darken by reducing dst, brighten by
    // adding tinted white. out = src + dst*(1-a), with a = d + b - d*b.
    half a = half(d + b - d * b);
    half3 premul = half3(b) * half3(1.0h, 0.98h, 0.94h);  // warm tape cast on the lift
    return half4(premul, a);
}

[[ stitchable ]]
half4 vhs(float2 pos, SwiftUI::Layer layer, float2 size, float time, float amount) {
    float2 uv = pos / max(size, float2(1.0));
    float line = pos.y;

    // --- slow vertical rolling tracking band ---
    float band = fract(uv.y + time * 0.06);
    float bandWarp = smoothstep(0.965, 0.99, band) * smoothstep(1.0, 0.99, band);

    // --- horizontal jitter / wobble per scanline ---
    float jitter = vnoise(float2(line * 0.15, time * 12.0)) - 0.5;   // per-line random
    float wob    = sin(uv.y * 90.0 + time * 4.0) * 0.5;              // smooth wobble
    float dx = (jitter * 2.2 + wob) * amount;
    dx += bandWarp * (vnoise(float2(line * 0.3, time * 30.0)) - 0.5) * 16.0 * amount;

    // --- head-switching noise at the very bottom ~2.5% ---
    float headSwitch = smoothstep(0.975, 1.0, uv.y);
    dx += headSwitch * (vnoise(float2(line, time * 50.0)) - 0.5) * 22.0 * amount;

    float2 p = pos + float2(dx, 0.0);

    // --- chroma bleed: R/G/B sampled at horizontal offsets (chroma delay) ---
    float bleed = (2.0 + 1.2 * sin(time * 0.7)) * amount;
    half4 cr = layer.sample(p + float2(bleed, 0.0));
    half4 cg = layer.sample(p);
    half4 cb = layer.sample(p - float2(bleed * 0.6, 0.0));
    half3 col = half3(cr.r, cg.g, cb.b);
    half  a   = cg.a;

    // --- horizontal luma smear (cheap 2-tap) ---
    half3 smear = layer.sample(p + float2(2.5 * amount, 0.0)).rgb;
    col = mix(col, (col + smear) * 0.5h, half(0.22 * amount));

    // --- saturation drop + characteristic tape color cast ---
    half luma = dot(col, half3(0.299h, 0.587h, 0.114h));
    col = mix(half3(luma), col, half(1.0 - 0.18 * amount));
    col *= half3(1.03h, 1.0h, 0.97h);

    // --- CRT scanlines ---
    float scan = 0.5 + 0.5 * sin(pos.y * 3.14159265);
    col *= half(1.0 - 0.10 * amount * scan);

    // --- tape grain, denser in shadows ---
    float g = vnoise(pos * float2(0.7, 1.3) + time * 60.0) - 0.5;
    col += half(g * (0.05 + 0.10 * (1.0 - luma)) * amount);

    // --- occasional bright dropout streaks ---
    float streak = step(0.997, vnoise(float2(floor(line * 0.5), floor(time * 9.0))));
    col += half(streak * 0.45 * amount);

    // --- rolling band brightness lift ---
    col += half(bandWarp * 0.22 * amount);

    // --- vignette ---
    float2 d = uv - 0.5;
    float vig = smoothstep(0.95, 0.30, dot(d, d) * 2.2);
    col *= half(mix(1.0, vig, 0.5 * amount));

    return half4(clamp(col, 0.0h, 1.0h), a);
}
