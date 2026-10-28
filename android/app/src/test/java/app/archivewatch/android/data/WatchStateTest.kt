package app.archivewatch.android.data

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.sql.Connection
import java.sql.DriverManager

/** Continue Watching asked in SQL (B16), and an un-mark that sticks (B11). */
class WatchStateTest {

    private lateinit var db: Connection

    @Before
    fun open() {
        db = DriverManager.getConnection("jdbc:sqlite::memory:")
        db.createStatement().use {
            it.execute("CREATE TABLE progress (id TEXT PRIMARY KEY, position INTEGER, duration INTEGER, " +
                "at INTEGER, firstAt INTEGER, plays INTEGER, everDone INTEGER DEFAULT 0)")
        }
    }

    @After
    fun close() = db.close()

    private fun row(id: String, pos: Long, dur: Long, at: Long) {
        db.prepareStatement("INSERT INTO progress (id, position, duration, at) VALUES (?, ?, ?, ?)").use {
            it.setString(1, id); it.setLong(2, pos); it.setLong(3, dur); it.setLong(4, at); it.executeUpdate()
        }
    }

    private fun run(sql: String, limit: Long): List<String> =
        db.prepareStatement(sql).use { st ->
            st.setLong(1, limit)
            st.executeQuery().use { rs -> buildList { while (rs.next()) add(rs.getString(1)) } }
        }

    private fun seed() {
        // 200 newer rows that are not resumable: recorded at 0, or finished.
        for (i in 0 until 200) row("done$i", if (i % 2 == 0) 0 else 5_900_000, 6_000_000, 10_000L + i)
        row("half", 3_000_000, 6_000_000, 1_000)
        row("start", 60_000, 6_000_000, 900)
        row("edge95", 5_700_000, 6_000_000, 800)   // exactly 95%: complete, not resumable
        row("tiny", 1_500, 6_000_000, 700)         // under 2 s: never started
    }

    @Test
    fun `resumable films survive a long history of finished ones`() {
        seed()
        assertEquals(listOf("half", "start"), run(UserStateStore.CONTINUE_WATCHING_SQL, 30))
    }

    @Test
    fun `control - the old window filtered in Kotlin loses them`() {
        seed()
        val old = "SELECT id, position, duration, at FROM progress ORDER BY at DESC LIMIT ?"
        val window = db.prepareStatement(old).use { st ->
            st.setLong(1, 30L * 4)
            st.executeQuery().use { rs ->
                buildList { while (rs.next()) add(WatchProgress(rs.getString(1), rs.getLong(2), rs.getLong(3), rs.getLong(4))) }
            }
        }
        assertTrue(window.none { it.isResumable })
    }

    @Test
    fun `the SQL agrees with isResumable row by row`() {
        seed()
        val sqlIDs = run(UserStateStore.CONTINUE_WATCHING_SQL, 10_000).toSet()
        val all = db.prepareStatement("SELECT id, position, duration, at FROM progress").use { st ->
            st.executeQuery().use { rs ->
                buildList { while (rs.next()) add(WatchProgress(rs.getString(1), rs.getLong(2), rs.getLong(3), rs.getLong(4))) }
            }
        }
        assertEquals(all.filter { it.isResumable }.map { it.archiveID }.toSet(), sqlIDs)
    }

    @Test
    fun `un-marking a finished film starts it over and stamps it now`() {
        val (pos, at) = UserStateStore.unmarkedProgress(5_800_000, 6_000_000, now = 99)
        assertEquals(0L, pos)
        assertEquals(99L, at)
        assertFalse(WatchProgress("x", pos, 6_000_000, at).isComplete)
    }

    @Test
    fun `control - un-marking a film mid-way keeps its place`() {
        val (pos, at) = UserStateStore.unmarkedProgress(3_000_000, 6_000_000, now = 99)
        assertEquals(3_000_000L, pos)
        assertEquals(99L, at)
    }

    @Test
    fun `a newer un-mark from the cloud wins`() {
        assertFalse(UserStateStore.mergedEverDone(mineDone = true, mineAt = 10, cloudDone = false, cloudAt = 20))
    }

    @Test
    fun `an older cloud record cannot clear a completion`() {
        assertTrue(UserStateStore.mergedEverDone(mineDone = true, mineAt = 20, cloudDone = false, cloudAt = 10))
    }

    @Test
    fun `control - a completion anywhere still counts, and a record without the field only adds`() {
        assertTrue(UserStateStore.mergedEverDone(mineDone = false, mineAt = 10, cloudDone = true, cloudAt = 20))
        assertTrue(UserStateStore.mergedEverDone(mineDone = true, mineAt = 10, cloudDone = null, cloudAt = 20))
        assertTrue(UserStateStore.mergedEverDone(mineDone = null, mineAt = 0, cloudDone = true, cloudAt = 5))
        assertFalse(UserStateStore.mergedEverDone(mineDone = null, mineAt = 0, cloudDone = null, cloudAt = 5))
    }
}
