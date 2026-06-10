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
        applicationId = "app.archivewatch.android"
        minSdk = 29
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables { useSupportLibrary = true }
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
