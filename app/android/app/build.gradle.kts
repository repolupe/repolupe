import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing with the upload key, see https://docs.flutter.dev/deployment/android#sign-the-app.
// Without key.properties (e.g. on F-Droid, which signs the APKs itself), release builds are unsigned.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.repolupe.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.repolupe.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. Split APKs get their own per ABI, see abiCodes below.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Google Play gets no armv7 build, to keep the bundle small. The split APKs (F-Droid) keep it,
        // and abiFilters can't be combined with their ABI splits anyway.
        if (gradle.startParameter.taskNames.any { it.contains("bundle", ignoreCase = true) }) {
            ndk {
                abiFilters.clear()
                abiFilters += listOf("arm64-v8a", "x86_64")
            }
        }
    }

    if (keystorePropertiesFile.exists()) {
        signingConfigs {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }

    // Required by F-Droid: no dependency metadata, which is encrypted with a Google key.
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }
}

// Version codes of the split APKs (`--split-per-abi`), in the scheme F-Droid assigns them
// (`versionCode * 10 + abi`), instead of Flutter's `1000 * abi + versionCode`.
// The bundle keeps the plain version code. This uses the legacy variant API like Flutter's own override,
// which this one has to run after.
val abiCodes = mapOf("x86_64" to 1, "armeabi-v7a" to 2, "arm64-v8a" to 3)
android.applicationVariants.configureEach {
    val variant = this
    outputs.forEach { output ->
        @Suppress("DEPRECATION")
        output as com.android.build.gradle.api.ApkVariantOutput
        @Suppress("DEPRECATION")
        val abiCode = abiCodes[output.getFilter(com.android.build.VariantOutput.FilterType.ABI)]
        if (abiCode != null) {
            output.versionCodeOverride = variant.versionCode * 10 + abiCode
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
