package app.archivewatch.android.data

/**
 * How long a film runs, as a Browse filter (2026-09-26, from the Orphaned Films
 * research). Bands over the upload's own runtimeSeconds, identical to Apple's
 * RuntimeBand: of 11,006 features ~12% run under an hour, ~60% an hour to 90
 * minutes, ~28% longer. Labels are whole words, never abbreviated.
 */
enum class RuntimeBand(val label: String, val sql: String) {
    UNDER_HOUR("Under an hour", "i.runtimeSeconds > 0 AND i.runtimeSeconds < 3600"),
    HOUR_TO_90("An hour to 90 minutes", "i.runtimeSeconds >= 3600 AND i.runtimeSeconds <= 5400"),
    OVER_90("Over 90 minutes", "i.runtimeSeconds > 5400"),
}
