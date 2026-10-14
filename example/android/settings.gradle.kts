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
    id("com.android.application") version "9.1.0" apply false
    // Not applied to any module. With built-in Kotlin, AGP compiles Kotlin
    // with the KGP version found on the classpath; this pins it above
    // Flutter's minimum (AGP 9.1 alone brings 2.2.10).
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
