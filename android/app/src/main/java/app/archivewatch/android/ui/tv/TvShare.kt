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
import androidx.compose.runtime.remember
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
fun TvShareOverlay(title: String, url: String, onDone: () -> Unit) {
    androidx.activity.compose.BackHandler(true) { onDone() }
    val qr = remember(url) { qrBitmap(url, 640) }
    Box(Modifier.fillMaxSize().background(Color(0xCC000000))) {
        Column(
            Modifier
                .align(Alignment.Center)
                .background(Color(0xFF141414), RoundedCornerShape(18.dp))
                .padding(40.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("Share “$title”", fontSize = 20.sp, fontWeight = FontWeight.Medium, color = Color.White)
            Text(
                "Scan with your phone to open or send this film.",
                fontSize = 13.sp, color = Color(0xFF9A9A9A),
                modifier = Modifier.padding(top = 4.dp, bottom = 20.dp),
            )
            qr?.let {
                Box(Modifier.background(Color.White, RoundedCornerShape(12.dp)).padding(14.dp)) {
                    Image(it.asImageBitmap(), contentDescription = url, modifier = Modifier.size(280.dp))
                }
            }
            Text(url, fontSize = 13.sp, color = Color(0xFF9A9A9A), modifier = Modifier.padding(top = 16.dp))
            Text(
                "Press Back to close",
                fontSize = 12.sp, color = Color(0xFF707070),
                modifier = Modifier.padding(top = 14.dp),
            )
        }
    }
}

private fun qrBitmap(text: String, sizePx: Int): Bitmap? = runCatching {
    val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, sizePx, sizePx)
    val bmp = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.RGB_565)
    for (x in 0 until sizePx) for (y in 0 until sizePx) {
        bmp.setPixel(x, y, if (matrix.get(x, y)) AColor.BLACK else AColor.WHITE)
    }
    bmp
}.getOrNull()
