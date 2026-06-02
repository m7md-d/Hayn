pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // Versions are variables in gradle.properties (single source of truth), not
    // inline literals.
    id("com.android.application")
        .version(providers.gradleProperty("agpVersion").get()).apply(false)
    id("org.jetbrains.kotlin.android")
        .version(providers.gradleProperty("kotlinVersion").get()).apply(false)
}

include(":app")
