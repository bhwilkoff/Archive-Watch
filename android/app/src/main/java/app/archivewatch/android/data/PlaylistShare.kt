package app.archivewatch.android.data

import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import android.net.Uri
import java.util.zip.Deflater
import java.util.zip.Inflater

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

    /** What a shared link carries. */
    data class Shared(val name: String, val archiveIDs: List<String>)

    /**
     * Pull the blob out of a share link, in either shape it has ever had.
     *
     * `/list/#<blob>` is what every platform emits now; `#/list/<blob>` shipped
     * first and is already in the wild. Links are permanent, so both are read
     * forever — only encoders ever choose, the same rule the '0' prefix follows.
     *
     * NOTE the fragment. An Android intent filter matches the PATH and cannot
     * see a fragment at all, which is exactly why the path carries `/list/` and
     * the payload rides behind the `#`: the filter can match, and the playlist
     * still never reaches a server.
     */
    fun blobFrom(uri: Uri): String? {
        val s = uri.toString()
        s.indexOf("/list/#").let { if (it >= 0) return s.substring(it + 7).trim('/').ifEmpty { null } }
        s.indexOf("#/list/").let { if (it >= 0) return s.substring(it + 7).trim('/').ifEmpty { null } }
        // A blob written into the path instead. Nothing emits this; 404.html
        // accepts it, so this does too.
        val segs = uri.pathSegments
        val i = segs.indexOf("list")
        if (i >= 0 && i + 1 < segs.size) return segs[i + 1].ifEmpty { null }
        return null
    }

    /**
     * Decode a blob into the playlist it carries. A leading '0' is the
     * uncompressed variant Roku emits; anything else is raw DEFLATE.
     */
    fun decode(blob: String): Shared? = runCatching {
        // A shared link that will not open is a dead end for whoever was sent
        // it, so this says WHY rather than returning a silent null (the
        // project's own debugging rule). One line, only on failure.
        Log.d("AWSHARE", "decode len=" + blob.length + " prefix=" + blob.take(8))
        val bytes = if (blob.startsWith("0")) {
            Base64.decode(blob.substring(1), Base64.URL_SAFE)
        } else {
            inflate(Base64.decode(blob, Base64.URL_SAFE)) ?: return null
        }
        val o = JSONObject(String(bytes, Charsets.UTF_8))
        val arr = o.optJSONArray("i") ?: return null
        val ids = (0 until arr.length()).map { arr.getString(it) }
        // The name is optional on the wire; a playlist without one is still a
        // playlist, and the web's reference decoder says so too.
        Shared(o.optString("n", "Shared playlist").ifEmpty { "Shared playlist" }, ids)
    }.onFailure { Log.w("AWSHARE", "decode failed: " + it) }.getOrNull()

    fun sharedFrom(uri: Uri): Shared? {
        val b = blobFrom(uri)
        if (b == null) { Log.d("AWSHARE", "no blob in " + uri); return null }
        return decode(b)
    }

    /** Raw INFLATE, the inverse of the deflate below — `nowrap = true` again. */
    private fun inflate(data: ByteArray): ByteArray? = runCatching {
        val inf = Inflater(true)
        inf.setInput(data)
        // A playlist is small and bounded by LIMIT, so one generous buffer
        // beats a streaming decode. 64 KB is far past a 50-title payload.
        val out = ByteArray(64 * 1024)
        val n = inf.inflate(out)
        inf.end()
        if (n > 0) out.copyOf(n) else null
    }.getOrNull()

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
