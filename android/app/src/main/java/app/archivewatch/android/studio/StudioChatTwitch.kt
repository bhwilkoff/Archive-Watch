package app.archivewatch.android.studio

// Twitch chat, read ANONYMOUSLY, for the chat the program carries
// (docs/WATCH-TOGETHER.md §4, §6.4).
//
// The Kotlin counterpart of the Swift reader, and it exists for the same
// reason: Twitch's historical IRC interface accepts `NICK justinfan<digits>`
// with NO PASSWORD AND NO ACCOUNT, so this half of chat was never blocked on
// the owner registering anything. Verified against tmi.twitch.tv from this
// machine with no credential before either client was written.
//
// A raw SSLSocket on its own thread rather than a library: this project ships
// no third-party networking (Decision 127), the protocol is line-oriented
// text, and the whole client is smaller than the dependency would be.
//
// READ ONLY. It never sends a message and never authenticates, so it cannot
// be mistaken for the host speaking.

import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory
import kotlin.random.Random

data class ChatLine(val id: String, val author: String, val text: String, val isEvent: Boolean)

class StudioChatTwitch {

    @Volatile var joined = false; private set
    @Volatile var linesReceived = 0L; private set
    @Volatile var eventsReceived = 0L; private set
    @Volatile var lastError: String? = null; private set

    private val lock = Object()
    private val buffer = ArrayList<ChatLine>()
    private var thread: Thread? = null
    @Volatile private var running = false
    private var socket: SSLSocket? = null

    var maxLines = 200

    /** A snapshot, oldest first. Copied under the lock: the render thread
     *  reads this while the reader thread appends. */
    fun snapshot(): List<ChatLine> = synchronized(lock) { ArrayList(buffer) }

    fun start(channel: String) {
        if (running) return
        running = true
        val name = channel.removePrefix("#").lowercase()
        val t = Thread({ readLoop(name) }, "aw-twitch-chat")
        t.isDaemon = true
        thread = t
        t.start()
    }

    fun stop() {
        running = false
        try { socket?.close() } catch (_: Exception) {}
        socket = null
        joined = false
    }

    private fun readLoop(channel: String) {
        while (running) {
            try {
                val s = (SSLSocketFactory.getDefault() as SSLSocketFactory)
                    .createSocket("irc.chat.twitch.tv", 6697) as SSLSocket
                s.soTimeout = 330_000      // Twitch pings well inside this
                socket = s
                val out = OutputStreamWriter(s.outputStream, Charsets.UTF_8)
                val input = BufferedReader(InputStreamReader(s.inputStream, Charsets.UTF_8))
                // The tags capability is what carries display-name, color and
                // the message id; without it every line is a bare login.
                out.write("CAP REQ :twitch.tv/tags twitch.tv/commands\r\n")
                out.write("NICK justinfan${Random.nextInt(10_000, 99_999)}\r\n")
                out.write("JOIN #$channel\r\n")
                out.flush()
                lastError = null

                while (running) {
                    val line = input.readLine() ?: break
                    // An unanswered PING ends the connection within minutes,
                    // and the symptom is a chat that simply stops.
                    if (line.startsWith("PING")) {
                        out.write("PONG :tmi.twitch.tv\r\n"); out.flush(); continue
                    }
                    if (line.contains(" 376 ")) { joined = true; continue }
                    handle(line)
                }
            } catch (e: Exception) {
                lastError = e.message ?: e.toString()
            } finally {
                try { socket?.close() } catch (_: Exception) {}
                joined = false
            }
            if (running) {
                // Chat is not the broadcast: an unhurried retry costs the host
                // nothing and Twitch rate-limits a hammering one anyway.
                try { Thread.sleep(5_000) } catch (_: InterruptedException) { return }
            }
        }
    }

    private fun handle(line: String) {
        val (tags, rest) = splitTags(line)
        when (command(rest)) {
            "PRIVMSG" -> {
                val body = trailing(rest) ?: return
                val author = tags["display-name"]?.takeIf { it.isNotEmpty() } ?: nick(rest) ?: "someone"
                append(ChatLine(tags["id"] ?: java.util.UUID.randomUUID().toString(),
                                author, body, false))
                linesReceived++
            }
            "USERNOTICE" -> {
                val author = tags["display-name"] ?: "Twitch"
                val body = tags["system-msg"] ?: trailing(rest) ?: "joined in"
                append(ChatLine(tags["id"] ?: java.util.UUID.randomUUID().toString(),
                                author, body, true))
                eventsReceived++
            }
        }
    }

    private fun append(l: ChatLine) = synchronized(lock) {
        buffer.add(l)
        while (buffer.size > maxLines) buffer.removeAt(0)
    }

    companion object {
        /** Tag values are escaped: `\s` is a space, `\:` a semicolon. */
        fun splitTags(line: String): Pair<Map<String, String>, String> {
            if (!line.startsWith("@")) return emptyMap<String, String>() to line
            val sp = line.indexOf(' ')
            if (sp < 0) return emptyMap<String, String>() to line
            val tags = HashMap<String, String>()
            for (pair in line.substring(1, sp).split(';')) {
                val i = pair.indexOf('=')
                val k = if (i < 0) pair else pair.substring(0, i)
                val v = if (i < 0) "" else pair.substring(i + 1)
                tags[k] = v.replace("\\s", " ").replace("\\:", ";").replace("\\\\", "\\")
            }
            return tags to line.substring(sp + 1)
        }

        fun command(rest: String): String? {
            val parts = rest.split(' ').filter { it.isNotEmpty() }.toMutableList()
            if (parts.firstOrNull()?.startsWith(":") == true) parts.removeAt(0)
            return parts.firstOrNull()
        }

        fun nick(rest: String): String? {
            if (!rest.startsWith(":")) return null
            val bang = rest.indexOf('!')
            return if (bang > 1) rest.substring(1, bang) else null
        }

        /** Everything after the FIRST " :" past the command. Splitting on every
         *  colon breaks any message containing one, which is most links. */
        fun trailing(rest: String): String? {
            val i = rest.indexOf(" :")
            return if (i < 0) null else rest.substring(i + 2)
        }
    }
}
