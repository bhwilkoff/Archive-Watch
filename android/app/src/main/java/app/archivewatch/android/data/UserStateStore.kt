package app.archivewatch.android.data

import android.content.Context
import androidx.sqlite.SQLiteConnection
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

data class WatchProgress(
    val archiveID: String,
    val positionMs: Long,
    val durationMs: Long,
    val updatedAt: Long,
) {
    /** Resumable window: 10s < position < 95% of duration. */
    val isResumable: Boolean
        get() = positionMs > 10_000 && durationMs > 0 && positionMs < durationMs * 95 / 100
}

/**
 * Per-item user records (favorites, watch progress) in a tiny local
 * `user.sqlite` via the same BundledSQLiteDriver — the offline-first
 * local store (Drive App Data sync is the next wave, plan §6).
 */
class UserStateStore(context: Context) {
    private val connection: SQLiteConnection =
        BundledSQLiteDriver().open(context.filesDir.resolve("user.sqlite").path)
    private val mutex = Mutex()

    /** Bumped on every mutation so screens can re-query. */
    private val _changes = MutableStateFlow(0)
    val changes: StateFlow<Int> = _changes

    init {
        connection.execSQL(
            "CREATE TABLE IF NOT EXISTS favorites (id TEXT PRIMARY KEY, addedAt INTEGER)",
        )
        connection.execSQL(
            "CREATE TABLE IF NOT EXISTS progress (" +
                "id TEXT PRIMARY KEY, position INTEGER, duration INTEGER, at INTEGER)",
        )
    }

    // --- favorites ---

    suspend fun favoriteIDs(): List<String> = dbCall {
        query("SELECT id FROM favorites ORDER BY addedAt DESC") { it.getText(0) }
    }

    suspend fun isFavorite(id: String): Boolean = dbCall {
        query("SELECT 1 FROM favorites WHERE id = ?", listOf(id)) { true }.isNotEmpty()
    }

    suspend fun toggleFavorite(id: String): Boolean {
        val nowFavorite = dbCall {
            val exists = query("SELECT 1 FROM favorites WHERE id = ?", listOf(id)) { true }.isNotEmpty()
            if (exists) {
                exec("DELETE FROM favorites WHERE id = ?", listOf(id))
            } else {
                exec(
                    "INSERT OR REPLACE INTO favorites (id, addedAt) VALUES (?, ?)",
                    listOf(id, System.currentTimeMillis()),
                )
            }
            !exists
        }
        _changes.value += 1
        return nowFavorite
    }

    // --- watch progress ---

    suspend fun saveProgress(id: String, positionMs: Long, durationMs: Long) {
        if (durationMs <= 0) return
        dbCall {
            exec(
                "INSERT OR REPLACE INTO progress (id, position, duration, at) VALUES (?, ?, ?, ?)",
                listOf(id, positionMs, durationMs, System.currentTimeMillis()),
            )
        }
        _changes.value += 1
    }

    suspend fun progressFor(id: String): WatchProgress? = dbCall {
        query("SELECT id, position, duration, at FROM progress WHERE id = ?", listOf(id)) {
            WatchProgress(it.getText(0), it.getLong(1), it.getLong(2), it.getLong(3))
        }.firstOrNull()
    }

    /** Resumable items, most recent first — the Continue Watching source. */
    suspend fun continueWatching(limit: Int = 30): List<WatchProgress> = dbCall {
        query(
            "SELECT id, position, duration, at FROM progress ORDER BY at DESC LIMIT ?",
            listOf(limit.toLong() * 4),
        ) {
            WatchProgress(it.getText(0), it.getLong(1), it.getLong(2), it.getLong(3))
        }
    }.filter { it.isResumable }.take(limit)

    // --- plumbing ---

    private suspend fun <T> dbCall(block: () -> T): T =
        withContext(Dispatchers.IO) { mutex.withLock { block() } }

    private fun exec(sql: String, binds: List<Any?>) {
        val stmt = connection.prepare(sql)
        try {
            bindAll(stmt, binds)
            stmt.step()
        } finally {
            stmt.close()
        }
    }

    private fun <T> query(
        sql: String,
        binds: List<Any?> = emptyList(),
        map: (androidx.sqlite.SQLiteStatement) -> T,
    ): List<T> {
        val out = mutableListOf<T>()
        val stmt = connection.prepare(sql)
        try {
            bindAll(stmt, binds)
            while (stmt.step()) out.add(map(stmt))
        } finally {
            stmt.close()
        }
        return out
    }

    private fun bindAll(stmt: androidx.sqlite.SQLiteStatement, binds: List<Any?>) {
        binds.forEachIndexed { i, value ->
            val idx = i + 1
            when (value) {
                null -> stmt.bindNull(idx)
                is String -> stmt.bindText(idx, value)
                is Int -> stmt.bindLong(idx, value.toLong())
                is Long -> stmt.bindLong(idx, value)
                else -> stmt.bindText(idx, value.toString())
            }
        }
    }
}
