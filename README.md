# imaji_install_attribution — Play Install Referrer & Apple AdServices for Flutter

[![pub version](https://img.shields.io/pub/v/imaji_install_attribution)](https://pub.dev/packages/imaji_install_attribution)
[![pub points](https://img.shields.io/pub/points/imaji_install_attribution)](https://pub.dev/packages/imaji_install_attribution/score)
[![pub likes](https://img.shields.io/pub/likes/imaji_install_attribution)](https://pub.dev/packages/imaji_install_attribution/score)
[![CI](https://github.com/saimskywalker/flutter-imaji-install-attribution/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/saimskywalker/flutter-imaji-install-attribution/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/github/license/saimskywalker/flutter-imaji-install-attribution)](https://github.com/saimskywalker/flutter-imaji-install-attribution/blob/main/LICENSE)

A Flutter plugin that answers one question on Android and iOS: **where did
this install come from?** — and turns the answer into the deep link the user
was trying to open before they installed (a *deferred deep link*).

- **Android:** reads the Google Play Install Referrer.
- **iOS:** reads the Apple AdServices attribution token (Apple Ads).
- **Dart:** one typed result — `Attributed`, `Organic` or
  `Unavailable(reason)` — from a `read()` that never throws.
- **Built on AGP Built-in Kotlin.** No Kotlin Gradle Plugin line in any build
  file, so Flutter's *"Your app uses the following plugins that apply Kotlin
  Gradle Plugin (KGP)"* warning never names this plugin.

> Published on [pub.dev](https://pub.dev/packages/imaji_install_attribution):
> `flutter pub add imaji_install_attribution` (see [Install](#install)).

## Why this exists

Firebase Dynamic Links has been shut down, and with it the easy way to carry
a link through an app-store install. What is left is the platform itself:
the Play Install Referrer on Android and the AdServices token on iOS. The
existing Flutter referrer plugins share a few problems:

| Problem | What this plugin does |
|---|---|
| They apply the Kotlin Gradle Plugin, which Flutter warns will fail to build in future releases (AGP 9 Built-in Kotlin) | Built-in Kotlin from day one. Flutter's check is a text match on the plugin's build file, and there is nothing to match |
| The Binder call `getInstallReferrer()` runs on the platform thread, so a slow Play Store freezes the UI (ANR) | Every Binder call in the read (the Play Store presence check and `getInstallReferrer()`) runs on a background thread, with a timeout (default 10 s) |
| Play can answer `OK` with details whose bundle is null; reading them is a fatal `NullPointerException` | Every read is guarded: `Unavailable(nullDetails)` |
| `DeadObjectException`, `PERMISSION_ERROR`, `FEATURE_NOT_SUPPORTED`, … arrive as `PlatformException` strings, or crash the app | Each one is a distinct `UnavailableReason` |
| A second `SERVICE_DISCONNECTED` can leave the call unanswered forever | One reconnect, then `Unavailable(serviceDisconnected)`; a timeout bounds everything |
| Nothing stops a referrer from being acted on twice, and a failing read retries on every launch forever | `claimOnce()`: one claim per process, a persisted retry budget, first-launch-only semantics |
| Deep-link extraction is left to you, and decoding twice corrupts `%2F` paths | `referrer.deepLink(allow: [...])` decodes exactly once and enforces an allowlist |
| "Unknown installer" errors for Samsung restores and other stores | `InstallSource` maps the installer package: Play, Galaxy Store, AppGallery, Amazon, side-load, restore |
| No way to test without publishing | `debugOverride()` and a real [testing guide](TESTING.md) |

## 30-second quick start

```dart
import 'package:imaji_install_attribution/imaji_install_attribution.dart';

Future<void> routeFromInstall(GoRouter router) async {
  // null once handled, while another startup path holds the claim, or after
  // a failed read (retried on the next launch, up to a budget).
  final claim = await InstallAttribution.claimOnce();
  if (claim == null) return;
  switch (claim.result) {
    case Attributed(:final referrer?):
      final link = referrer.deepLink(allow: ['/items/', '/profile/']);
      if (link != null) router.go(link.toString());
    case Attributed(:final token?):
      await sendToServer(token); // iOS: resolve with Apple's attribution API
    case _:
      break; // installed with no campaign
  }
  await claim.complete(); // never again on this install
}
```

Failures are typed, never thrown: `InstallAttribution.lastSkipReason` and
`lastFailure` say why `claimOnce()` returned `null`.

That is the whole integration: no manifest edits, no `Info.plist` keys, no
App Tracking Transparency prompt.

## Install

```bash
flutter pub add imaji_install_attribution
```

or add it to `pubspec.yaml` yourself:

```yaml
dependencies:
  imaji_install_attribution: ^0.2.0
```

Requirements: Flutter 3.44+ / Dart 3.12+. Android minSdk 21. iOS 15
(Flutter's own minimum). Swift Package Manager and CocoaPods are both
supported.

### Tracking `main`

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

### Android build setup

Nothing to configure. The plugin's `android/build.gradle.kts` applies only
`com.android.library` and configures Kotlin through the top-level
`kotlin { compilerOptions { jvmTarget } }` block, exactly as Flutter's
[built-in Kotlin guide for plugin authors](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors)
prescribes.

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

## API

### `InstallAttribution.read({Duration timeout})`

Returns `Future<InstallAttributionResult>` and **never throws**.

| Result | When |
|---|---|
| `Attributed(source: googlePlay, referrer, clickedAt, installBeganAt, …)` | Play returned a referrer with a campaign, a `gclid`, or any custom key |
| `Attributed(source: appleAds, token)` | An iOS device returned an AdServices token |
| `Organic(referrer)` | Play's default `utm_source=google-play&utm_medium=organic`, an empty referrer, or only `(not set)` values |
| `Unavailable(reason, message)` | Nothing could be read; `reason` says why |

Every result also carries `installSource` (Android; `null` on iOS).

`UnavailableReason`: `notSupported` (web, desktop, iOS simulator), `timeout`,
`playStoreMissing`, `featureNotSupported`, `serviceUnavailable`,
`serviceDisconnected`, `deadService`, `permissionError`, `developerError`,
`nullDetails`, `unknownResponse`, `networkError` (iOS), `internalError`.

Concurrent calls share one platform read. The default timeout is 10 seconds.

### `InstallReferrer`

- `raw`: the string exactly as Play returned it.
- `parameters`, `referrer['key']`: values decoded **exactly once**.
- `utmSource`, `utmMedium`, `utmCampaign`, `utmContent`, `utmTerm`: `null`
  when absent or `(not set)`.
- `isOrganic`: the rule `read()` uses.
- `deepLink({key = 'utm_content', required allow, hosts = const []})`: the
  in-app path, or `null`. Only paths under an allowlisted prefix pass
  (`/items` allows `/items` and `/items/42`, never `/itemsX`). Absolute URLs
  are refused unless they are `https` on a listed host; `//host`, `..`,
  backslashes, control characters and percent escapes that are malformed or
  not UTF-8 (`%ZZ`, `%FF`) are always refused. It never throws: the referrer
  is input anyone can craft, so anything that is not a safe path is `null`.
- `deepLinkResult(...)`: the same check, but it says **why** there is no
  link. Use it to log why an attributed install landed on the home screen:

  ```dart
  switch (referrer.deepLinkResult(allow: ['/invite/'])) {
    case DeepLinkFound(:final uri):
      router.go(uri.toString());
    case DeepLinkRejected(:final reason):
      log('No deep link: ${reason.name}'); // never throws either
  }
  ```

  The `DeepLinkRejection` values are `absent`, `unsafe`, `undecodable`,
  `notAPath`, `hostNotAllowed`, `looksDoubleEncoded` and `notAllowlisted`.
  `looksDoubleEncoded` is the common link-builder bug: after one decode the
  value is `%2Finvite%2Fabc123`, and one more decode would give an
  allowlisted link. It is reported, **never repaired**. Repairing it would
  hide the builder bug and corrupt paths that really contain `%2F`.
- `InstallReferrer(raw, decoding: ReferrerDecoding.rfc3986)`: see
  [the decoding rule](#the-decoding-rule). `referrer.withDecoding(...)`
  re-reads the same `raw` string.

### The decoding rule

A deferred link crosses two codebases. A **link builder** (a server, an edge
redirect, a CLI) puts the in-app path into the store URL. The **app**
decodes it. Each side's tests usually pin only its own literal, so both can
stay green while disagreeing. Here is the rule this plugin applies:

1. The builder encodes the path **once** as the value of `utm_content`, and
   the whole referrer **once more** as the store URL's `referrer=`
   parameter: `/invite/abc123` → `utm_content=%2Finvite%2Fabc123` →
   `&referrer=utm_content%3D%252Finvite%252Fabc123`. `PlayStoreUrl` does
   exactly this.
2. Play removes the outer layer and hands the app
   `utm_content=%2Finvite%2Fabc123`.
3. `InstallReferrer` splits on `&`, then splits each piece at its first `=`.
   It decodes each key and value **once** and keeps the first occurrence of
   a key. The default decoding is `ReferrerDecoding.form`
   ([`application/x-www-form-urlencoded`](https://url.spec.whatwg.org/#application/x-www-form-urlencoded)):
   `+` is a space and `%XX` is UTF-8.
   `ReferrerDecoding.rfc3986`
   ([RFC 3986 §2.1](https://www.rfc-editor.org/rfc/rfc3986#section-2.1)) is
   the same, except that `+` stays `+`.
4. `deepLink` checks the value in a fixed order and returns the first
   failure as the `DeepLinkRejection`.

The two decodings agree on everything a real encoder produces: form
encoders write a space as `+` and a `+` as `%2B`, and RFC 3986 encoders
(`encodeURIComponent`) write `%20` and `%2B`. They disagree only on a
**literal** `+`, which appears when the builder did not encode the value at
all:

| Referrer as Play returns it | `form` (default) | `rfc3986` |
|---|---|---|
| `utm_content=%2Fitems%2Fa%2Bb` | `/items/a+b` | `/items/a+b` |
| `utm_content=%2Fitems%2Fa+b` | `/items/a b` | `/items/a+b` |
| `utm_content=/items/a+b` (not encoded) | `/items/a b` | `/items/a+b` |

#### Test your link builder against the vectors

[`test/vectors/deep_link_vectors.json`](test/vectors/deep_link_vectors.json)
is a language-neutral table of the rule above. For each row, it gives:

- the referrer as Play returns it, and the `decoding`;
- the `value` after one decode;
- the `expected_deep_link`, or the `rejection` reason;
- for rows built from a `path`, the exact `play_url_referrer_param` and
  `play_store_url` a builder must emit.

The rows include `+`, `%`, `&`, `=`, `#`, a query, non-ASCII, an encoded
slash inside a segment, double encoding, and every rejection reason. The
plugin's own tests check `InstallReferrer` and `PlayStoreUrl` against every
row. A backend in any language can load the same file. Pin it to a release
tag, for example
`https://raw.githubusercontent.com/saimskywalker/flutter-imaji-install-attribution/v0.2.0/test/vectors/deep_link_vectors.json`
(available from 0.2.0). For example, in Python:

```python
import json, urllib.parse, urllib.request

URL = "https://raw.githubusercontent.com/saimskywalker/flutter-imaji-install-attribution/v0.2.0/test/vectors/deep_link_vectors.json"
doc = json.load(urllib.request.urlopen(URL))
for row in doc["vectors"]:
    if "path" in row:  # a row a builder must reproduce
        referrer = my_build_referrer({doc["key"]: row["path"]})
        assert referrer == row["referrer_as_play_returns_it"], row["name"]
        assert my_store_url(doc["package_name"], referrer) == row["play_store_url"]
```

### Consume once, on the first launch only

`readOnce()` returns `null` after `markHandled()`. Nothing is marked
automatically, so a crash between reading and routing does not lose the
link. The marker is a tiny file excluded from backups (`noBackupFilesDir` on
Android, an excluded file in Application Support on iOS): an uninstall and
reinstall starts unhandled again, which matches Play — a reinstall gets a
fresh referrer. `isHandled()` and `clearHandled()` exist for debug menus.

Google's guidance is to act on the referrer only on the first execution
after install. Play keeps returning the same referrer for 90 days, so
"unhandled" alone is not enough. `readOnce()` has three options for that.
Each one that applies marks the install handled and returns `null`, and
`InstallAttribution.lastSkipReason` (a `ReadOnceSkip`) says why. `claimOnce()`
takes the same options. A
suppressed referrer is silent: nothing is returned, so nothing can route or
show a banner about it.

| Option | Default | What it does |
|---|---|---|
| `treatUpgradesAsHandled` | `true` | An install that existed before the plugin is handled. That is an app updated since it was installed, where the plugin first ran after that update. Android only; it needs no Play Store call. |
| `maxClickAge` | `null` (no limit) | A Play click older than this is handled. Uses Play's server clock (`clickedAtServer`) when reported, else `clickedAt`; an unknown click time is never stale. Pick the window your links are meant for, such as an invite's validity. |
| `pastInstallFlow` | `null` | Your own "this user is past the install flow" check, asked before Play. See [the recipe](#route-only-while-the-user-is-still-in-the-install-flow). |

```dart
final result = await InstallAttribution.readOnce(
  maxClickAge: const Duration(days: 7), // your link's lifetime
  pastInstallFlow: () => session.isSignedIn && firstRunDoneOnThisDevice,
);
```

**How upgrades are detected (Android).** The plugin records the first time
it starts on an install, in `noBackupFilesDir`. `readOnce()` treats the
install as an upgrade when two conditions both hold:

- `PackageInfo.lastUpdateTime` is more than a minute after
  `firstInstallTime`, so the app has been updated since it was installed.
- The plugin's first start came after that update.

A fresh install is never affected, and neither is an install that had
0.2.0 or later from day one. Unknown facts never count as an upgrade.

Two known limits:

- **An install that started on 0.1.x** counts as adopted in an update on
  its first 0.2.0 launch, and is marked handled. 0.1.x kept no first-seen
  record, so the record is written after the update that brought 0.2.0.
  That install already had its first launch under 0.1.x. Pass
  `treatUpgradesAsHandled: false` if an app on 0.1.x still needs that
  install's referrer.
- An app installed from a link, never opened, and auto-updated before its
  first launch counts as an upgrade, so its link is skipped. Its click is
  at least as old as that update anyway.

Pass `treatUpgradesAsHandled: false` to keep the 0.1 behaviour.

**iOS.** There is no referrer to protect, so `treatUpgradesAsHandled` and
`maxClickAge` are no-ops (the AdServices token carries no click time).
`pastInstallFlow` is app state and applies on both platforms.

### Route only while the user is still in the install flow

A deferred link belongs to the install, sign-up and first-run flow. A
reliable "past the install flow" check needs **both** halves:

1. **Signed in.** Signed in alone is wrong: a reinstall that restores a
   session (an account manager, a credential restore, a server that
   remembers the device) is still a first run, and its link should route.
2. **The first run already completed on this device.** Keep this flag out
   of backups. Android Auto Backup and device-to-device transfer restore
   `SharedPreferences` by default. A reinstall would then inherit "first
   run done" and spend the link silently. Keep the flag in a file under
   `noBackupFilesDir`, or exclude its preferences file from backup:

```xml
<!-- res/xml/data_extraction_rules.xml (Android 12+), referenced from
     android:dataExtractionRules; mirror it in android:fullBackupContent
     for Android 11 and lower. -->
<data-extraction-rules>
  <cloud-backup>
    <exclude domain="sharedpref" path="first_run.xml"/>
  </cloud-backup>
  <device-transfer>
    <exclude domain="sharedpref" path="first_run.xml"/>
  </device-transfer>
</data-extraction-rules>
```

```dart
final result = await InstallAttribution.readOnce(
  pastInstallFlow: () async =>
      await auth.isSignedIn() && await firstRun.completedOnThisDevice(),
);
```

If the check throws, `readOnce()` returns `null` without marking anything,
and the next launch asks again.

### `claimOnce`: one claim, a retry budget

`claimOnce()` is `readOnce()` with three guarantees for apps that have more
than one startup path:

- **One claim per process.** While a claim is held, every other
  `claimOnce()` in the process returns `null` (`claimedElsewhere`). A link
  cannot be dispatched twice by a first-frame callback and a later "router
  ready" path. The lock is taken before the first `await`.
  `claim.complete()` marks the install handled. `claim.release()` leaves it
  unhandled, for when the link did not land (no router, or a newer tapped
  link took precedence). The next launch, or a later `claimOnce()`, then
  tries again.
- **A retry budget across launches.** A failed read returns `null`
  (`readFailed`, details in `lastFailure`). The failure is counted in a file
  next to the handled marker, which survives process death, is excluded
  from backups and is cleared by `clearHandled()`. After `maxFailedReads`
  failures the install is marked handled (`budgetSpent`), and no later
  launch binds to the Play Store again.
- **Terminal reasons** in `terminal` mark the install handled on first sight
  (`terminalFailure`).

| Parameter | Default | Why |
|---|---|---|
| `maxFailedReads` | `3` | A failed Android read costs a service bind and up to the timeout (10 s) of background work, on every launch, forever. Three launches separate a transient failure (Play updating itself, a busy device) from a device that cannot answer. Raise it if first launches are often offline. |
| `terminal` | `{playStoreMissing}` | Without the Play Store there is no Play install, and so no referrer, even if Play is installed later. Add `permissionError` if you would rather not retry a manifest problem; pass `const {}` to count everything against the budget. |

`readOnce()` keeps its 0.1 shape (no lock, no budget) for apps that manage
those themselves.

### `InstallSource`

`InstallAttribution.installSource()` (or `result.installSource`) reports the
installer package — `getInstallSourceInfo()` on API 30+,
`getInstallerPackageName()` below — mapped to `InstallStore`: `googlePlay`,
`galaxyStore`, `huaweiAppGallery`, `amazonAppstore`, `sideload`, `restore`,
`other`. It cannot tell which chat app a link was shared in; only a
`utm_source` on the link can.

### `PlayStoreUrl`

`PlayStoreUrl.web(packageName:, referrer: {...})` and `.market(...)` build
store links whose referrer is encoded exactly once. See
[TESTING.md](TESTING.md#4-building-the-play-url).

#### Building links on a server

Store links are usually built by a backend, which cannot import a Flutter
package. [`imaji_referrer_builder`](packages/imaji_referrer_builder) is the
same builder in pure Dart with no dependencies: it appends the path to a
configured campaign string without changing it, encodes it once, and
refuses paths the app would not route. Its README lists the five rules a
builder in any language must follow, and
[`test/vectors/referrer_vectors.json`](test/vectors/referrer_vectors.json)
is the file both sides are tested against — test your link builder against
it.

### Testing

- `InstallAttribution.debugOverride(referrer: ..., clickedAt: ...)`: debug
  builds only; profile and release builds ignore it.
- `ImajiInstallAttributionPlatform.instance = FakeAttribution();`: unit tests
  without a device.
- **[TESTING.md](TESTING.md)**: how to see a real referrer. Only a build that
  Google Play installed has one; side-loads never do.

## Migrating from other plugins

**If your app already shipped referrer handling, call `adoptExistingState`
first.** Without it, an existing user can be routed to a stale link on the
first launch after the update. For example, a user installed from
`/invite/abc123` 40 days ago, and your previous code already routed that
link. Play still returns the same referrer, and the plugin cannot see your
old "done" flag. `treatUpgradesAsHandled` catches this case from the device
alone, and your own flag makes it certain:

```dart
await InstallAttribution.adoptExistingState(
  alreadyHandled: prefs.getBool('referrer_done') ?? false, // your old flag
);
final result = await InstallAttribution.readOnce();
```

`true` marks the install handled; `false` changes nothing. It is idempotent,
so calling it on every launch is fine.

### From `play_install_referrer`

```dart
// Before
try {
  final details = await PlayInstallReferrer.installReferrer;
  handle(details.installReferrer, details.referrerClickTimestampSeconds);
} catch (e) {
  // PlatformException, or a native crash before this line runs
}

// After
if (await InstallAttribution.read()
    case Attributed(:final referrer?, :final clickedAt)) {
  handle(referrer.raw, clickedAt);
}
```

`referrerClickTimestampSeconds` → `clickedAt` (a UTC `DateTime`, `null`
when Play reports 0); `installBeginTimestampSeconds` → `installBeganAt`;
`installVersion` → `installVersion`; the `*ServerSeconds` values →
`clickedAtServer` / `installBeganAtServer`.

If you split the referrer yourself, note which decoder you used. With
`Uri.splitQueryString` or `Uri.decodeQueryComponent` (form decoding,
`+` → space), the default matches. With `Uri.decodeComponent`, pass
`decoding: ReferrerDecoding.rfc3986`.

### From `android_play_install_referrer`

```dart
// Before
final info = await AndroidPlayInstallReferrer.installReferrer;
final source = Uri.splitQueryString(info.installReferrer ?? '')['utm_source'];

// After
final source = switch (await InstallAttribution.read()) {
  Attributed(:final referrer?) => referrer.utmSource,
  _ => null,
};
```

Error codes become reasons: `FEATURE_NOT_SUPPORTED` → `featureNotSupported`,
`PERMISSION_ERROR` → `permissionError`, `SERVICE_UNAVAILABLE` →
`serviceUnavailable`, `SERVICE_DISCONNECTED` → `serviceDisconnected`,
`DeadObjectException` → `deadService`.

### From `stack_deferred_link`

```dart
// Before
final info = await StackDeferredLink.getInstallReferrerAndroid();
final path = Uri.decodeComponent(info.installReferrer); // decodes again

// After
final link = switch (await InstallAttribution.read()) {
  Attributed(:final referrer?) => referrer.deepLink(allow: ['/items/']),
  _ => null,
};
```

Drop any extra `Uri.decodeComponent` on referrer values: `parameters` are
already decoded once, and decoding again corrupts paths containing `%2F`.
If your old code decoded the values themselves with `Uri.decodeComponent`
(RFC 3986, where `+` stays `+`), construct the referrer with
`InstallReferrer(raw, decoding: ReferrerDecoding.rfc3986)` to keep the same
answers; see [the decoding rule](#the-decoding-rule). On
iOS this plugin reads the AdServices token rather than the clipboard; keep a
clipboard or "paste link" flow of your own if you rely on one.

## Comparison

| | imaji_install_attribution | play_install_referrer | android_play_install_referrer | stack_deferred_link |
|---|---|---|---|---|
| Play Install Referrer | Yes | Yes | Yes | Yes |
| iOS | AdServices token | No | No | Clipboard |
| No Kotlin Gradle Plugin (AGP 9 built-in Kotlin) | Yes | Applies KGP | Applies KGP | Applies KGP |
| Binder call off the platform thread | Yes | No | No | No |
| Timeout | Yes | No | No | No |
| Null details bundle | Typed result | Crash | Crash | Crash |
| Failures | Typed `UnavailableReason` | `PlatformException` | `PlatformException` | `PlatformException` |
| Deep-link helper | Allowlist, single decode, typed rejection reasons, cross-language vectors | No | No | Pattern list |
| Consume-once store | Yes | No | No | No |
| Installer / store detection | Yes | No | No | No |
| Debug override + testing guide | Yes | No | No | No |

"Crash" in the null-details row: every getter of Play's `ReferrerDetails`
reads its bundle, so a null bundle throws `NullPointerException` on the
first read, and each of those plugins makes that read while building its
result, outside any `try`, on the main thread.

Based on each project's public default branch and issue tracker in October
2026. Corrections are welcome.

## FAQ

**Do I need the App Tracking Transparency prompt on iOS?** No. Fetching the
AdServices token does not require ATT. Resolving it is a server-to-Apple call
outside this plugin.

**Why do I always get `Organic` while developing?** Because Play did not
install your debug build. See [TESTING.md](TESTING.md).

**Is there a deferred deep link on iOS?** Not from the platform. The
AdServices token tells your server about Apple Ads campaigns; it carries no
custom payload.

**Can I call `read()` on every launch?** Yes. Concurrent calls share one
read, and Play keeps the referrer for 90 days. `readOnce()` skips the call
entirely once you have handled it.

**Does it build with AGP 8 or `builtInKotlin=false`?** Yes; see
[Android build setup](#android-build-setup).

**Does it fingerprint users?** No. It reads what the platform hands the app
and nothing else.

## Non-goals

- Fingerprinting, or any matching that identifies a person across apps.
- A hosted attribution service, or calling Apple's attribution API for you.

## Contributing

Issues and pull requests are welcome — especially device reports
("Play returned X on <OEM> Android N"), since referrer behaviour varies by
vendor and Play Store version.

Run the checks CI runs:

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
cd example && flutter build apk --debug
cd example/android && ./gradlew :imaji_install_attribution:testDebugUnitTest
```

Building the example **for iOS** has one quirk: Xcode resolves the plugin's
Swift package through its real path, and that package's identity is its
directory name. Clone into a folder named `imaji_install_attribution` (CI does
the same) or `xcodebuild` refuses to resolve packages with *"unable to
override package 'imaji_install_attribution'"*. Apps that depend on the
plugin are not affected.

## Support

If this plugin saved you a day of chasing referrers, a ⭐ on the repository
helps other Flutter developers find it.

## License

MIT © saimskywalker. See [LICENSE](LICENSE).
