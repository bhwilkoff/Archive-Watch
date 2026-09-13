package app.archivewatch.android.data

import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.util.zip.Deflater

/**
 * A playlist you can hand to somebody, as a link.
 *
 * THE PLAYLIST IS THE LINK. There is no backend and no account here
 * (Decisions 009 and 028), and privacy.html promises a playlist never leaves
 * the device except through the viewer's own cloud. Measurement says no
 * service is needed: archive ids are short (median 23 characters), so
 * deflated and base64url'd a 50-title playlist is about 1,200 characters —
 * inside what messaging apps and QR codes carry without mangling.
 *
 * THE FORMAT IS THE WEB'S, and it has to be exactly: a link made on a Google
 * TV is opened in somebody else's browser. `js/watch.js`'s `ShareList` is the
 * reference. Raw DEFLATE is the codec because every platform already has it —
 * here that is `Deflater(level, nowrap = true)`, which is the same bytes
 * `deflate-raw` produces in a browser and `COMPRESSION_ZLIB` produces on
 * Apple.
 */
object PlaylistShare {

    /** Measured, not guessed: 50 real ids encode to ~1,223 characters. */
    const val LIMIT = 50

    fun blob(name: String, archiveIDs: List<String>): String {
        val json = JSONObject()
            .put("n", name.take(80))
            .put("i", JSONArray(archiveIDs))
            .toString()
            .toByteArray(Charsets.UTF_8)
        val deflated = deflate(json)
        // A '0' prefix means uncompressed — the variant that lets a platform
        // without deflate (Roku) share too. Everything that CAN compress does.
        return if (deflated != null) b64(deflated) else "0" + b64(json)
    }

    fun url(name: String, archiveIDs: List<String>): String? {
        if (archiveIDs.isEmpty() || archiveIDs.size > LIMIT) return null
        // the PATH is /list/ and the playlist rides the FRAGMENT: a browser never
        // sends a fragment to a server, so the list stays off ours, while the path
        // is what a native app can match (an Android intent filter cannot see a
        // fragment at all).
        // /list/ is also a real 200 page, and several crawlers decline to preview
        // a 404 — which matters for a link made to be posted.
        return "https://archivewatch.org/list/#" + blob(name, archiveIDs)
    }

    /** Raw DEFLATE — `nowrap = true` is what drops the zlib header. */
    private fun deflate(data: ByteArray): ByteArray? = runCatching {
        val d = Deflater(Deflater.BEST_COMPRESSION, true)
        d.setInput(data); d.finish()
        // Deflate can EXPAND incompressible input; a tight buffer here would
        // truncate silently, which is the worst possible failure for a link.
        val out = ByteArray(data.size + 1024)
        val n = d.deflate(out)
        d.end()
        if (n > 0) out.copyOf(n) else null
    }.getOrNull()

    private fun b64(b: ByteArray): String =
        Base64.encodeToString(b, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
}
