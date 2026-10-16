## 0.2.0

**Behaviour change:** `readOnce()` no longer re-delivers an old referrer to
an install that existed before the plugin did (#30).

- `readOnce({treatUpgradesAsHandled = true})`: on Android, an install that
  was updated since it was installed, and whose first start with the plugin
  came after that update, is marked handled and gets `null`. Before, the
  first launch after an app adopted the plugin in an update re-delivered
  Play's referrer, up to 90 days old, to every existing user. The plugin now
  records its first start in `noBackupFilesDir`. Pass `false` for the 0.1
  behaviour.
  - An install that started on 0.1.x counts as adopted in an update on its
    first 0.2.0 launch (0.1.x kept no first-seen record) and is marked
    handled. It already had its first launch under 0.1.x. Pass
    `treatUpgradesAsHandled: false` if an app on 0.1.x still needs that
    install's referrer.
- `readOnce({maxClickAge})`: a Play click older than the limit is marked
  handled. Uses `clickedAtServer` when reported, else `clickedAt`; an
  unknown click time is never stale. Default: no limit.
- `readOnce({pastInstallFlow})`: the app's own "past the install flow" check;
  `true` marks the install handled without a Play read. README recipe:
  require signed in **and** a first run completed on this device, with the
  first-run flag kept out of backups.
- `InstallAttribution.lastSkipReason` (`ReadOnceSkip`) says why `readOnce()`
  returned `null`.
- `InstallAttribution.adoptExistingState(alreadyHandled:)`: one-time
  migration from referrer handling an app shipped before the plugin.
- `InstallAttribution.installFacts()` and `InstallFacts`. Platform
  implementations get a default `installFacts()` that returns `null`.
- Android: `markHandled()` keeps an existing marker instead of rewriting it.
- iOS: `treatUpgradesAsHandled` and `maxClickAge` are no-ops.

## 0.1.2

- Fix: `InstallReferrer.deepLink()` and `InstallReferrer.resolveDeepLink()`
  never throw. A value with a percent escape that is not UTF-8 (`%FF`,
  `%C3`, a truncated `%E2%82`) threw `FormatException` instead of returning
  `null`; it is now refused, like a malformed escape (`%`, `%ZZ`), which
  `Uri.parse` used to rewrite silently into `%25`. The check covers the
  query and fragment too, so a returned link's own `queryParameters` can no
  longer throw. Unescaped non-ASCII text (`/items/café`) is still accepted;
  a lone UTF-16 surrogate is refused. A fuzz test over every `%XX` escape
  and random input pins it, and a differential test against the 0.1.1
  algorithm checks nothing else changed.

## 0.1.1

Documentation only; no API or behaviour change.

- README: the package is on pub.dev. Install with
  `flutter pub add imaji_install_attribution` (or
  `imaji_install_attribution: ^0.1.0`); the Git dependency is now only the
  way to track unreleased `main`. Adds pub version, pub points, likes, CI
  and license badges.
- README comparison table: `stack_deferred_link` crashes on a null details
  bundle; it does not report a `PlatformException` as the table said.
- RELEASING.md is a reusable per-release checklist.

## 0.1.0

First release.

- `InstallAttribution.read({timeout})` returns a sealed
  `InstallAttributionResult` — `Attributed`, `Organic` or
  `Unavailable(reason)` — and never throws.
- Android: Google Play Install Referrer 2.2. The Binder call runs off the
  platform thread with a timeout; a null details bundle, `DeadObjectException`,
  `PERMISSION_ERROR`, `FEATURE_NOT_SUPPORTED`, `SERVICE_UNAVAILABLE`,
  `DEVELOPER_ERROR`, `SERVICE_DISCONNECTED` (after one reconnect) and a missing
  Play Store each map to a typed `UnavailableReason`.
- Android: `InstallSource` — installer package via `getInstallSourceInfo`
  (API 30+) or `getInstallerPackageName`, mapped to Play, Galaxy Store,
  AppGallery, Amazon, side-load or restore.
- iOS: Apple AdServices attribution token as
  `Attributed(source: appleAds, token: ...)`; the simulator reports
  `Unavailable(notSupported)`. Swift Package Manager and CocoaPods, with a
  privacy manifest.
- `InstallReferrer.deepLink(allow: [...])`: decodes exactly once and only
  returns allowlisted in-app paths.
- `PlayStoreUrl`: store links whose referrer is encoded exactly once.
- Opt-in consume-once store: `readOnce()`, `markHandled()`, `isHandled()`,
  `clearHandled()`.
- `debugOverride()` for debug builds, and a testing guide (TESTING.md).
- Built on AGP Built-in Kotlin: no Kotlin Gradle Plugin in any build file.
  Minimum supported SDK: Flutter 3.44 / Dart 3.12.
