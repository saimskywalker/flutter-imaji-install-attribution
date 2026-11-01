# API guide

The full API reference is on
[pub.dev](https://pub.dev/documentation/imaji_install_attribution/latest/).
This page explains the main types and how they fit together.

## `InstallAttribution.read({Duration timeout})`

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

To act on the referrer only once, use `readOnce()` or `claimOnce()`; see
[Consume once](consume-once.md).

## `InstallReferrer`

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
  [the decoding rule](decoding.md). `referrer.withDecoding(...)` re-reads the
  same `raw` string.

## `InstallSource`

`InstallAttribution.installSource()` (or `result.installSource`) reports the
installer package (`getInstallSourceInfo()` on API 30+,
`getInstallerPackageName()` below), mapped to `InstallStore`: `googlePlay`,
`galaxyStore`, `huaweiAppGallery`, `amazonAppstore`, `sideload`, `restore`,
`other`. It cannot tell which chat app a link was shared in; only a
`utm_source` on the link can.

## `PlayStoreUrl`

`PlayStoreUrl.web(packageName:, referrer: {...})` and `.market(...)` build
store links whose referrer is encoded exactly once. See
[TESTING.md](../TESTING.md#4-building-the-play-url).

### Building links on a server

Store links are usually built by a backend, which cannot import a Flutter
package. [`imaji_referrer_builder`](../packages/imaji_referrer_builder) is
the same builder in pure Dart with no dependencies: it appends the path to a
configured campaign string without changing it, encodes it once, and
refuses paths the app would not route. Its README lists the five rules a
builder in any language must follow, and
[`test/vectors/referrer_vectors.json`](../test/vectors/referrer_vectors.json)
is the file both sides are tested against. Test your link builder against
it.

## Testing

- `InstallAttribution.debugOverride(referrer: ..., clickedAt: ...)`: debug
  builds only; profile and release builds ignore it.
- `ImajiInstallAttributionPlatform.instance = FakeAttribution();`: unit tests
  without a device.
- **[TESTING.md](../TESTING.md)**: how to see a real referrer. Only a build
  that Google Play installed has one; side-loads never do.
