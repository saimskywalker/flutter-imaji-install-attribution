## 0.2.1

- README: the comparison table is replaced by an Alternatives section that
  describes each plugin without per-feature verdicts, and the "Why this
  exists" table now describes the platform's traps rather than other
  plugins. `play_install_referrer` 0.6.0 moved to Built-in Kotlin, reads the
  referrer off the main thread with a timeout and guards a null details
  bundle, which the old table did not reflect.
- README: a Trademarks section for the Google and Apple names.
- README: the per-plugin migration notes are replaced by a mapping from
  Play's own fields and response codes, and the package description no
  longer leads with a difference that every referrer plugin now shares.

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
- `InstallAttribution.claimOnce()` returns an `InstallClaim`
  (`complete()` / `release()`) (#31):
  - One claim per process: a concurrent `claimOnce()` returns `null`
    (`claimedElsewhere`).
  - A persisted failed-read budget, `maxFailedReads` (default 3). After it
    the install is marked handled and Play is not asked again.
  - `terminal` reasons (default `{playStoreMissing}`) mark the install
    handled at once.
  - The count lives next to the handled marker, outside backups, and
    `clearHandled()` clears it.
  - `failedReads()`, `lastFailure`, and the `ReadOnceSkip` values
    `claimedElsewhere`, `readFailed`, `terminalFailure` and `budgetSpent`.
  - Platform interface: `failedReads()` / `recordFailedRead()`. A platform
    without them gets the lock but no budget.
- Android: the Play Store presence check (`PackageManager.getPackageInfo`, a
  Binder call) moved from the platform thread to the worker thread (#31).
  No Binder call in `read` runs on the main thread now.
- README quick start uses `claimOnce()`.
- `InstallReferrer.deepLinkResult()` / `resolveDeepLinkResult()` return a
  sealed `DeepLinkResult`: `DeepLinkFound(uri)`, or
  `DeepLinkRejected(reason)` with a `DeepLinkRejection` (#29). The reasons
  are `absent`, `unsafe`, `undecodable`, `notAPath`, `hostNotAllowed`,
  `looksDoubleEncoded` and `notAllowlisted`. A double-encoded value is
  reported, never repaired. `deepLink()` is `deepLinkResult().uriOrNull`.
- `InstallReferrer(raw, decoding: ReferrerDecoding.rfc3986)`: opt-in RFC
  3986 value decoding, where `+` stays `+`. `ReferrerDecoding.form`
  (`application/x-www-form-urlencoded`) stays the default. `withDecoding()`
  re-reads the same raw string. Equality now includes the decoding.
- Fix: a `.` or `..` segment is refused as written. `Uri.parse` normalised
  `/items/../admin` to `/admin`, and `/items/../items/42` to `/items/42`
  (accepted), before the check could see the segment.
- `test/vectors/deep_link_vectors.json`: language-neutral vectors for the
  decoding rule and the link builder. The README documents the rule and
  shows how a backend in any language can test against the file.

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
