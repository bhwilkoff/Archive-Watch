package app.archivewatch.android.data

/**
 * A catalog id is an archive.org identifier, or — for one episode of a series
 * archive.org holds as files of a single item (Decision 166) — `<item>@<token>`
 * (`UFO.complete@e01`). archive.org identifiers never contain `@`, so the real
 * item is everything before the first one.
 */
fun archiveItemOf(id: String): String = id.substringBefore('@')

/** True when the id names one file of a multi-episode item, not a whole item. */
val String.isBundleFile: Boolean get() = contains('@')

/** The decoded file path of an `archive.org/download/<item>/<file>` url, or null. */
fun archiveFileOf(url: String?): String? {
    val path = url?.substringAfter("/download/", "")?.takeIf { it.isNotEmpty() } ?: return null
    val file = path.substringAfter('/', "").substringBefore('?')
    if (file.isEmpty()) return null
    return file.split('/').joinToString("/") {
        java.net.URLDecoder.decode(it.replace("+", "%2B"), "UTF-8")
    }
}

/** The archive.org page for an id: the item's, or for a bundle episode its own file's. */
fun archiveDetailsURL(id: String, downloadURL: String?): String {
    val base = "https://archive.org/details/" + archiveItemOf(id)
    if (!id.isBundleFile) return base
    val file = archiveFileOf(downloadURL) ?: return base
    return base + "/" + file.split('/').joinToString("/") {
        java.net.URLEncoder.encode(it, "UTF-8").replace("+", "%20")
    }
}
