package app.archivewatch.android.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

/**
 * The TV copy pickers key one row per version. A merged upload often carries
 * the same file name as the title's own item — measured 2026-10-15: 3 of 40
 * sampled merged pairs, e.g. Betty_Boop_The_Candid_Candidate_1937 and its _944
 * twin both hold `The_Candid_Candidate_1937_512kb.mp4` — and keying by the bare
 * name crashed Compose's subcompose on Android TV (Play d1f2cb18, fe8e0f79).
 */
class ArchiveVersionsKeyTest {
    private fun v(item: String, name: String, other: Boolean) = ArchiveVersions.Version(
        name = name,
        url = "https://archive.org/download/$item/$name",
        sizeBytes = 40_000_000,
        format = "h.264",
        heightPixels = 480,
        isDerivative = true,
        sourceItemID = item,
        isOtherUpload = other,
    )

    private val shared = "The_Candid_Candidate_1937_512kb.mp4"

    @Test
    fun `the same file name on two uploads gives two distinct row keys`() {
        val out = ArchiveVersions.ordered(listOf(
            v("Betty_Boop_The_Candid_Candidate_1937", shared, other = false),
            v("Betty_Boop_The_Candid_Candidate_1937_944", shared, other = true),
        ))
        val keys = out.map { it.choiceKey }
        assertEquals(2, keys.size)
        assertEquals(keys.size, keys.toSet().size)
    }

    @Test
    fun `control - the bare name, the old key, repeats for the same pair`() {
        val out = ArchiveVersions.ordered(listOf(
            v("Betty_Boop_The_Candid_Candidate_1937", shared, other = false),
            v("Betty_Boop_The_Candid_Candidate_1937_944", shared, other = true),
        ))
        val names = out.map { it.name }
        assertNotEquals(names.size, names.toSet().size)
    }

    @Test
    fun `one upload listed twice yields one row per file`() {
        val item = "Betty_Boop_The_Candid_Candidate_1937_944"
        val out = ArchiveVersions.ordered(listOf(
            v(item, shared, other = true),
            v(item, shared, other = true),
        ))
        assertEquals(1, out.size)
    }
}
