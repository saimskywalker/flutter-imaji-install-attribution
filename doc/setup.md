# Setup

## Requirements

Flutter 3.44+ / Dart 3.12+. Android minSdk 21. iOS 15 (Flutter's own
minimum). Swift Package Manager and CocoaPods are both supported.

There is nothing to configure: no manifest edits, no `Info.plist` keys, no
App Tracking Transparency prompt.

## Install

```bash
flutter pub add imaji_install_attribution
```

or add it to `pubspec.yaml` yourself:

```yaml
dependencies:
  imaji_install_attribution: ^0.2.1
```

## Tracking `main`

To try unreleased changes before they reach pub.dev, depend on the
repository's `main` branch instead. It is not a release: pin a commit with
`ref:` if you need a reproducible build.

```yaml
dependencies:
  imaji_install_attribution:
    git:
      url: https://github.com/saimskywalker/flutter-imaji-install-attribution.git
      ref: main
```

## Android build setup

Nothing to configure. The plugin's `android/build.gradle.kts` applies only
`com.android.library` and configures Kotlin through the top-level
`kotlin { compilerOptions { jvmTarget } }` block, exactly as Flutter's
[built-in Kotlin guide for plugin authors](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors)
prescribes. There is no Kotlin Gradle Plugin line in any build file, so
Flutter's *"Your app uses the following plugins that apply Kotlin Gradle
Plugin (KGP)"* warning never names this plugin. Flutter's check is a text
match on the plugin's build file, and there is nothing to match.

| Host app | Works? |
|---|---|
| AGP 9.x, `android.builtInKotlin=true` (Flutter 3.47+) | Yes. Verified with the example app; no KGP warning. |
| AGP 9.x, `android.builtInKotlin=false` (Flutter 3.44+) | Yes, verified. Flutter's Gradle plugin applies `kotlin-android` to plugins that do not declare it. |
| AGP 8.x | Yes, as long as the app has KGP 2.0+ on its classpath (every Flutter 3.44+ template does). |

With built-in Kotlin, AGP compiles Kotlin with the KGP version on the build
classpath. Flutter 3.47 requires 2.2.20+, while AGP 9.1 alone brings 2.2.10,
so keep the template's `id("org.jetbrains.kotlin.android") version "2.4.0"
apply false` in the app's `settings.gradle.kts`. It is a version pin, applied
to no module, and Flutter does not warn about it.
