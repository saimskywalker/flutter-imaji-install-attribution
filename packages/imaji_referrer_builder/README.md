# imaji_referrer_builder — build Play install-referrer links on a server

[![CI](https://github.com/saimskywalker/flutter-imaji-install-attribution/actions/workflows/ci.yml/badge.svg)](https://github.com/saimskywalker/flutter-imaji-install-attribution/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Pure Dart, **no Flutter, no runtime dependencies**. Builds the Google Play
`referrer=` value and store URL for a deferred deep link — the **builder**
half of the contract whose **app** half is `InstallReferrer` in the Flutter
plugin
[`imaji_install_attribution`](https://pub.dev/packages/imaji_install_attribution).

```dart
import 'package:imaji_referrer_builder/imaji_referrer_builder.dart';

final referrer = PlayStoreUrl.appendPath(
  'utm_source=share&utm_medium=social&utm_campaign=spring', // as configured
  '/invite/abc123',                                         // or null
  allow: ['/invite/', '/items/'],                           // same list as the app
);
// utm_source=share&utm_medium=social&utm_campaign=spring&utm_content=%2Finvite%2Fabc123

final url = PlayStoreUrl.webFromReferrer(
  packageName: 'com.example.app',
  referrer: referrer,
);
// https://play.google.com/store/apps/details?id=com.example.app
//   &referrer=utm_source%3Dshare%26utm_medium%3Dsocial%26utm_campaign%3Dspring
//   %26utm_content%3D%252Finvite%252Fabc123
```

## Why a server needs it

A deferred deep link has two halves. The app reads the referrer, decodes the
value once, checks an allowlist and routes. Something else — a redirect
server, an edge function, a CLI that prints campaign links — decides what
goes into `referrer=`. When the two disagree **nothing fails visibly**: Play
counts the install, the app reads an attributed referrer, finds no usable
path, and the user lands on the home screen.

The Flutter plugin already has a correct builder, but a backend cannot
import a Flutter package: `dart pub get` fails in an image that only has the
Dart SDK. So the builder gets rewritten by hand, which is where "encoded
twice" and "not encoded at all" come from. This package is that builder,
importable from a `shelf` server, a Cloud Run job or a CLI, and tested
against the same vector file as the app-side parser.

## Install

```bash
dart pub add imaji_referrer_builder
```

To track `main` before a release, or to pin a commit:

```yaml
dependencies:
  imaji_referrer_builder:
    git:
      url: https://github.com/saimskywalker/flutter-imaji-install-attribution
      path: packages/imaji_referrer_builder
      ref: main # or a commit SHA
```

## The five rules

`PlayStoreUrl.appendPath` enforces all of them; a hand-written builder
should too.

1. **Append, never replace.** The path rides in its own key (`utm_content`
   by default) next to the configured campaign keys. The configured string
   is kept **byte for byte** — not parsed and re-encoded — so `+` stays `+`,
   `%20` stays `%20`, key order and repeated keys stay as they are, and
   store-console campaign reporting is unaffected.
2. **The payload does not depend on a campaign being configured.** An empty
   campaign plus a path gives `utm_content=%2Finvite%2Fabc123`.
3. **One key, once.** The app keeps the **first** occurrence of a repeated
   key, so appending `utm_content` to a campaign that already holds one
   silently loses the path. `appendPath` throws instead (also for an
   encoded `utm%5Fcontent` or a bare `utm_content` token).
4. **Emit only paths the app routes.** A path outside the app's allowlist
   is counted as an install and lands on home. `appendPath` throws an
   `ArgumentError` naming the reason, with the same rules as
   `deepLink(allow: …, hosts: …)`: `/items` allows `/items` and `/items/42`,
   never `/itemsX`; `//host`, `.`/`..` segments, backslashes and control
   characters are refused; an absolute URL only as `https` on one of
   `hosts`. It is stricter in two places (surrounding whitespace, and a dot
   segment the URI parser would silently remove), because emitting either
   is a bug.
5. **A target that is not public carries no path.** The referrer is visible
   in the URL and Play keeps it for 90 days. For something deleted, private
   or hidden, pass `null` (or `targetIsPublic: false`) and you get a
   campaign-only link that does not name it.

A server bug should fail in the server's tests, so the builder **throws**;
the app side never does.

## API

| Member | What it does |
|---|---|
| `PlayStoreUrl.appendPath(campaign, path, {allow, hosts, key, targetIsPublic})` | Referrer string: `campaign` unchanged, plus `key=<path encoded once>`. Throws `ArgumentError` on a refused path, a campaign that already holds `key`, a campaign starting with `?`, or an empty `key`. |
| `PlayStoreUrl.checkPath(path, {allow, hosts})` | `PathRefusal?` — why the app would not route `path`, or `null`. For servers that prefer to fall back to a campaign-only link over throwing. |
| `PlayStoreUrl.expectedDeepLink(path, {allow, hosts})` | The `Uri` the app will route (`/items/a b` → `/items/a%20b`; an allowed `https` URL → its path), or `null`. Handy in server tests. |
| `PlayStoreUrl.webFromReferrer` / `marketFromReferrer` | `https://play.google.com/store/apps/details?…` / `market://details?…` with the referrer encoded once as the `referrer` parameter. |
| `PlayStoreUrl.web` / `market` / `encodeReferrer` (map form) | Identical to the Flutter plugin's `PlayStoreUrl`, byte for byte. |
| `PathRefusal` | `empty`, `surroundingWhitespace`, `forbiddenCharacter`, `malformed`, `notAPath`, `hostNotAllowed`, `unsafe`, `notAllowlisted`. |

Refusing without throwing:

```dart
final ok = item.isPublic &&
    PlayStoreUrl.checkPath(item.path, allow: allow) == null;
final referrer = PlayStoreUrl.appendPath(
  campaign,
  ok ? item.path : null,
  allow: allow,
);
```

## The encoding contract

```
path                   /items/a b
inner (value, once)    utm_content=%2Fitems%2Fa+b              <- what Play returns to the app
outer (param, once)    referrer=utm_content%3D%252Fitems%252Fa%2Bb
app: one decode        /items/a b  ->  routes /items/a%20b
```

- The **inner** value is `application/x-www-form-urlencoded` once: letters,
  digits and `-._~` stay, a space becomes `+`, everything else is `%XX` of
  its UTF-8 bytes. So a literal `+` in a path becomes `%2B` and survives.
- The **outer** layer encodes the whole referrer once more as the
  `referrer` query parameter, the same way.
- Play removes the outer layer; the app removes the inner one, **exactly
  once**. A path that really contains `%2F` (`/items/a%2Fb`) is sent as
  `%252F` inside and reaches the app intact.

## Test your builder against the shared vectors

[`test/vectors/referrer_vectors.json`](https://github.com/saimskywalker/flutter-imaji-install-attribution/blob/main/test/vectors/referrer_vectors.json)
holds rows of `campaign` + `path` → `referrer_as_play_returns_it`,
`play_url_referrer_param`, `play_store_url` and `expected_deep_link`, plus
`refused` rows a builder must reject. This package's tests and the Flutter
plugin's tests both read it, so the builder and the parser cannot drift
apart. A builder in any other language can pin the same file — fetch
`https://raw.githubusercontent.com/saimskywalker/flutter-imaji-install-attribution/<tag-or-commit>/test/vectors/referrer_vectors.json`
in its tests. A Python builder that passes every row:

```python
import json
from urllib.parse import quote_plus, urlencode

def append_path(campaign, path, key="utm_content"):
    if path is None:  # also for a target that is not public
        return campaign
    pair = quote_plus(key, safe="") + "=" + quote_plus(path, safe="")
    if campaign == "" or campaign.endswith("&"):
        return campaign + pair
    return campaign + "&" + pair

def play_store_url(package_name, referrer):
    query = {"id": package_name}
    if referrer:
        query["referrer"] = referrer
    return "https://play.google.com/store/apps/details?" + urlencode(query)

def test_vectors():
    doc = json.load(open("referrer_vectors.json", encoding="utf-8"))
    for row in doc["vectors"]:
        referrer = append_path(row["campaign"], row["path"], doc["key"])
        assert referrer == row["referrer_as_play_returns_it"], row["name"]
        assert play_store_url(doc["package_name"], referrer) == row["play_store_url"]
```

(The allowlist and duplicate-key checks are left out for brevity; the
`refused` rows test them.) In JavaScript neither built-in matches byte for
byte: `encodeURIComponent` leaves `!'()*` unescaped and writes a space as
`%20`, and `URLSearchParams` leaves `*` and escapes `~`. This one passes
every row:

```js
const encode = (s) =>
  encodeURIComponent(s)
    .replace(/[!'()*]/g, (c) => '%' + c.charCodeAt(0).toString(16).toUpperCase())
    .replace(/%20/g, '+');
```

## Migrating

- **From hand-built store URLs.** Replace string concatenation such as
  `'$campaign&utm_content=${Uri.encodeComponent(path)}'` or a second
  `Uri.encodeComponent` around the whole referrer with
  `appendPath` + `webFromReferrer`, then run the vectors in your tests. The
  usual findings: the path encoded twice (the app sees `%2Finvite…` and
  routes nothing), not encoded at all (works until a path has `&`, `=`, `%`
  or `+`), or a campaign that already carried `utm_content`.
- **From a hosted deferred-link SDK.** Link vendors built the store URL for
  you; when moving link generation in-house, this package is that part.
  Use the same `allow` list the app passes to `deepLink()`, keep the
  campaign string your marketing team configured, and send hidden or
  deleted targets as campaign-only links.
- **From the Flutter plugin's `PlayStoreUrl`.** The map form (`web`,
  `market`, `encodeReferrer`) is identical, so a server can switch to this
  package without changing a single emitted byte.

## License

MIT — see [LICENSE](LICENSE).
