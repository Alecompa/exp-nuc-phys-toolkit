import java.util.Properties
import org.jetbrains.compose.desktop.application.dsl.TargetFormat
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    kotlin("multiplatform")
    id("com.android.application")
    id("org.jetbrains.compose")
    id("org.jetbrains.kotlin.plugin.compose")
}

// One copy of the bundled data (AME2020, NUBASE2020, SRIM, EXFOR index): the Swift package's resources.
val sharedData = rootDir.resolve("../Packages/NucToolkit/Sources/NucPhysKit/Resources")

kotlin {
    androidTarget {
        compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
    }
    jvm("desktop")

    sourceSets {
        val desktopMain by getting {
            resources.srcDir(sharedData)
        }
        commonMain.dependencies {
            implementation(compose.runtime)
            implementation(compose.foundation)
            implementation(compose.material3)
            implementation(compose.ui)
            implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0")
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
        }
        val desktopTest by getting {
            dependencies { implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3") }
        }
        androidMain.dependencies {
            implementation("androidx.activity:activity-compose:1.9.3")
            implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
        }
        desktopMain.dependencies {
            implementation(compose.desktop.currentOs)
            implementation("org.jetbrains.kotlinx:kotlinx-coroutines-swing:1.9.0")
        }
    }
}

// Release signing: from multiplatform/keystore.properties (git-ignored) or the environment (CI secrets).
// Keys: storeFile, storePassword, keyAlias, keyPassword / GAMOW_KEYSTORE, GAMOW_KEYSTORE_PASSWORD, GAMOW_KEY_ALIAS,
// GAMOW_KEY_PASSWORD. Without them, release builds stay unsigned and debug builds are unaffected.
val signingProps = Properties().apply {
    rootDir.resolve("keystore.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}
fun signing(key: String, env: String): String? = signingProps.getProperty(key) ?: System.getenv(env)
val releaseKeystore = signing("storeFile", "GAMOW_KEYSTORE")

android {
    namespace = "com.acompagnucci.gamow"
    compileSdk = 35
    defaultConfig {
        applicationId = "com.acompagnucci.gamow"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
    }
    sourceSets["main"].resources.srcDir(sharedData)
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    packaging { resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" } }
    signingConfigs {
        if (releaseKeystore != null) create("release") {
            storeFile = rootDir.resolve(releaseKeystore)
            storePassword = signing("storePassword", "GAMOW_KEYSTORE_PASSWORD")
            keyAlias = signing("keyAlias", "GAMOW_KEY_ALIAS")
            keyPassword = signing("keyPassword", "GAMOW_KEY_PASSWORD")
        }
    }
    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            if (releaseKeystore != null) signingConfig = signingConfigs.getByName("release")
        }
    }
}

compose.desktop {
    application {
        mainClass = "org.gamow.MainKt"
        nativeDistributions {
            // Linux packages must be built on Linux, Windows installers on Windows, the DMG on a Mac.
            targetFormats(TargetFormat.Deb, TargetFormat.Rpm, TargetFormat.Msi, TargetFormat.Dmg)
            packageName = "Gamow"
            packageVersion = "1.0.0"   // installers need MAJOR > 0; the app reports 0.1.0
            description = "Pocket toolkit for experimental nuclear astrophysics"
            linux { menuGroup = "Science" }
        }
    }
}

// The reference tests read ../Shared/*.json (written by the Swift tests): a changed file must re-run them.
tasks.withType<Test>().configureEach { inputs.dir(rootDir.resolve("../Shared")).withPropertyName("sharedReferenceValues") }
