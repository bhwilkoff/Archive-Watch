package app.archivewatch.android.studio

import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.abs

/**
 * The 0-10 level the host reads, and its one conversion to a linear gain.
 *
 * The SAME scale as every other platform — tvOS-DESIGN Rule 8.8c, iOS-DESIGN
 * §8.8c, macOS-DESIGN §B13h. Owner, 2026-09-20: *"a scale of 0 to 10 rather
 * than ... decibles that most people won't understand"*, which is a statement
 * about people and not about televisions.
 *
 * 8 is unity — the source's own level, and the default, so a host who never
 * opens the panel is already there. 0-8 cuts 5 dB a step to silence; 8-10
 * boosts 3 dB a step to the same +6 dB ceiling Apple uses. The boost is not
 * decoration: Apple measured a host speaking beside the phone at RMS
 * 0.007-0.023, which is quiet enough to need somewhere to go.
 */
object MixLevel {
    const val UNITY = 8.0
    const val MAXIMUM = 10.0

    fun decibels(level: Double): Double =
        if (level > UNITY) (level - UNITY) * 3 else (level - UNITY) * 5

    fun gain(level: Double): Float =
        if (level <= 0) 0f else 10.0.pow(decibels(minOf(level, MAXIMUM)) / 20.0).toFloat()

    fun level(gain: Float): Double {
        if (gain <= 0.0001f) return 0.0
        val dB = 20 * log10(gain.toDouble())
        val l = if (dB > 0) UNITY + dB / 3 else UNITY + dB / 5
        return minOf(MAXIMUM, maxOf(0.0, l))
    }

    /** An RMS reading on the FADER's scale — a linear meter reads as dead. */
    fun meterFraction(rms: Float): Double = level(rms) / MAXIMUM

    fun text(level: Double): String = String.format("%.1f", level)
}

/**
 * Mixes the host's voice INTO the film's own PCM buffers.
 *
 * **It does not pull, and that is the whole design.** `StudioFilmAudioTap` is
 * the timeline: when a film buffer arrives it is mixed in place and handed to
 * the AAC encoder with its own timestamps untouched. A mixer that pulled both
 * sources on its own cadence would be a second clock, and §9.qq is what a
 * second clock cost Android last time — video and audio 19.6 SECONDS apart,
 * invisible until audio existed on the product path at all.
 *
 * The buffers are little-endian interleaved Int16, which is what the tap
 * delivers (`StudioFilmAudioTap.handleBuffer`).
 */
/**
 * What the mixer needs from a voice, and nothing more.
 *
 * `StudioMicAudio` cannot be built in a JVM unit test — `AudioRecord` and
 * `Context` are device APIs — so a mixer that named it directly could only be
 * tested on hardware, which is the one place this cannot currently run (the
 * Pixel's adb pairing is expired and no television has a microphone). An
 * interface makes the MIXING testable on its own, which is where the rules
 * live: the gains, the duck, the clip. The capture stays untestable off a
 * device and is honest about that.
 */
interface VoiceSource {
    /** RMS of the most recent voice, 0..1 — what the duck decides on. */
    val level: Float
    /** Oldest-first, returning how many samples were real. */
    fun read(out: ShortArray, samples: Int): Int
}

class StudioAudioMix {

    /** §4's faders, as linear gain. 1.0 is unity, i.e. level 8. */
    @Volatile var filmGain: Float = 1f
    @Volatile var micGain: Float = 1f
    @Volatile var filmMuted: Boolean = false
    @Volatile var micMuted: Boolean = false

    /**
     * Rule 8.8c's third state. On by default, because the duck is right for a
     * host who has not thought about it — and a SETTING, because otherwise
     * the fader lies: a host who sets Film to 9 and then speaks hears it drop
     * 12 dB anyway and reasonably concludes the control is broken.
     */
    @Volatile var duckEnabled: Boolean = true

    /** Whether the film is ducking right now, for the readout. */
    @Volatile var ducking: Boolean = false
        private set

    /** Peak of the mixed result, 0..1 — what the audience actually gets. */
    @Volatile var programLevel: Float = 0f
        private set

    private var scratch = ShortArray(0)
    /** Smoothed, so a duck is a fade and not a click. */
    private var duckGain = 1f

    private val duckThreshold = 0.02f
    private val duckDecibels = -12.0

    /**
     * Mixes in place. [pcm] is little-endian interleaved Int16 at
     * [channelCount] channels; [mic] contributes whatever voice it has.
     */
    fun mixInto(pcm: ByteArray, channelCount: Int, mic: VoiceSource?) {
        val samples = pcm.size / 2
        if (samples <= 0) return

        val micRms = mic?.level ?: 0f
        val wantDuck = duckEnabled && !micMuted && mic != null && micRms > duckThreshold
        ducking = wantDuck
        val target = if (wantDuck) 10.0.pow(duckDecibels / 20.0).toFloat() else 1f
        // ~30 ms of smoothing at 44.1 kHz, applied per buffer rather than per
        // sample: the buffers are short and a per-sample ramp here would cost
        // more than it buys.
        duckGain += (target - duckGain) * 0.25f

        var micHave = 0
        if (mic != null && !micMuted) {
            if (scratch.size < samples) scratch = ShortArray(samples)
            micHave = mic.read(scratch, samples)
        }

        val fg = (if (filmMuted) 0f else filmGain) * duckGain
        val mg = if (micMuted) 0f else micGain
        var peak = 0f

        var i = 0
        var s = 0
        while (s < samples) {
            val lo = pcm[i].toInt() and 0xFF
            val hi = pcm[i + 1].toInt()
            val film = ((hi shl 8) or lo).toShort().toInt()
            var v = film * fg
            if (s < micHave) v += scratch[s] * mg
            // CLIP RATHER THAN WRAP. An Int16 that overflows wraps to the
            // opposite sign, which is not loud — it is a crack on every peak,
            // and it would be blamed on the encoder.
            val out = when {
                v > 32767f -> 32767
                v < -32768f -> -32768
                else -> v.toInt()
            }
            val a = abs(out) / 32768f
            if (a > peak) peak = a
            pcm[i] = (out and 0xFF).toByte()
            pcm[i + 1] = ((out shr 8) and 0xFF).toByte()
            i += 2
            s += 1
        }
        programLevel = peak
    }
}
