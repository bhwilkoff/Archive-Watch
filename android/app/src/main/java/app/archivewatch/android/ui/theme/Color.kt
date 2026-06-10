package app.archivewatch.android.ui.theme

import androidx.compose.ui.graphics.Color

// Brand chrome (shared design system — CLAUDE.md). Brand colors are for
// chrome/CTA only; per-category semantic accents come from featured.json
// at runtime and carry content meaning only (Decision 013).
val BrandPrimary = Color(0xFFFF5C35)   // marquee orange
val BrandAccent = Color(0xFF0047FF)    // links, interactive
val BrandBackground = Color(0xFF0A0A0A)
val BrandSurface = Color(0xFF141414)
val BrandSurfaceHigh = Color(0xFF1E1E1E)

/** featured.json accent hex → Color (semantic category accents). */
fun colorFromHex(hex: String?): Color? {
    if (hex == null) return null
    val cleaned = hex.removePrefix("#")
    return runCatching {
        when (cleaned.length) {
            6 -> Color(0xFF000000 or cleaned.toLong(16))
            8 -> Color(cleaned.toLong(16))
            else -> null
        }
    }.getOrNull()
}
