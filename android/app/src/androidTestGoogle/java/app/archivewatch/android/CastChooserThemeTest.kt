package app.archivewatch.android

import android.view.ContextThemeWrapper
import androidx.mediarouter.app.MediaRouteChooserDialog
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Play cluster d8f3f3a4: tapping Cast on Android 11-12 threw "background can
 * not be translucent: #0" building mediarouter's in-app chooser, which reads
 * AppCompat's colorPrimary from the ACTIVITY's theme. Newer Android hands Cast
 * to the system output switcher, so the crash never shows on the bench phone;
 * building the chooser directly runs the same theme read on any version.
 */
@RunWith(AndroidJUnit4::class)
class CastChooserThemeTest {

    /** Dialog.create() runs onCreate. Called through android.app.Dialog because
     *  AppCompat (the chooser's superclass) reaches this module only at runtime,
     *  through mediarouter; the cause of a failure is unwrapped. */
    private fun createAndDismiss(dialog: Any) {
        try {
            android.app.Dialog::class.java.getMethod("create").invoke(dialog)
            android.app.Dialog::class.java.getMethod("dismiss").invoke(dialog)
        } catch (e: java.lang.reflect.InvocationTargetException) {
            throw e.targetException
        }
    }

    @Test
    fun theChooserBuildsUnderTheActivityTheme() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            var error: Throwable? = null
            scenario.onActivity { activity ->
                error = runCatching { MediaRouteChooserDialog(activity) }.exceptionOrNull()
            }
            assertTrue("chooser threw: $error", error == null)
        }
    }

    /** The v69 cluster: past the constructor, onCreate's setContentView is
     *  AppCompatDialog's, and it refuses a non-AppCompat theme ("You need to
     *  use a Theme.AppCompat theme", Android 12). create() runs onCreate. */
    @Test
    fun theChooserCreatesItsContentUnderTheActivityTheme() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            var error: Throwable? = null
            scenario.onActivity { activity ->
                error = runCatching {
                    createAndDismiss(MediaRouteChooserDialog(activity))
                }.exceptionOrNull()
            }
            assertTrue("chooser onCreate threw: $error", error == null)
        }
    }

    @Test
    fun controlTheMaterialBaseThemeFailsOnCreate() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            var error: Throwable? = null
            scenario.onActivity { activity ->
                val old = activity.resources.newTheme().apply {
                    applyStyle(R.style.Theme_ArchiveWatch_Base, true)
                }
                error = runCatching {
                    createAndDismiss(MediaRouteChooserDialog(ContextThemeWrapper(activity, old)))
                }.exceptionOrNull()
            }
            assertTrue("expected the old theme to fail building the chooser", error != null)
        }
    }

    @Test
    fun controlTheBaseThemeWithoutColorPrimaryStillThrows() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            var error: Throwable? = null
            scenario.onActivity { activity ->
                // A FRESH theme holding only the old activity style: a
                // ContextThemeWrapper given a style id layers it over the
                // activity's theme and would inherit the fix.
                val old = activity.resources.newTheme().apply {
                    applyStyle(R.style.Theme_ArchiveWatch_Base, true)
                }
                val bare = ContextThemeWrapper(activity, old)
                error = runCatching { MediaRouteChooserDialog(bare) }.exceptionOrNull()
            }
            assertTrue("expected the translucent-primary failure, got $error",
                error is IllegalArgumentException && "translucent" in (error?.message ?: ""))
        }
    }
}
