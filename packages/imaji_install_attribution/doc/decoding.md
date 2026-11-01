# The decoding rule

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

Decoding a referrer value twice corrupts paths that really contain `%2F`.
Nothing in `InstallReferrer` decodes twice.

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

## Test your link builder against the vectors

[`test/vectors/deep_link_vectors.json`](../test/vectors/deep_link_vectors.json)
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
