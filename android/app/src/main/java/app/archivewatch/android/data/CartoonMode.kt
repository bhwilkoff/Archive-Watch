package app.archivewatch.android.data

/**
 * Cartoon Mode's pool and character shelves, phone and TV: the port of
 * Apple's KidsContent (keep them in step). Android took ANY animation, so the
 * marathon opened on "NASA eClips Video Series 360", a 24-minute NASA lesson
 * typed animation, with no artwork, silent-film or scary-subject gate at all.
 */
object CartoonMode {
    private val scary = listOf("horror", "war", "nightmare", "death", "ghost story", "macabre")
    private val shelfScary = listOf("horror", "nightmare", "macabre")

    val characterDefs: List<Pair<String, List<String>>> = listOf(
        "Popeye" to listOf("popeye"), "Betty Boop" to listOf("betty boop"),
        "Porky Pig" to listOf("porky"), "Mr. Magoo" to listOf("magoo"),
        "Looney Tunes" to listOf("looney tunes", "looney"), "Felix the Cat" to listOf("felix"),
        "Daffy Duck" to listOf("daffy"), "Bosko" to listOf("bosko"),
        "Mighty Mouse" to listOf("mighty mouse"), "Casper" to listOf("casper"),
        "Mickey Mouse" to listOf("mickey mouse"), "Superman" to listOf("superman"),
        "Little Lulu" to listOf("little lulu"), "Gulliver" to listOf("gulliver"),
        "Gerald McBoing-Boing" to listOf("mcboing"), "Bimbo" to listOf("bimbo"),
    )

    private fun CatalogItem.blob() = (genres + subjects).map { it.lowercase() }

    private fun CatalogItem.isBlackAndWhiteOrSilent(): Boolean {
        if (colorMode == "color") return false
        if (colorMode == "bw") return true
        if (isSilentFilm == true) return true
        return (year ?: Int.MAX_VALUE) < 1930
    }

    /** One read serves both (two full reads of 2,100 rows kept the TV page on
     *  "Rounding up the cartoons…" for over 20 s): animation that can play, has
     *  designed art and is not silent. */
    private suspend fun candidates(db: CatalogDatabase): List<CatalogItem> =
        db.withPoolFields(
            db.browse(contentType = "animation", limit = 800, recommendOnly = true)
                .filter { it.hasDesignedArtwork && it.isSilentFilm != true },
        ).filter { it.downloadURL != null }

    /** The marathon: color-leaning, never silent, nothing scary, designed art. */
    fun pool(candidates: List<CatalogItem>, limit: Int = 250): List<CatalogItem> {
        val pool = candidates.filter { item -> item.blob().none { g -> scary.any { g.contains(it) } } }
        val color = pool.filter { !it.isBlackAndWhiteOrSilent() }.shuffled()
        val bw = pool.filter { it.isBlackAndWhiteOrSilent() }.shuffled()
        // Shuffled before the cut: color comes first, so with more color cartoons
        // than the limit the B&W share never reached a lineup.
        return (color + bw.take(maxOf(3, (color.size * 0.15).toInt()))).shuffled().take(maxOf(limit, 120))
    }

    /** Character shelves, matched on title OR archive.org subjects (Apple's rule). */
    fun characters(candidates: List<CatalogItem>): List<Pair<String, List<CatalogItem>>> {
        val pool = candidates.filter { item -> item.blob().none { g -> shelfScary.any { g.contains(it) } } }
        return characterDefs.mapNotNull { (name, terms) ->
            val rows = pool.filter { item ->
                val hay = item.title.lowercase() + " " + item.subjects.joinToString(" ") { it.lowercase() }
                terms.any { hay.contains(it) }
            }.take(20)
            if (rows.size >= 3) name to rows else null
        }
    }

    /** (marathon pool, character shelves). The marathon draws on every
     *  qualifying cartoon (tools/lineup_pools.py); an older DB has no lineup and
     *  draws on the 800 most popular, as the character shelves still do. */
    suspend fun load(db: CatalogDatabase): Pair<List<CatalogItem>, List<Pair<String, List<CatalogItem>>>> {
        val c = candidates(db)
        val lineup = db.lineup("lineup-cartoon")
        val marathon = if (lineup.isEmpty()) c else db.withPoolFields(
            lineup.filter { it.hasDesignedArtwork && it.isSilentFilm != true },
        ).filter { it.downloadURL != null }
        return pool(marathon) to characters(c)
    }
}
