# imaji_install_attribution

A Flutter plugin that tells your app where an install came from (the Google
Play Install Referrer on Android, the Apple AdServices token on iOS) and
turns it into the deep link the user wanted before they installed.

[![pub version](https://img.shields.io/pub/v/imaji_install_attribution)](https://pub.dev/packages/imaji_install_attribution)
[![pub points](https://img.shields.io/pub/points/imaji_install_attribution)](https://pub.dev/packages/imaji_install_attribution/score)
[![pub likes](https://img.shields.io/pub/likes/imaji_install_attribution)](https://pub.dev/packages/imaji_install_attribution/score)
[![CI](https://github.com/saimskywalker/flutter-imaji-install-attribution/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/saimskywalker/flutter-imaji-install-attribution/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/github/license/saimskywalker/flutter-imaji-install-attribution)](https://github.com/saimskywalker/flutter-imaji-install-attribution/blob/main/LICENSE)

## Why

- Firebase Dynamic Links is gone. To carry a link through a store install,
  you now read the platform's own referrer yourself.
- Reading it safely is full of traps: a Binder call that freezes the UI, a
  null bundle that throws, a value decoded twice, and a 90-day-old referrer
  routed again on every launch or after an update.
- You want one typed answer on both platforms, without manifest edits,
  `Info.plist` keys or an App Tracking Transparency prompt.

## Install

```bash
flutter pub add imaji_install_attribution
```

Flutter 3.44+ / Dart 3.12+, Android minSdk 21, iOS 15. Swift Package Manager
and CocoaPods both work. Nothing to configure on Android or iOS
([setup details](https://github.com/saimskywalker/flutter-imaji-install-attribution/blob/main/doc/setup.md)).

## Quick start

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
`lastFailure` say why `claimOnce()` returned `null`. To try your routing
without a Play install, call `InstallAttribution.debugOverride(referrer: ...)`
in a debug build; see the
[testing guide](https://github.com/saimskywalker/flutter-imaji-install-attribution/blob/main/TESTING.md).

## Example output

The quick start above, run against the referrer
`utm_source=newsletter&utm_campaign=spring&utm_content=%2Fitems%2F42`:

```text
read(): Attributed(source: googlePlay, referrer: utm_source=newsletter&utm_campaign=spring&utm_content=%2Fitems%2F42, token: null, clickedAt: null)
routed: [/items/42]
second launch: claimOnce() -> null (handled)
```

`referrer.deepLinkResult(allow: ['/items/'])` says why a referrer has no
link:

```text
utm_content=%2Fitems%2F42                           -> DeepLinkFound(/items/42)
utm_content=%252Fitems%252F42                       -> DeepLinkRejected(looksDoubleEncoded)
utm_content=%2Fadmin                                -> DeepLinkRejected(notAllowlisted)
utm_content=https%3A%2F%2Fevil.example%2Fitems%2F1  -> DeepLinkRejected(hostNotAllowed)
utm_content=%2F%2Fevil.example                      -> DeepLinkRejected(unsafe)
utm_source=google-play&utm_medium=organic           -> DeepLinkRejected(absent)
```

## Features

| Feature | What you get |
|---|---|
| One typed result | `Attributed`, `Organic` or `Unavailable(reason)` from a `read()` that never throws |
| No ANR | Every Play Binder call runs on a background thread, with a timeout (default 10 s) |
| Typed failures | `DeadObjectException`, `PERMISSION_ERROR`, a null bundle and more each get their own `UnavailableReason` |
| Consume once | `readOnce()` / `claimOnce()`: first launch only, one claim per process, a persisted retry budget, upgrades skipped |
| Safe deep links | `deepLink(allow: [...])` decodes exactly once and only returns allowlisted paths |
| Installer detection | `InstallSource`: Play, Galaxy Store, AppGallery, Amazon, side-load, restore |
| Link building | `PlayStoreUrl` here, and [`imaji_referrer_builder`](https://pub.dev/packages/imaji_referrer_builder) for pure-Dart backends, both tested against shared JSON vectors |
| Built-in Kotlin | No Kotlin Gradle Plugin line, so Flutter's KGP warning never names this plugin |
| Testable | `debugOverride()` for debug builds, a replaceable platform for unit tests |

## Documentation

- [API guide](https://github.com/saimskywalker/flutter-imaji-install-attribution/blob/main/doc/api.md): results, reasons, `InstallReferrer`, `InstallSource`, `PlayStoreUrl`
- [Consume once](https://github.com/saimskywalker/flutter-imaji-install-attribution/blob/main/doc/consume-once.md): `readOnce()`, upgrade detection, the install-flow recipe, `claimOnce()`
- [The decoding rule](https://github.com/saimskywalker/flutter-imaji-install-attribution/blob/main/doc/decoding.md) and the language-neutral test vectors
- [Adopting in an app that already reads the referrer](https://github.com/saimskywalker/flutter-imaji-install-attribution/blob/main/doc/migration.md)
- [Setup](https://github.com/saimskywalker/flutter-imaji-install-attribution/blob/main/doc/setup.md): requirements, tracking `main`, Android build setup
- [Testing guide](https://github.com/saimskywalker/flutter-imaji-install-attribution/blob/main/TESTING.md): how to see a real referrer from Play
- [FAQ](https://github.com/saimskywalker/flutter-imaji-install-attribution/blob/main/doc/faq.md): ATT, iOS deep links, non-goals, alternatives

## Links

- [pub.dev page](https://pub.dev/packages/imaji_install_attribution)
- [API reference](https://pub.dev/documentation/imaji_install_attribution/latest/)
- [CHANGELOG](https://github.com/saimskywalker/flutter-imaji-install-attribution/blob/main/CHANGELOG.md)
- [Issues](https://github.com/saimskywalker/flutter-imaji-install-attribution/issues)
- [Contributing](https://github.com/saimskywalker/flutter-imaji-install-attribution/blob/main/CONTRIBUTING.md)

## Trademarks

Google Play and Android are trademarks of Google LLC. Apple, App Store and iOS
are trademarks of Apple Inc. This project is independent and is not affiliated
with, sponsored by or endorsed by Google or Apple.

## License

MIT © saimskywalker. See [LICENSE](https://github.com/saimskywalker/flutter-imaji-install-attribution/blob/main/LICENSE).
