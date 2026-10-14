# Testing install attribution

The question everyone asks about install referrers is not "how do I read it"
but "how do I see a real one before I ship". This guide is the answer for
`imaji_install_attribution`, on Android and iOS.

**Short version:** a *real* Play referrer only exists for a build that Google
Play itself installed. Everything else — `flutter run`, a side-loaded APK, an
emulator without the Play Store — is expected to report `Organic` or
`Unavailable`. Exercise your *routing* with `debugOverride`, and test the
*Play hand-off* once, on a real device, with a Play-installed build.

- [1. Test your routing anywhere: `debugOverride`](#1-test-your-routing-anywhere-debugoverride)
- [2. What each environment really returns](#2-what-each-environment-really-returns)
- [3. Getting a real referrer from Play](#3-getting-a-real-referrer-from-play)
- [4. Building the Play URL](#4-building-the-play-url)
- [5. `(not set)` and other surprises](#5-not-set-and-other-surprises)
- [6. iOS: the AdServices token](#6-ios-the-adservices-token)
- [7. Unit tests in your app](#7-unit-tests-in-your-app)

## 1. Test your routing anywhere: `debugOverride`

```dart
void main() {
  if (kDebugMode) {
    InstallAttribution.debugOverride(
      referrer: 'utm_source=newsletter&utm_content=%2Fitems%2F42',
      clickedAt: DateTime.now().subtract(const Duration(minutes: 2)),
    );
  }
  runApp(const MyApp());
}
```

- The `referrer` is the string **exactly as Play would return it** — inner
  values encoded once. It goes through the same classification as a real
  one, so `utm_source=google-play&utm_medium=organic` gives you `Organic`.
- `debugOverride(result: const Unavailable(UnavailableReason.timeout))`
  simulates a failure.
- The override lives inside an `assert`, so **profile and release builds
  ignore it** and always ask the platform. A forgotten call cannot ship.
- `InstallAttribution.debugClearOverride()` removes it.

The example app has buttons for each of these.

## 2. What each environment really returns

| How the app got onto the device | Android result |
|---|---|
| `flutter run`, `adb install`, an APK from a file | `Organic` (Play answers with its default `utm_source=google-play&utm_medium=organic`) or `Unavailable`. Never your campaign. `installSource.store` is `sideload`. |
| Emulator image **without** Play ("Google APIs") | `Unavailable(playStoreMissing)` |
| Emulator image with an old Play Store | often `Unavailable(featureNotSupported)` |
| Device without Google Play (AOSP, many Huawei / Fire devices) | `Unavailable(playStoreMissing)` |
| Installed from Play from a link **with** `&referrer=` | `Attributed` with your referrer — subject to the track caveats below |
| Installed from Play by searching the store | `Organic` |
| Installed from Galaxy Store / AppGallery / Amazon | Play has no record of the install: `Organic` or `Unavailable`. Check `installSource.store`. |
| Restored by a backup / transfer tool (for example Samsung Smart Switch) | No campaign. `installSource.store` is `restore`. |

Play keeps the referrer for **90 days** after install, and it does not change
until the app is reinstalled. Reading it on every launch is allowed, but
`readOnce()` + `markHandled()` saves the Binder call once you have acted on it.

## 3. Getting a real referrer from Play

You need a build that the Play Store installed. Two routes work for testing
without a public release:

- **Internal app sharing** — upload an APK/AAB in Play Console → *Internal app
  sharing*, and open the generated link on the test device.
- **Internal testing track** — add your Google account as a tester, accept the
  opt-in link, then install from the store listing.

Reports from many developers agree on the important part: **whether a custom
`referrer=` reaches the app on a testing track is not guaranteed.** Some
installs from the internal testing track come back as
`utm_source=(not set)&utm_medium=(not set)` even when the link carried a
referrer (see section 5). If you see that, it is Play, not the plugin. The
only fully representative test is a production (or staged rollout) install
from a referrer link.

Step by step, on a **physical device** signed in to a tester account:

1. Uninstall the app completely.
2. Optional but recommended: *Settings → Apps → Google Play Store → Storage →
   Clear cache*, so Play does not reuse an earlier visit.
3. Open the store URL **with the referrer** on the device. Typing it into a
   browser works; so does adb:

   ```bash
   adb shell am start -a android.intent.action.VIEW \
     -d "https://play.google.com/store/apps/details?id=com.example.app&referrer=utm_source%3Dqa%26utm_content%3D%252Fitems%252F42"
   ```

4. Tap **Install** on that page. Installing from *My apps* or from search
   loses the referrer.
5. Open the app (from Play's **Open** button or the launcher).
6. `InstallAttribution.read()` should return `Attributed` with
   `referrer['utm_content'] == '/items/42'`.

Checklist when it does not:

- [ ] The device really had **no** copy of the app before step 4.
- [ ] The install came from the page opened in step 3.
- [ ] The referrer value is URL-encoded **once** as a parameter (use
      `PlayStoreUrl` below rather than building it by hand).
- [ ] The merged manifest still contains
      `com.google.android.finsky.permission.BIND_GET_INSTALL_REFERRER_SERVICE`
      (added by the Install Referrer library). Removing it produces
      `Unavailable(permissionError)`.
- [ ] `installSource.store == InstallStore.googlePlay`. Anything else means
      Play did not install this copy.

## 4. Building the Play URL

The referrer is a query string *inside* a query parameter. Encode the inner
values once, then encode the whole string once as the `referrer` parameter.
`PlayStoreUrl` does exactly that:

```dart
final url = PlayStoreUrl.web(
  packageName: 'com.example.app',
  referrer: {
    'utm_source': 'newsletter',
    'utm_campaign': 'spring',
    'utm_content': '/items/42',
  },
);
// https://play.google.com/store/apps/details?id=com.example.app
//   &referrer=utm_source%3Dnewsletter%26utm_campaign%3Dspring%26utm_content%3D%252Fitems%252F42
```

Play strips the outer layer and hands the app
`utm_source=newsletter&utm_campaign=spring&utm_content=%2Fitems%2F42`;
`InstallReferrer` strips the inner layer once, giving `/items/42`.

Encoding the outer layer twice is the usual bug: the app then sees
`%252F...`-style values. Decoding the inner layer twice is the other one: a
path that genuinely contains `%2F` loses it. The plugin never decodes twice.

`PlayStoreUrl.market(...)` builds the `market://details?...` form that opens
the Play Store app directly.

## 5. `(not set)` and other surprises

- **`utm_source=(not%20set)&utm_medium=(not%20set)`** — Play's placeholder
  when it has an install record but no campaign: the store page was opened
  without a usable `referrer`, or a testing track did not forward it. The
  plugin classifies a referrer that contains nothing but `(not set)` / empty
  `utm_*` values as `Organic`, and `referrer.utmSource` returns `null` for
  `(not set)`. The raw string is still in `referrer.raw`.
- **`utm_source=google-play&utm_medium=organic`** — Play's default for an
  install with no referrer (store search, side-load). `Organic`.
- **Custom keys** such as `custom_id=8` or a bare token `abc123` are
  preserved and make the install `Attributed`.
- **Click time is 0** — Play reports 0 for "unknown"; the plugin turns that
  into `clickedAt == null`, not 1 January 1970.
- **A link shared in a chat app** — Android cannot tell you which app the user
  tapped the link in. It only shows up if the link itself carried a
  `utm_source` (for example `utm_source=chat-share`).

## 6. iOS: the AdServices token

- `read()` returns `Attributed(source: AttributionSource.appleAds, token: ...)`
  on a **physical device**. The **simulator** returns
  `Unavailable(notSupported)` by design.
- No App Tracking Transparency prompt is needed to fetch the token.
- The token is opaque and valid for 24 hours. To learn whether the install
  came from an Apple Ads campaign, your **server** POSTs it to Apple's
  AdServices attribution API. Only installs that followed an Apple Ads tap
  resolve to campaign data; that call is out of scope for this plugin.
- iOS has no equivalent of the Play referrer, so there is no deferred deep
  link payload on iOS. Common alternatives: a "paste link" button, or a
  server-side match you are comfortable defending to your users.
- `UnavailableReason.networkError` means AdServices could not reach Apple;
  try again on a later launch.

## 7. Unit tests in your app

Install a fake platform; no device or channel needed:

```dart
class FakeAttribution extends ImajiInstallAttributionPlatform {
  @override
  Future<InstallAttributionResult> read({required Duration timeout}) async =>
      Attributed(
        source: AttributionSource.googlePlay,
        referrer: InstallReferrer('utm_content=%2Fitems%2F42'),
      );

  bool handled = false;
  @override
  Future<bool> isHandled() async => handled;
  @override
  Future<bool> markHandled() async => handled = true;
  @override
  Future<bool> clearHandled() async => !(handled = false);
}

setUp(() => ImajiInstallAttributionPlatform.instance = FakeAttribution());
```
