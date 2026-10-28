package app.archivewatch.android.data

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import java.sql.Connection
import java.sql.DriverManager

/** The grid orders, run against real rows (Apple `CatalogDB.browseSQL`). The
 *  defect they guard: Top Rated on television had no TVmaze rating and no tie
 *  break, so ~400 unrated series came back in slug order and read as A–Z. */
class BrowseSortOrderTest {

    private lateinit var db: Connection

    @Before
    fun open() {
        db = DriverManager.getConnection("jdbc:sqlite::memory:")
    }

    @After
    fun close() = db.close()

    private fun table(withTVmaze: Boolean, withRank: Boolean = false) {
        db.createStatement().use {
            it.execute(
                "CREATE TABLE items (archiveID TEXT, title TEXT, year INTEGER, imdbRating REAL, " +
                    "imdbVotes INTEGER, episodesCount INTEGER, hasRealArtwork INTEGER, " +
                    "artworkSource TEXT, popularityScore REAL" +
                    (if (withTVmaze) ", tvmazeRating REAL" else "") +
                    (if (withRank) ", ratingRank REAL" else "") + ")",
            )
        }
    }

    private fun ranked(id: String, title: String, imdb: Double?, votes: Int?, rank: Double?) {
        db.prepareStatement(
            "INSERT INTO items (archiveID, title, imdbRating, imdbVotes, episodesCount, hasRealArtwork, " +
                "artworkSource, popularityScore, tvmazeRating, ratingRank) VALUES (?, ?, ?, ?, 0, 1, NULL, 0, NULL, ?)",
        ).use { st ->
            st.setString(1, id); st.setString(2, title); st.setObject(3, imdb); st.setObject(4, votes)
            st.setObject(5, rank); st.executeUpdate()
        }
    }

    private fun row(id: String, title: String, year: Int? = null, imdb: Double? = null,
                    votes: Int? = null, eps: Int? = null, tvmaze: Double? = null) {
        val hasCol = db.metaData.getColumns(null, null, "items", "tvmazeRating").use { it.next() }
        val sql = "INSERT INTO items (archiveID, title, year, imdbRating, imdbVotes, episodesCount, " +
            "hasRealArtwork, artworkSource, popularityScore" + (if (hasCol) ", tvmazeRating" else "") +
            ") VALUES (?, ?, ?, ?, ?, ?, 1, NULL, 0" + (if (hasCol) ", ?" else "") + ")"
        db.prepareStatement(sql).use { st ->
            st.setString(1, id); st.setString(2, title)
            st.setObject(3, year); st.setObject(4, imdb); st.setObject(5, votes); st.setObject(6, eps)
            if (hasCol) st.setObject(7, tvmaze)
            st.executeUpdate()
        }
    }

    private fun ids(sort: BrowseSort, tvmaze: Boolean, demote: String = "", rank: Boolean = false): List<String> =
        db.createStatement().use { st ->
            st.executeQuery(
                "SELECT i.archiveID FROM items i ORDER BY " +
                    CatalogDatabase.orderSQL(sort, tvmaze, demote, rank),
            ).use { rs -> generateSequence { if (rs.next()) rs.getString(1) else null }.toList() }
        }

    @Test
    fun `Top Rated reads TVmaze for a series and breaks every tie`() {
        table(withTVmaze = true)
        row("zorro", "Zorro", eps = 78)                       // unrated, deep
        row("abbott", "Abbott and Costello", eps = 52)        // unrated
        row("adams", "Adams Family", eps = 52)                // unrated, same depth: by title
        row("film", "A Film", imdb = 7.0, votes = 100)
        row("series", "Bonanza", tvmaze = 8.1, eps = 430)
        row("tie1", "Tie Few Votes", imdb = 6.0, votes = 10)
        row("tie2", "Tie Many Votes", imdb = 6.0, votes = 900)
        assertEquals(listOf("series", "film", "tie2", "tie1", "zorro", "abbott", "adams"),
                     ids(BrowseSort.RATING, tvmaze = true))
    }

