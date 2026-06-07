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
            // We don't ship 32-bit ARM. DarkLib's pure-Rust AV1 decoder (rav1d)
            // needs nightly Rust only on armeabi-v7a (unstable NEON feature
            // detection); arm64/x86_64 build it on stable. 32-bit-only Android
            // devices are effectively extinct (Play has required 64-bit since
            // 2019), so arm64-v8a (all modern phones) + x86_64 (emulators) is the
            // whole matrix. See native/darklib/docs/SUPPORT.md.
            abiFilters.addAll(listOf("arm64-v8a", "x86_64"))
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
