package app.archivewatch.android.studio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The Kotlin side of a rule that exists in three languages.
 *
 * The input table below is the SAME one `tools/test_studio_room.swift` (§8.28)
 * and `tools/test_together_worker.mjs` (§8.29) assert. Keeping them identical
 * by hand is the point: a code is read aloud on a call and typed on another
 * device, so if two implementations disagree about what a heard "oh" means,
 * a guest reaches a different room and nothing says why.
 *
 * Same discipline as `StudioLayoutTest`, which pins the Kotlin placement
 * rects to the numbers §8.22 printed.
 */
class StudioRoomTest {

    @Test fun `the alphabet drops the confusable letters but keeps 0 and 1`() {
        for (bad in listOf('I', 'L', 'O', 'U')) {
            assertTrue("alphabet must not contain $bad", !StudioRoom.ALPHABET.contains(bad))
        }
        assertTrue(StudioRoom.ALPHABET.contains('0'))
        assertTrue(StudioRoom.ALPHABET.contains('1'))
        assertEquals(32, StudioRoom.ALPHABET.length)
    }

    @Test fun `a generated code is the right length and alphabet`() {
        repeat(200) {
            val c = StudioRoom.newCode()
            assertEquals(StudioRoom.CODE_LENGTH, c.length)
            assertTrue(c.all { StudioRoom.ALPHABET.contains(it) })
            assertEquals("a generated code must normalize to itself", c, StudioRoom.normalize(c))
        }
    }

    @Test fun `codes are not a constant`() {
        val seen = (1..200).map { StudioRoom.newCode() }.toSet()
        assertTrue("200 codes produced ${seen.size} distinct", seen.size > 150)
    }

    /** The §8.28 / §8.29 table, character for character. */
    @Test fun `a code typed the way it was heard reaches the same room`() {
        val cases = listOf(
            "ca11" to "CA11",       // lower case
            "CA 11" to "CA11",      // spaces ignored
            "CA-11" to "CA11",      // dashes ignored
            "CAL1" to "CA11",       // a heard "ell"
            "CAI1" to "CA11",       // a heard "eye"
            "CALI" to "CA11",       // both at once
            "CODE" to "C0DE",       // a heard "oh"
            "C0DE" to "C0DE",       // a real zero, untouched
            "ABCD" to "ABCD",       // clean
        )
        for ((input, want) in cases) {
            assertEquals("normalize(\"$input\")", want, StudioRoom.normalize(input))
        }
        assertEquals(
            "every spelling must reach ONE room",
            1,
            listOf("CALI", "CAL1", "CAI1", "CA11", "ca11").map { StudioRoom.normalize(it) }.toSet().size,
        )
    }

    @Test fun `malformed codes are refused`() {
        for (bad in listOf("AB", "ABCDE", "AB!E", "ABUE", "", null)) {
            assertNull("normalize(\"$bad\") must be null", StudioRoom.normalize(bad))
        }
        // CONTROL: if everything were refused the assertions above would prove
        // nothing at all.
        assertEquals("XYZ9", StudioRoom.normalize("XYZ9"))
    }
}
