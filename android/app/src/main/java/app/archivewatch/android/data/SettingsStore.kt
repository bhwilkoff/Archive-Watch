package app.archivewatch.android.data

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.settingsDataStore by preferencesDataStore("settings")

/**
 * Scalar settings in DataStore preferences. Per-item records (favorites,
 * progress) live in user.sqlite — DataStore is wrong for those.
 */
class SettingsStore(private val context: Context) {
    private val hideAdultKey = booleanPreferencesKey("hideAdultContent")
    private val autoplayKey = booleanPreferencesKey("autoplayNext")
    private val hideWatchedKey = booleanPreferencesKey("hideWatchedOnHome")

    /** Decision 012 — mature content hidden by DEFAULT. */
    val hideAdultContent: Flow<Boolean> =
        context.settingsDataStore.data.map { it[hideAdultKey] ?: true }

    val autoplayNext: Flow<Boolean> =
        context.settingsDataStore.data.map { it[autoplayKey] ?: false }

    suspend fun setHideAdultContent(value: Boolean) {
        context.settingsDataStore.edit { it[hideAdultKey] = value }
    }

    suspend fun setAutoplayNext(value: Boolean) {
        context.settingsDataStore.edit { it[autoplayKey] = value }
    }

    /** tvOS parity: per-category visibility (Decision 012's sibling switch).
     *  Stored as the HIDDEN set so the default (empty) shows everything. */
    private val hiddenCategoriesKey = stringSetPreferencesKey("hiddenCategories")

    val hiddenCategories: Flow<Set<String>> =
        context.settingsDataStore.data.map { it[hiddenCategoriesKey] ?: emptySet() }

    suspend fun setCategoryHidden(contentType: String, hidden: Boolean) {
        context.settingsDataStore.edit {
            val cur = it[hiddenCategoriesKey] ?: emptySet()
            it[hiddenCategoriesKey] = if (hidden) cur + contentType else cur - contentType
        }
    }

    /** #17 parity: hide completed titles from Home shelves. */
    val hideWatchedOnHome: Flow<Boolean> =
        context.settingsDataStore.data.map { it[hideWatchedKey] ?: false }

    suspend fun setHideWatchedOnHome(value: Boolean) {
        context.settingsDataStore.edit { it[hideWatchedKey] = value }
    }
}
