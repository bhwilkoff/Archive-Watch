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
        versionCode = 11
        // Marketing version tracks the Apple apps (AppVersion.xcconfig) so a
        // user report names one version family across platforms.
        versionName = "1.3.280"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables { useSupportLibrary = true }
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

    implementation(libs.splashscreen)

    testImplementation(libs.junit)
    testImplementation(libs.coroutines.test)
    androidTestImplementation(libs.junit.ext)
    androidTestImplementation(libs.espresso.core)
}
