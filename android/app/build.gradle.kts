plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.naqaa.hayn"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.naqaa.hayn"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            // Phones only: arm64-v8a. 32-bit ARM would need nightly Rust for
            // DarkLib's AV1 decoder (rav1d) and 32-bit-only devices are
            // effectively extinct (Play has required 64-bit since 2019); x86_64
            // served only PC emulators and a few Chromebooks, so it was dropped
            // (user decision 2026-09-30). See native/darklib/docs/SUPPORT.md.
            // The Flutter Gradle plugin has already filled this set with every
            // ABI it supports; adding to it packaged all of them (BUILD-03).
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

dependencies {
    // Read EXIF orientation so the hardware AVIF encoder bakes upright pixels
    // (BitmapFactory ignores orientation). androidx works on all minSdk levels.
    implementation("androidx.exifinterface:exifinterface:1.3.7")
}
