package app.archivewatch.android.ui.tv

import android.graphics.Bitmap
import android.graphics.Color as AColor
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter

/**
 * The TV Share surface (tvOS ShareSheet parity): a remote has no share
 * sheet, so the phone in the viewer's pocket is the share target — a QR of
 * the canonical archivewatch.org URL, scanned in a second.
 */
@Composable
fun TvShareOverlay(title: String, url: String, onDone: () -> Unit, reportUrl: String? = null) {
    androidx.activity.compose.BackHandler(true) { onDone() }
    // A film's overlay can swap to "Something wrong with this film?"
    // (2026-09-26): a television has no browser, so the phone opens the form.
    var reporting by androidx.compose.runtime.saveable.rememberSaveable { androidx.compose.runtime.mutableStateOf(false) }
    val shown = if (reporting && reportUrl != null) reportUrl else url
    val qr = remember(shown) { qrBitmap(shown, 640) }
    Box(Modifier.fillMaxSize().background(Color(0xCC000000))) {
        Column(
            Modifier
                .align(Alignment.Center)
                .background(Color(0xFF141414), RoundedCornerShape(18.dp))
                .padding(40.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(if (reporting) "Something wrong with “$title”?" else "Share “$title”",
                fontSize = 20.sp, fontWeight = FontWeight.Medium, color = Color.White)
            Text(
                // Not "this film": the same overlay carries a PLAYLIST link,
                // and on a television the viewer is looking at the thing they
                // just pressed Share on — naming it wrongly is worse than not
                // naming it.
                if (reporting) "Scan to tell us on your phone." else "Scan with your phone to open or send it.",
                fontSize = 13.sp, color = Color(0xFF9A9A9A),
                modifier = Modifier.padding(top = 4.dp, bottom = 20.dp),
            )
            qr?.let {
                Box(Modifier.background(Color.White, RoundedCornerShape(12.dp)).padding(14.dp)) {
                    Image(it.asImageBitmap(), contentDescription = shown, modifier = Modifier.size(280.dp))
                }
            }
            // ONLY IF IT CAN BE TYPED. A playlist link carries the whole list
            // in its fragment, so it runs to several hundred characters —
            // printed in full it wrapped to three lines and ran off the bottom
            // of the screen, pushing the hint with it. Nobody keys in 450
            // characters from a television. Same rule the web TV build
            // settled on: write the link out when it is short enough to be
            // useful, and otherwise let the code carry it.
            if (reporting) {
                // The form's link is for the camera, not for typing.
            } else if (url.length <= 120) {
                Text(
                    url,
                    fontSize = 13.sp,
                    color = Color(0xFF9A9A9A),
                    modifier = Modifier.padding(top = 16.dp),
                )
            } else {
                Text(
                    "This link is too long to type — the code carries it.",
                    fontSize = 13.sp,
                    color = Color(0xFF9A9A9A),
                    modifier = Modifier.padding(top = 16.dp),
                )
            }
            if (reportUrl != null) {
                val focus = remember { androidx.compose.ui.focus.FocusRequester() }
                Box(
                    Modifier
                        .padding(top = 18.dp)
                        .tvFocusable(onClick = { reporting = !reporting }, focusRequester = focus)
                        .padding(horizontal = 18.dp, vertical = 8.dp),
                ) {
                    Text(if (reporting) "Share this film" else "Report a problem",
                        fontSize = 14.sp, color = Color.White)
                }
                androidx.compose.runtime.LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
            }
            Text(
                "Press Back to close",
                fontSize = 12.sp, color = Color(0xFF707070),
                modifier = Modifier.padding(top = 14.dp),
            )
        }
    }
}

internal fun qrBitmap(text: String, sizePx: Int): Bitmap? = runCatching {
    val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, sizePx, sizePx)
    val bmp = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.RGB_565)
    for (x in 0 until sizePx) for (y in 0 until sizePx) {
        bmp.setPixel(x, y, if (matrix.get(x, y)) AColor.BLACK else AColor.WHITE)
    }
    bmp
}.getOrNull()
