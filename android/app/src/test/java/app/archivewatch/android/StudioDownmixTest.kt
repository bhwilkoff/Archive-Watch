package app.archivewatch.android

import app.archivewatch.android.studio.StudioFilmAudioTap
import org.junit.Assert.assertEquals
import org.junit.Test

class StudioDownmixTest {
    private fun pcm(vararg s: Int) = ByteArray(s.size * 2).also { b ->
        s.forEachIndexed { i, v -> b[i * 2] = v.toByte(); b[i * 2 + 1] = (v shr 8).toByte() }
    }
    private fun samples(b: ByteArray) = (0 until b.size / 2).map {
        ((b[it * 2 + 1].toInt() shl 8) or (b[it * 2].toInt() and 0xFF)).toShort().toInt()
    }

    @Test fun fivePointOneFoldsToOneStereoFramePerFrame() {
        // two frames: FL FR FC LFE BL BR
        val out = StudioFilmAudioTap.toStereo(pcm(1000, 0, 0, 30000, 0, 0, 0, 0, 1000, 0, 0, 0), 6)
        val s = samples(out)
        assertEquals(4, s.size)                  // 2 frames x 2 channels
        assertEquals(414, s[0]); assertEquals(0, s[1])   // FL alone, normalised
        assertEquals(292, s[2]); assertEquals(292, s[3]) // centre to both at -3 dB
    }

    @Test fun lfeIsDroppedAndFullScaleDoesNotClip() {
        val out = samples(StudioFilmAudioTap.toStereo(pcm(32767, 32767, 32767, 32767, 32767, 32767), 6))
        assertEquals(listOf(32767, 32767), out.map { minOf(it, 32767) })
        assert(out.all { it in 32000..32767 })
        // control: LFE alone contributes nothing
        assertEquals(listOf(0, 0), samples(StudioFilmAudioTap.toStereo(pcm(0, 0, 0, 32767, 0, 0), 6)))
    }

    @Test fun otherLayoutsKeepTheFrontPair() {
        assertEquals(listOf(5, 6), samples(StudioFilmAudioTap.toStereo(pcm(5, 6, 7, 8), 4)))
    }
}
