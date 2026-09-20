package app.archivewatch.android.studio

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.core.content.ContextCompat
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * The host's voice.
 *
 * Android had NO microphone path of any kind until 2026-09-20 — no
 * `AudioRecord`, no `RECORD_AUDIO`, no mixer, nothing to duck and nothing to
 * duck under (WATCH-TOGETHER §9.qqqqq). Every Android broadcast carried the
 * film's audio and only that, which on a phone is most of the feature missing.
 *
 * **IT IS A SLAVE TO THE FILM'S CLOCK, DELIBERATELY.** The obvious design —
 * a mixer pulling both sources on its own cadence — is the one that broke
 * Android once already: §9.qq found video and audio 19.6 SECONDS apart
 * because they were stamped from two unrelated clocks, and the fix was to
 * give them one origin. So this does not drive anything. `StudioFilmAudioTap`
 * remains the timeline; when a film buffer arrives, whatever voice has
 * accumulated is mixed INTO it, and the same number of samples with the same
 * timestamps goes to the encoder. The microphone cannot move the clock
 * because it never touches it.
 *
 * **VOICE_COMMUNICATION, not MIC.** On a phone the film is playing out of the
 * same speakers the microphone is listening to, so a raw `MIC` source feeds
 * the film back into the broadcast on top of itself — an echo that gets worse
 * with every duck. `VOICE_COMMUNICATION` is the source Android documents as
 * carrying acoustic echo cancellation and noise suppression, which is exactly
 * the job here.
 *
 * **The backlog is BOUNDED at 120 ms**, for the reason tvOS measured on the
 * owner's own broadcast: a live voice that arrives late is worse than a live
 * voice with a gap. Owner, 2026-09-20, on the Apple TV version: *"the
 * microphone audio does not match with the video. The audio is about a second
 * later than the video so my words do not match my lips."* An unbounded ring
 * turns every stall into permanent lag, so the oldest audio is dropped rather
 * than queued.
 */
class StudioMicAudio : VoiceSource {

    /** Why the microphone is not running, or null. Never inferred (§4). */
    @Volatile var problem: String? = null
        private set

    /** RMS of the most recent voice, 0..1, for the readouts and the duck. */
    @Volatile override var level: Float = 0f
        private set

    /** Frames captured, and frames dropped for being too old to be live. */
    @Volatile var framesCaptured: Long = 0; private set
    @Volatile var framesDroppedForLatency: Long = 0; private set

    private var record: AudioRecord? = null
    private var thread: Thread? = null
    @Volatile private var running = false

    /** Interleaved to the FILM's channel count, so mixing is a plain add. */
    private var ring = ShortArray(0)
    private var writeIndex = 0
    private var available = 0
    private var maxBacklog = 0
    private var channels = 2
    private val lock = Object()

    /**
     * Opens the microphone at the FILM's rate and channel count.
     *
     * The rate is not negotiable: mixing into the film's own buffers means
     * sample for sample, and a mismatch would pitch-shift the host's voice.
     * If the device will not record at that rate this returns false and says
     * so, rather than opening at some other rate and sounding wrong — the
     * alternative would be a resampler on the capture path, and §8.17 is a
     * fresh reminder of how badly a careless one behaves.
     */
    fun start(context: Context, sampleRate: Int, filmChannels: Int): Boolean {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED) {
            problem = "Microphone permission has not been granted, so your voice is not in the show."
            return false
        }
        if (sampleRate <= 0) { problem = "The film's sample rate is not known yet."; return false }
        channels = if (filmChannels >= 2) 2 else 1

        val min = AudioRecord.getMinBufferSize(
            sampleRate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (min == AudioRecord.ERROR || min == AudioRecord.ERROR_BAD_VALUE) {
            problem = "This device cannot record at the film's rate (${sampleRate} Hz), " +
                      "so your voice would be the wrong pitch."
            return false
        }
        // Four times the minimum: enough that a scheduling hiccup does not
        // drop input, and small enough that the bound below still governs.
        val bufBytes = min * 4

        val r = try {
            AudioRecord(MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                        sampleRate, AudioFormat.CHANNEL_IN_MONO,
                        AudioFormat.ENCODING_PCM_16BIT, bufBytes)
        } catch (e: Exception) {
            problem = "The microphone could not be opened: ${e.message}"
            return false
        }
        if (r.state != AudioRecord.STATE_INITIALIZED) {
            problem = "The microphone could not be initialised."
            r.release(); return false
        }

        synchronized(lock) {
            // One second of headroom; 120 ms of it is ever allowed to be used.
            ring = ShortArray(sampleRate * channels)
            writeIndex = 0; available = 0
            maxBacklog = (sampleRate * 0.120).toInt() * channels
        }

        record = r
        running = true
        problem = null
        r.startRecording()
        thread = Thread({ pump(r, sampleRate) }, "aw-studio-mic").also {
            it.priority = Thread.MAX_PRIORITY      // capture is real-time-ish
            it.start()
        }
        return true
    }

    private fun pump(r: AudioRecord, sampleRate: Int) {
        val mono = ShortArray(1024)
        while (running) {
            val n = try { r.read(mono, 0, mono.size) } catch (e: Exception) { -1 }
            if (n <= 0) {
                if (n < 0) { problem = "The microphone stopped delivering (code $n)." ; break }
                continue
            }
            var sum = 0.0
            for (i in 0 until n) { val v = mono[i] / 32768f; sum += (v * v).toDouble() }
            level = sqrt(sum / n).toFloat()
            framesCaptured += n
            synchronized(lock) { writeInterleaved(mono, n) }
        }
    }

    /** Mono in, the film's channel count out — the same voice in both ears. */
    private fun writeInterleaved(mono: ShortArray, frames: Int) {
        val cap = ring.size
        if (cap == 0) return
        val samples = frames * channels
        for (i in 0 until frames) {
            val v = mono[i]
            for (c in 0 until channels) {
                ring[writeIndex] = v
                writeIndex = (writeIndex + 1) % cap
            }
        }
        available = minOf(cap, available + samples)
        // THE BOUND. Past 120 ms the OLDEST audio is discarded, because it is
        // no longer live and shipping it only makes the host later.
        if (available > maxBacklog) {
            framesDroppedForLatency += ((available - maxBacklog) / channels).toLong()
            available = maxBacklog
        }
    }

    /**
     * Reads up to [samples] interleaved samples, OLDEST FIRST, into [out].
     * Returns how many were real; the rest of [out] is untouched.
     *
     * FIFO, and that word is load-bearing. The Apple ring computed its start
     * as `writeIndex - have` — the NEWEST samples — and silently discarded
     * everything buffered behind them. What went to air was real audio at the
     * right level with the right spectrum and no discontinuities, fragmented
     * beyond recognition, and six instruments called it clean for a day
     * (§9.jjjjj). The start is `writeIndex - available`.
     */
    override fun read(out: ShortArray, samples: Int): Int = synchronized(lock) {
        val cap = ring.size
        if (cap == 0 || available == 0) return 0
        val have = minOf(available, samples, out.size)
        var idx = ((writeIndex - available) % cap + cap) % cap
        for (i in 0 until have) {
            out[i] = ring[idx]
            idx = (idx + 1) % cap
        }
        available -= have
        return have
    }

    fun stop() {
        running = false
        thread?.join(500)
        thread = null
        try { record?.stop() } catch (_: Exception) {}
        try { record?.release() } catch (_: Exception) {}
        record = null
        level = 0f
        synchronized(lock) { available = 0; writeIndex = 0 }
    }
}