    @Test
    fun `Top Rated follows the pipeline's rank, not the raw rating`() {
        table(withTVmaze = true, withRank = true)
        ranked("vierte", "Der Vierte kommt nicht", imdb = 9.2, votes = 13, rank = 0.31)
        ranked("harakiri", "Harakiri", imdb = 8.6, votes = 90669, rank = 2.57)
        ranked("soundie", "Soundie", imdb = null, votes = null, rank = 1.21)   // archive.org reviewers
        ranked("plain", "Unrated", imdb = null, votes = null, rank = null)
        assertEquals(listOf("harakiri", "soundie", "vierte", "plain"),
                     ids(BrowseSort.RATING, tvmaze = true, rank = true))
        // control: the same rows by the raw rating put the 13-vote 9.2 first
        assertEquals("vierte", ids(BrowseSort.RATING, tvmaze = true, rank = false).first())
    }

    @Test
    fun `an older DB without the column still sorts, by IMDb alone`() {
        table(withTVmaze = false)
        row("b", "B", imdb = 5.0)
        row("a", "A", imdb = 8.0)
        row("n", "N")
        assertEquals(listOf("a", "b", "n"), ids(BrowseSort.RATING, tvmaze = false))
    }

    @Test
    fun `IMDb outranks TVmaze when an item carries both`() {
        table(withTVmaze = true)
        row("x", "X", imdb = 6.0, tvmaze = 9.5)
        row("y", "Y", imdb = 7.0)
        assertEquals(listOf("y", "x"), ids(BrowseSort.RATING, tvmaze = true))
    }

    @Test
    fun `A-Z ignores case and orders a shared title by year, Z-A reverses the title only`() {
        table(withTVmaze = true)
        row("k27", "King Kong", year = 1976)
        row("k33", "king kong", year = 1933)
        row("a", "Aelita", year = 1924)
        row("z", "zorro", year = 1957)
        assertEquals(listOf("a", "k33", "k27", "z"), ids(BrowseSort.ALPHABETICAL, tvmaze = true))
        assertEquals(listOf("z", "k33", "k27", "a"), ids(BrowseSort.REVERSE_ALPHABETICAL, tvmaze = true))
    }

    @Test
    fun `Oldest puts a missing year last`() {
        table(withTVmaze = true)
        row("none", "None")
        row("new", "New", year = 1950)
        row("old", "Old", year = 1910)
        assertEquals(listOf("old", "new", "none"), ids(BrowseSort.OLDEST, tvmaze = true))
    }

    @Test
    fun `demoted ids sort last under Top Rated`() {
        table(withTVmaze = true)
        row("demoted", "D", imdb = 9.0)
        row("plain", "P", imdb = 5.0)
        assertEquals(listOf("plain", "demoted"),
                     ids(BrowseSort.RATING, tvmaze = true, demote = "(i.archiveID IN ('demoted')) ASC, "))
    }

    @Test
    fun `persisted keys are the Apple raw values, and television defaults to A-Z`() {
        assertEquals(listOf("popular", "rating", "alphabetical", "reverseAlphabetical", "newest", "oldest"),
                     BrowseSort.entries.map { it.key })
        BrowseSort.entries.forEach { assertEquals(it, BrowseSort.fromKey(it.key)) }
        assertNull(BrowseSort.fromKey(null))
        assertEquals("Z–A", BrowseSort.REVERSE_ALPHABETICAL.label)
        assertEquals(BrowseSort.ALPHABETICAL, SortMemory.defaultSort(SortMemory.TV))
        assertEquals(BrowseSort.POPULAR, SortMemory.defaultSort(SortMemory.BROWSE))
        assertEquals(BrowseSort.POPULAR, SortMemory.defaultSort(SortMemory.CATEGORY))
        assertEquals(BrowseSort.POPULAR, SortMemory.defaultSort(SortMemory.COLLECTION))
        assertEquals(SortMemory.TV, SortMemory.surface("tv-series"))
        assertEquals(SortMemory.TV, SortMemory.surface("tv-special"))
        assertEquals(SortMemory.CATEGORY, SortMemory.surface("feature-film"))
        assertEquals(SortMemory.CATEGORY, SortMemory.surface(null))
        assertEquals("browseSort.tv", SortMemory.key(SortMemory.TV))
    }
}
