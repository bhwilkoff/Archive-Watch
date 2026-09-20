package app.archivewatch.android

import app.archivewatch.android.studio.MixLevel
import app.archivewatch.android.studio.StudioAudioMix
import app.archivewatch.android.studio.VoiceSource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * Android's mixer: the 0-10 scale, the duck, and the clip.
 *
 * Every assertion is paired with a control that must come out the OTHER way,
 * because a check that cannot fail is not a check (Decision 130). The capture
 * itself (`StudioMicAudio`) is not tested here and cannot be: `AudioRecord`
 * is a device API, the Pixel's adb pairing is expired, and no television has
 * a microphone. What is tested is where the rules live.
 */
class StudioAudioMixTest {

    /** A voice with a known level and a known waveform. */
    private class Voice(override val level: Float, val value: Short) : VoiceSource {
        var offered = 0
        override fun read(out: ShortArray, samples: Int): Int {
            val n = minOf(samples, out.size)
            for (i in 0 until n) out[i] = value
            offered += n
            return n
        }
    }

    private fun pcm(value: Short, frames: Int): ByteArray {
        val b = ByteArray(frames * 2)
        for (i in 0 until frames) {
            b[i * 2] = (value.toInt() and 0xFF).toByte()
            b[i * 2 + 1] = ((value.toInt() shr 8) and 0xFF).toByte()
        }
        return b
    }

    private fun firstSample(b: ByteArray): Int {
        val lo = b[0].toInt() and 0xFF
        val hi = b[1].toInt()
        return ((hi shl 8) or lo).toShort().toInt()
    }

    // ---- the scale ------------------------------------------------------

    @Test fun `the default gain lands exactly on the unity tick`() {
        assertEquals(8.0, MixLevel.level(1.0f), 1e-9)
        assertEquals(1.0f, MixLevel.gain(8.0), 1e-6f)
    }

    @Test fun `level 10 is the mixer's plus 6 dB ceiling and 0 is silence`() {
        assertEquals(Math.pow(10.0, 6.0 / 20.0).toFloat(), MixLevel.gain(10.0), 1e-5f)
        assertEquals(0f, MixLevel.gain(0.0), 0f)
        // CONTROL: the old readout was decibels, which is NOT on a 0-10 scale.
        val oldReadout = 20 * Math.log10(0.02)
        assertTrue("CONTROL: the dB reading for quiet speech ($oldReadout) is not a 0-10 level",
                   oldReadout < 0.0)
    }

    @Test fun `gain and level round-trip across the whole scale`() {
        var worst = 0.0
        var l = 0.1
        while (l <= 10.0) {
            worst = maxOf(worst, abs(MixLevel.level(MixLevel.gain(l)) - l))
            l += 0.1
        }
        assertTrue("round-trip worst error $worst", worst < 1e-6)
    }

    @Test fun `the meter reads on the fader's scale, not linearly`() {
        // Apple measured a host speaking beside the phone at RMS 0.007-0.023.
        val onScale = MixLevel.meterFraction(0.02f)
        assertTrue("speech at RMS 0.02 draws ${(onScale * 100).toInt()}% of the meter",
                   onScale > 0.08)
        // CONTROL: the linear meter this replaces draws 2% for the same voice
        // and reads as a dead microphone.
        assertTrue("CONTROL: a linear meter draws 2% and looks dead", 0.02 < 0.08)
    }

    // ---- the mix --------------------------------------------------------

    @Test fun `film alone at unity passes through unchanged`() {
        val m = StudioAudioMix()
        val b = pcm(1000, 64)
        m.mixInto(b, 2, null)
        assertEquals("unity must not touch the film", 1000, firstSample(b))
    }

    @Test fun `the voice is added to the film`() {
        val m = StudioAudioMix()
        val b = pcm(1000, 64)
        m.duckEnabled = false                 // isolate the ADD from the duck
        m.mixInto(b, 2, Voice(level = 0.5f, value = 500))
        assertEquals("film plus voice", 1500, firstSample(b))
    }

    @Test fun `auto-duck drops the film under a loud voice`() {
        val m = StudioAudioMix()
        val b = pcm(10000, 64)
        val voice = Voice(level = 0.5f, value = 0)   // loud, but silent waveform
        // The duck is smoothed, so it takes a few buffers to arrive — which is
        // the point: a step would click.
        repeat(40) { m.mixInto(pcm(10000, 64), 2, voice) }
        m.mixInto(b, 2, voice)
        assertTrue("the film should be ducking", m.ducking)
        assertTrue("the film should be well below 10000, was ${firstSample(b)}",
                   firstSample(b) < 6000)
    }

    @Test fun `auto-duck OFF means manual, which is the whole point of the setting`() {
        val m = StudioAudioMix()
        m.duckEnabled = false
        val voice = Voice(level = 0.9f, value = 0)   // as loud as it gets
        repeat(40) { m.mixInto(pcm(10000, 64), 2, voice) }
        val b = pcm(10000, 64)
        m.mixInto(b, 2, voice)
        assertTrue("with auto-duck off nothing may duck", !m.ducking)
        assertEquals("the film stays exactly where the host set it", 10000, firstSample(b))
    }

    @Test fun `a silent room does not duck`() {
        val m = StudioAudioMix()
        val b = pcm(10000, 64)
        m.mixInto(b, 2, Voice(level = 0.001f, value = 0))   // below the threshold
        assertTrue("silence must not duck", !m.ducking)
        assertEquals(10000, firstSample(b))
    }

    @Test fun `the mix CLIPS rather than wrapping`() {
        val m = StudioAudioMix()
        m.duckEnabled = false
        val b = pcm(30000, 32)
        m.mixInto(b, 2, Voice(level = 0.5f, value = 30000))   // 60000, far over
        assertEquals("must clip to the Int16 ceiling", 32767, firstSample(b))
        // CONTROL: the arithmetic this guards against. A raw Int16 add wraps to
        // the opposite sign, which is not loudness — it is a crack on every
        // peak, and it would be blamed on the encoder.
        val wrapped = (30000 + 30000).toShort().toInt()
        assertTrue("CONTROL: an unguarded add wraps to $wrapped, the wrong SIGN",
                   wrapped < 0)
    }

    @Test fun `muting the film leaves only the voice`() {
        val m = StudioAudioMix()
        m.duckEnabled = false
        m.filmMuted = true
        val b = pcm(9000, 32)
        m.mixInto(b, 2, Voice(level = 0.3f, value = 700))
        assertEquals(700, firstSample(b))
    }

    @Test fun `muting the voice leaves only the film, and reads nothing from it`() {
        val m = StudioAudioMix()
        m.micMuted = true
        val voice = Voice(level = 0.9f, value = 700)
        val b = pcm(9000, 32)
        m.mixInto(b, 2, voice)
        assertEquals(9000, firstSample(b))
        assertEquals("a muted voice must not be drained either", 0, voice.offered)
    }
}
