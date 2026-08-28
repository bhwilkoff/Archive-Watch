// :app — composition root. Single module; manual DI via AppContainer.

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

// Shared data plane (docs/CATALOG-CONTRACT.md): the bundled first-paint
// seed.sqlite and the featured.json fallback are the SAME files the Apple
// apps bundle — copied from the repo at build time, never duplicated in git.
abstract class SyncSharedAssets : DefaultTask() {
    @get:InputFiles
    abstract val sources: ConfigurableFileCollection

    @get:OutputDirectory
    abstract val outDir: DirectoryProperty

    @TaskAction
    fun run() {
        val dir = outDir.get().asFile
        dir.mkdirs()
        sources.files.forEach { it.copyTo(File(dir, it.name), overwrite = true) }
    }
}

val syncSharedAssets = tasks.register<SyncSharedAssets>("syncSharedAssets") {
    val repoRoot = rootDir.parentFile
    sources.from(
        File(repoRoot, "ArchiveWatch/ArchiveWatch/seed.sqlite"),
        File(repoRoot, "featured.json"),
        File(repoRoot, "ArchiveWatch/ArchiveWatch/collection_metadata.json"),
    )
}

androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(
            syncSharedAssets,
            SyncSharedAssets::outDir,
        )
    }
}

android {
    namespace = "app.archivewatch.android"
    // The 2026.05 Compose BOM requires API 37 to compile against;
    // targetSdk stays 36 (runtime behavior opt-in is separate).
    compileSdk = 37

    defaultConfig {
        // Play Console app record was created as com.archivewatch.app — the
        // applicationId must match it. The Kotlin namespace above stays
        // app.archivewatch.android (source packages don't move).
        applicationId = "com.archivewatch.app"
        minSdk = 29
        targetSdk = 36
        // Play rejects ANY previously-uploaded versionCode — bump +1 before
        // every Play upload, even if that upload was never released.
        versionCode = 42
        // Marketing version tracks the Apple apps (AppVersion.xcconfig) so a
        // user report names one version family across platforms.
        versionName = "1.3.478"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables { useSupportLibrary = true }
    }

    // Store flavors (Decision 047 §6.6). The ONLY difference is Google Play
    // Services: Cast is GMS-dependent, and Fire OS has no GMS, so linking Cast
    // into the Fire build would crash it at runtime — not at build time, which
    // is exactly why this is a hard structural split rather than a code guard.
    // tools/audit_fire_tv_gms.py gates the amazon variant in CI.
    // Drive-sync activation (Decision 028): set awGoogleServerClientId in
    // ~/.gradle/gradle.properties (or CI env) once the owner creates the
    // OAuth client — docs/google-oauth-setup.md. Empty = feature hidden.
    defaultConfig {
        buildConfigField(
            "String", "AW_GOOGLE_SERVER_CLIENT_ID",
            "\"${providers.gradleProperty("awGoogleServerClientId").orNull ?: ""}\"",
        )
        // OpenSubtitles shared API key (the download QUOTA follows the
        // viewer's own account; this key only carries request rate). Local:
        // ~/.gradle/gradle.properties; CI: the OPENSUBTITLES_API_KEY secret.
        buildConfigField(
            "String", "OPENSUBTITLES_API_KEY",
            "\"${providers.gradleProperty("awOpenSubtitlesApiKey").orNull
                ?: System.getenv("OPENSUBTITLES_API_KEY") ?: ""}\"",
        )
    }

    flavorDimensions += "store"
    productFlavors {
        create("google") {
            dimension = "store"
            // Same applicationId — Play is the store for this flavor.
        }
        create("amazon") {
            dimension = "store"
            // Amazon Appstore. Deliberately ZERO GMS: no Cast, no Play
            // Services of any kind. If you are about to add a dependency
            // here, check it first with tools/audit_fire_tv_gms.py.
        }
    }

    signingConfigs {
        // Upload key lives OUTSIDE git (~/keystores); creds come from the
        // user-level ~/.gradle/gradle.properties. Release stays buildable
        // (unsigned) on machines without them. Play App Signing will hold
        // the production key once the Play listing exists.
        create("release") {
            val keystorePath = providers.gradleProperty("UPLOAD_KEYSTORE_PATH").orNull
            if (keystorePath != null) {
                storeFile = file(keystorePath)
                storePassword = providers.gradleProperty("UPLOAD_KEYSTORE_PASSWORD").orNull
                keyAlias = providers.gradleProperty("UPLOAD_KEY_ALIAS").orNull
                keyPassword = providers.gradleProperty("UPLOAD_KEY_PASSWORD").orNull
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            isDebuggable = true
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            signingConfig = signingConfigs.getByName("release")
            // Embed native-lib symbol tables (BUNDLE-METADATA/…debugsymbols)
            // so Play can symbolicate crashes/ANRs in libsqliteJni & friends —
            // clears the Console's "no debug symbols" warning. Needs an NDK
            // (auto-provisioned via cmdline-tools).
            ndk { debugSymbolLevel = "SYMBOL_TABLE" }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    androidResources {
        // Keep the 18 MB seed DB stored (mmap-able, faster first copy).
        noCompress += "sqlite"
    }

    packaging {
        resources {
            excludes += setOf(
                "/META-INF/{AL2.0,LGPL2.1}",
                "/META-INF/LICENSE*",
            )
        }
    }
}

dependencies {
    implementation(platform(libs.compose.bom))
    androidTestImplementation(platform(libs.compose.bom))
    implementation(libs.bundles.compose.core)
    debugImplementation(libs.compose.ui.tooling)

    implementation(libs.bundles.adaptive)

    // Compose for TV — the 10-foot D-pad surfaces (docs/TV-DESIGN.md §6.1).
    // tv-material ONLY; tv-foundation no longer exists.
    implementation(libs.tv.material)
    // QR generation for the TV Share overlay (the tvOS ShareSheet QR,
    // PARITY §4). zxing:core is Apache-2, dependency-free, and tiny.
    implementation("com.google.zxing:core:3.5.3")
    // Keychain analogue for the OpenSubtitles credentials.
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    // Home-screen widgets (the iOS WidgetKit suite's analogue, PARITY §8).
    implementation("androidx.glance:glance-appwidget:1.1.1")
    // Google TV Watch Next (home-screen Continue Watching, PARITY §8)
    implementation("androidx.tvprovider:tvprovider:1.0.0")

    implementation(libs.activity.compose)
    implementation(libs.lifecycle.runtime.compose)
    implementation(libs.lifecycle.process)

    implementation(libs.coroutines.core)
    implementation(libs.coroutines.android)
    implementation(libs.kotlinx.serialization.json)

    implementation(libs.datastore.preferences)
    implementation(libs.sqlite)
    implementation(libs.sqlite.bundled)

    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)

    implementation(libs.okhttp)

    implementation(libs.bundles.media3)

    // Cast — GOOGLE FLAVOR ONLY. `googleImplementation` is what keeps GMS out
    // of the amazon variant; a plain `implementation` here would silently
    // break Fire TV (docs/TV-DESIGN.md §6.6).
    "googleImplementation"(libs.play.services.cast.framework)
    // Drive App Data sync (google flavor only — Decision 028/047): the
    // authorization API for the appdata scope. Fire stays GMS-free.
    "googleImplementation"("com.google.android.gms:play-services-auth:21.2.0")
    "googleImplementation"(libs.media3.cast)

    implementation(libs.splashscreen)

    testImplementation(libs.junit)
    testImplementation(libs.coroutines.test)
    androidTestImplementation(libs.junit.ext)
    androidTestImplementation(libs.espresso.core)
}
