package app.archivewatch.android.ui.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material3.Text
import app.archivewatch.android.app.AppContainer
import app.archivewatch.android.studio.StudioRoom
import app.archivewatch.android.studio.StudioSyncClient
import app.archivewatch.android.studio.StudioSyncFollower
import app.archivewatch.android.ui.Nav
import app.archivewatch.android.ui.Route
import kotlinx.coroutines.launch

/**
 * JOIN A ROOM on a television — SHAREPLAY §11.9, the Android TV side.
 *
 * §11.10 is what allows this at all: Decision 132 removed the Watch Together
 * entry from these boxes because they cannot HOST — no camera, no microphone
 * — and JOINING needs neither. A television is in fact the best device to
 * join from, which is the owner's own case: on a call on a laptop, the film
 * on the big screen.
 *
 * **No keyboard**, for the same reason tvOS's version has none: a soft
 * keyboard on a television is a grid driven one character at a time with a
 * remote, and for four characters read aloud on a call that is the wrong
 * instrument. The screen IS the alphabet. Same shape as `JoinRoomTV.swift`
 * so the two televisions behave alike.
 */
@Composable
fun TvJoinRoomScreen(container: AppContainer, nav: Nav) {
    var typed by remember { mutableStateOf("") }
    var problem by remember { mutableStateOf<String?>(null) }
    var working by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    // Eight wide, so the alphabet is four rows and a full sweep is never more
    // than a few presses from anywhere.
    val rows = remember { StudioRoom.ALPHABET.chunked(8) }

    fun attempt(code: String) {
        working = true
        scope.launch {
            val client = StudioSyncClient()
            try {
                val state = client.join(code)
                client.leave()
                working = false
                val db = container.catalog.awaitDb()
                val item = db.itemsByIDs(listOf(state.filmID)).firstOrNull()
                if (item == null) {
                    problem = "That room is watching a film this device does not have in its catalog yet."
                    typed = ""
                    return@launch
                }
                // The player is where the ExoPlayer exists, so the code waits
                // there — the same hand-off every other platform uses.
                StudioSyncFollower.pending = code
                StudioSyncFollower.pendingFilm = item.archiveID
                nav.push(Route.Detail(item.archiveID))
            } catch (e: Exception) {
                working = false
                problem = StudioSyncFollower.sentence(e)
                typed = ""
            }
        }
    }

    fun append(ch: Char) {
        if (typed.length >= StudioRoom.CODE_LENGTH) return
        problem = null
        typed += ch
        if (typed.length == StudioRoom.CODE_LENGTH) {
            val code = StudioRoom.normalize(typed)
            if (code == null) { problem = "That is not a room code."; typed = "" }
            else attempt(code)
        }
    }

    Column(
        Modifier.fillMaxWidth().padding(horizontal = TvDims.OverscanH, vertical = TvDims.OverscanV),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("Join a room", fontSize = 34.sp, fontWeight = FontWeight.Bold, color = Color.White)
        Spacer(Modifier.size(10.dp))
        Text(
            "Enter the code your host reads out.",
            fontSize = 15.sp, color = Color(0xFF8A8F98), textAlign = TextAlign.Center,
            modifier = Modifier.width(700.dp),
        )
        Spacer(Modifier.size(22.dp))

        // The slots are DRAWN, empty ones included: from a sofa, "how many
        // more do I type" must be answerable at a glance.
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            repeat(StudioRoom.CODE_LENGTH) { i ->
                val ch = typed.getOrNull(i)?.toString() ?: ""
                Box(
                    Modifier.size(width = 64.dp, height = 80.dp)
                        .clip(RoundedCornerShape(10.dp))
                        .background(Color.White.copy(alpha = if (ch.isEmpty()) 0.06f else 0.14f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(ch, fontSize = 44.sp, fontWeight = FontWeight.Bold,
                         fontFamily = FontFamily.Monospace, color = Color.White)
                }
            }
        }

        problem?.let {
            Spacer(Modifier.size(14.dp))
            Text(it, fontSize = 15.sp, color = Color(0xFFFFA726),
                 textAlign = TextAlign.Center, modifier = Modifier.width(700.dp))
        }
        if (working) { Spacer(Modifier.size(14.dp)); Text("Joining…", color = Color.White) }

        Spacer(Modifier.size(22.dp))
        rows.forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.padding(bottom = 10.dp)) {
                row.forEach { ch -> KeyCell(ch.toString()) { append(ch) } }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            KeyCell("Delete", wide = true) { if (typed.isNotEmpty()) { typed = typed.dropLast(1); problem = null } }
        }
    }
}

@Composable
private fun KeyCell(label: String, wide: Boolean = false, onPress: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    Box(
        Modifier
            .size(width = if (wide) 140.dp else 58.dp, height = 52.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(if (focused) Color.White else Color.White.copy(alpha = 0.10f))
            // The focus ring is the affordance on a ten-foot screen; without a
            // visible one a remote is being driven blind (TV-DESIGN §3.1).
            .border(2.dp, if (focused) Color.White else Color.Transparent, RoundedCornerShape(8.dp))
            .onFocusChanged { focused = it.isFocused }
            .focusable()
            .clickable { onPress() },
        contentAlignment = Alignment.Center,
    ) {
        Text(label, fontSize = if (wide) 16.sp else 22.sp, fontWeight = FontWeight.SemiBold,
             fontFamily = if (wide) FontFamily.Default else FontFamily.Monospace,
             color = if (focused) Color.Black else Color.White)
    }
}
