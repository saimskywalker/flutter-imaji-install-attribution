// Android side of imaji_install_attribution.
//
// Built on AGP Built-in Kotlin: this file applies the Android library plugin
// and nothing else. There is deliberately no Kotlin Gradle Plugin line here —
// not in `plugins {}`, not as `apply plugin:`, not on the buildscript
// classpath. Flutter's "plugins that apply Kotlin Gradle Plugin" warning is a
// text match on this file, so even a guarded KGP line would trip it.
//
// Hosts on AGP 9 with `android.builtInKotlin=true` compile the Kotlin sources
// with AGP's own Kotlin support. Hosts with `android.builtInKotlin=false` (or
// AGP 8) still build: Flutter's Gradle plugin applies the Kotlin plugin to
// plugin projects that do not declare it, as long as the host has KGP 2.0+ on
// its classpath (every Flutter 3.44+ app template does).

group = "io.github.saimskywalker.imaji_install_attribution"
version = "0.1.1"

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Only used when this directory is opened on its own in an IDE.
        classpath("com.android.tools.build:gradle:9.1.0")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "io.github.saimskywalker.imaji_install_attribution"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // src/main/kotlin and src/test/kotlin are default source roots.

    defaultConfig {
        minSdk = 21
    }

    testOptions {
        unitTests {
            // android.jar stubs (DeadObjectException, RemoteException, ...)
            // are constructed by the tests; return defaults instead of
            // throwing "Method ... not mocked".
            isReturnDefaultValues = true
            all {
                it.testLogging {
                    events("passed", "skipped", "failed")
                    showStandardStreams = true
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("com.android.installreferrer:installreferrer:2.2")
    testImplementation("junit:junit:4.13.2")
}
