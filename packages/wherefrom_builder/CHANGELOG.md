## 0.2.0

- Renamed from `imaji_referrer_builder`. To migrate, replace the dependency
  (`imaji_referrer_builder: ^0.1.1` → `wherefrom_builder: ^0.2.0`) and the
  import (`package:imaji_referrer_builder/imaji_referrer_builder.dart` →
  `package:wherefrom_builder/wherefrom_builder.dart`). No API change. The
  repository is now `github.com/saimskywalker/wherefrom` and the package
  lives in `packages/wherefrom_builder`.
- README: the shared vectors moved with the Flutter plugin to
  `packages/wherefrom/test/vectors/referrer_vectors.json` in the
  repository. Older tags keep them at
  `packages/imaji_install_attribution/test/vectors/` (`v0.2.2`) or
  `test/vectors/` (up to `imaji_referrer_builder-v0.1.1` and `v0.2.1`).

## 0.1.1

Packaging: shorter package description so pub.dev search shows it whole.
No API change.

## 0.1.0

First release.

- `PlayStoreUrl.appendPath(campaign, path, {allow, hosts, key,
  targetIsPublic})` appends one `utm_content` (or custom key) pair to a
  configured campaign string, which it keeps byte for byte, with the path
  encoded exactly once. `null` path or `targetIsPublic: false` returns the
  campaign unchanged; an empty campaign gives the pair alone.
- Throws `ArgumentError` on a path the app would not route (same rules as
  `InstallReferrer.deepLink` in `imaji_install_attribution`, plus surrounding
  whitespace and dot segments), on a campaign that already holds the key
  (the app keeps the first occurrence), on a campaign starting with `?`, and
  on an empty key.
- `PlayStoreUrl.checkPath` returns a typed `PathRefusal` instead of throwing;
  `PlayStoreUrl.expectedDeepLink` returns the link the app will route.
- `PlayStoreUrl.webFromReferrer` / `marketFromReferrer` build the store links
  with the referrer encoded once as the `referrer` parameter; `web`, `market`
  and `encodeReferrer` match the Flutter plugin's `PlayStoreUrl` byte for
  byte.
- Tested against the repository's shared vectors
  (`test/vectors/referrer_vectors.json`), which the Flutter plugin's parser
  tests read too. No Flutter dependency and no runtime dependencies.
