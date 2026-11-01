# Adopting in an app that already reads the referrer

**If your app already shipped referrer handling, call `adoptExistingState`
first.** Without it, an existing user can be routed to a stale link on the
first launch after the update. For example, a user installed from
`/invite/abc123` 40 days ago, and your previous code already routed that
link. Play still returns the same referrer, and the plugin cannot see your
old "done" flag. `treatUpgradesAsHandled` (see
[Consume once](consume-once.md)) catches this case from the device alone,
and your own flag makes it certain:

```dart
await InstallAttribution.adoptExistingState(
  alreadyHandled: prefs.getBool('referrer_done') ?? false, // your old flag
);
final result = await InstallAttribution.readOnce();
```

`true` marks the install handled; `false` changes nothing. It is idempotent,
so calling it on every launch is fine.

## Mapping Play's fields and response codes

Play's `ReferrerDetails` fields map to `Attributed` like this:
`getInstallReferrer()` → `referrer.raw`; `getReferrerClickTimestampSeconds()`
→ `clickedAt` (a UTC `DateTime`, `null` when Play reports 0);
`getInstallBeginTimestampSeconds()` → `installBeganAt`; `getInstallVersion()`
→ `installVersion`; the `*ServerSeconds` values → `clickedAtServer` /
`installBeganAtServer`.

```dart
if (await InstallAttribution.read()
    case Attributed(:final referrer?, :final clickedAt)) {
  handle(referrer.raw, clickedAt);
}
```

`InstallReferrerResponse` codes become reasons: `FEATURE_NOT_SUPPORTED` →
`featureNotSupported`, `PERMISSION_ERROR` → `permissionError`,
`SERVICE_UNAVAILABLE` → `serviceUnavailable`, `SERVICE_DISCONNECTED` →
`serviceDisconnected`, and a `DeadObjectException` → `deadService`.

## Decoding

If your code split or decoded the referrer itself, note which decoder it
used. `parameters` are already decoded once, and decoding again corrupts
paths containing `%2F`. With `Uri.splitQueryString` or
`Uri.decodeQueryComponent` (form decoding, `+` → space) the default matches;
with `Uri.decodeComponent` (RFC 3986, where `+` stays `+`), construct the
referrer with `InstallReferrer(raw, decoding: ReferrerDecoding.rfc3986)`; see
[the decoding rule](decoding.md).

## iOS

On iOS this plugin reads the AdServices token and never the clipboard; keep
a clipboard or "paste link" flow of your own if you rely on one.
