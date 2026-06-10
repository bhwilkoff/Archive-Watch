package app.archivewatch.android.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/**
 * Always-dark brand theme — a cinema, not a settings app. Dynamic color
 * (Material You) is deliberately NOT the default; the dark canvas is the
 * product (ANDROID-DESIGN theme rules).
 */
@Composable
fun ArchiveWatchTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = BrandDarkColors,
        typography = Typography(),
        content = content,
    )
}

private val BrandDarkColors = darkColorScheme(
    primary = BrandPrimary,
    onPrimary = Color.Black,
    secondary = BrandAccent,
    onSecondary = Color.White,
    background = BrandBackground,
    onBackground = Color.White,
    surface = BrandBackground,
    onSurface = Color.White,
    surfaceVariant = BrandSurface,
    onSurfaceVariant = Color(0xFFBBBBBB),
    surfaceContainer = BrandSurface,
    surfaceContainerLow = BrandSurface,
    surfaceContainerLowest = BrandBackground,
    surfaceContainerHigh = BrandSurfaceHigh,
    surfaceContainerHighest = BrandSurfaceHigh,
)
