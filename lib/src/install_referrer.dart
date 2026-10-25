import 'package:flutter/foundation.dart';

/// The Google Play install referrer, parsed.
///
/// Play returns the `referrer` parameter of the store URL with its outer
/// encoding removed, for example
/// `utm_source=newsletter&utm_content=%2Fitems%2F42`. [parameters] decodes
/// each value exactly once, so `utm_content` above is `/items/42`.
///
/// Decoding a second time is the classic bug: a path segment that really
/// contains an encoded slash (`/tags/a%2Fb`) would turn into `/tags/a/b`.
/// Nothing in this class decodes twice.
///
/// The parsing rule, exactly (`doc/decoding.md` in the repository, and the
/// language-neutral vectors in `test/vectors/deep_link_vectors.json`):
///
/// 1. Split [raw] on `&`. Skip empty pieces.
/// 2. Split each piece at its **first** `=`; a piece with no `=` is a key
///    with an empty value.
/// 3. Decode key and value **once**, per [decoding]: `form`
///    (`application/x-www-form-urlencoded`: `+` is a space, `%XX` is UTF-8)
///    by default, or `rfc3986` (`%XX` only; `+` stays `+`). A piece whose
///    escapes do not decode is kept as written.
/// 4. Drop an empty key. The first occurrence of a repeated key wins.
@immutable
class InstallReferrer {
  /// Parses [raw] as Play returned it, decoding each value once per
  /// [decoding].
  InstallReferrer(this.raw, {this.decoding = ReferrerDecoding.form})
    : parameters = _parse(raw, decoding);

  /// The referrer string exactly as Play returned it.
  final String raw;

  /// How [parameters] were decoded.
  final ReferrerDecoding decoding;

  /// The referrer's key/value pairs, each value decoded exactly once. The
  /// first occurrence of a repeated key wins. A bare token with no `=`
  /// (`abc123`) is kept as a key with an empty value.
  final Map<String, String> parameters;

  /// The same [raw] referrer, decoded per [decoding] instead.
  InstallReferrer withDecoding(ReferrerDecoding decoding) =>
      InstallReferrer(raw, decoding: decoding);

  /// The value Play uses for a UTM field nobody set.
  static const notSet = '(not set)';

  /// `true` when [value] is absent, empty, or Play's `(not set)`.
  static bool isNotSet(String? value) =>
      value == null || value.trim().isEmpty || value.trim() == notSet;

  /// The decoded value for [key], or `null` when it is absent.
  String? operator [](String key) => parameters[key];

  /// `utm_source`, or `null` when absent or `(not set)`.
  String? get utmSource => _utm('utm_source');

  /// `utm_medium`, or `null` when absent or `(not set)`.
  String? get utmMedium => _utm('utm_medium');

  /// `utm_campaign`, or `null` when absent or `(not set)`.
  String? get utmCampaign => _utm('utm_campaign');

  /// `utm_content`, or `null` when absent or `(not set)`.
  String? get utmContent => _utm('utm_content');

  /// `utm_term`, or `null` when absent or `(not set)`.
  String? get utmTerm => _utm('utm_term');

  String? _utm(String key) {
    final value = parameters[key];
    return isNotSet(value) ? null : value;
  }

  /// Whether this referrer carries no campaign at all.
  ///
  /// True for an empty referrer, for only `(not set)` / empty `utm_*`
  /// values, and for Play's default
  /// `utm_source=google-play&utm_medium=organic`. Any other key, or any
  /// set `utm_*` value, makes it attributed.
  bool get isOrganic {
    final meaningful = <String, String>{
      for (final entry in parameters.entries)
        if (!(entry.key.startsWith('utm_') && isNotSet(entry.value)))
          entry.key: entry.value,
    };
    if (meaningful.isEmpty) return true;
    return meaningful.length == 2 &&
        meaningful['utm_source'] == 'google-play' &&
        meaningful['utm_medium'] == 'organic';
  }

  /// The in-app path the user was trying to open before installing, taken
  /// from the parameter [key] (default `utm_content`), or `null`.
  ///
  /// Returns `null` unless the value is a path that starts with one of the
  /// [allow] prefixes. A prefix matches itself and anything below it:
  /// `/items` allows `/items` and `/items/42`, never `/itemsX`. This is the
  /// guard that stops a crafted referrer from routing into arbitrary screens.
  ///
  /// The value is used as decoded once by [parameters]; it is never decoded
  /// again. Absolute URLs are refused unless they are `https` and their host
  /// is listed in [hosts], in which case only the path, query and fragment
  /// are returned. Protocol-relative values (`//host/...`), backslashes,
  /// control characters and `.`/`..` segments are always refused, and so is
  /// any value with a malformed percent escape (`%`, `%ZZ`) or one that does
  /// not decode as UTF-8 (`%FF`, `%C3`, `%E2%82`).
  ///
  /// [deepLinkResult] says *why* a value was refused.
  ///
  /// **Never throws.** The referrer is input anyone can craft, so every
  /// value that is not a safe in-app path is `null`, not an exception.
  Uri? deepLink({
    String key = 'utm_content',
    required Iterable<String> allow,
    Iterable<String> hosts = const [],
  }) => deepLinkResult(key: key, allow: allow, hosts: hosts).uriOrNull;

  /// Like [deepLink], but a refusal carries its [DeepLinkRejection], so an
  /// app can log why an attributed install landed on the home screen.
  ///
  /// A value that was encoded once too often by the link builder
  /// (`%2Finvite%2Fabc123` after Play's decode) is reported as
  /// [DeepLinkRejection.looksDoubleEncoded] and is **never repaired**:
  /// decoding again would mask the builder bug and corrupt paths that
  /// really contain `%2F`. Never throws.
  DeepLinkResult deepLinkResult({
    String key = 'utm_content',
    required Iterable<String> allow,
    Iterable<String> hosts = const [],
  }) => resolveDeepLinkResult(parameters[key], allow: allow, hosts: hosts);

  /// The validation behind [deepLink], for a value you already extracted.
  ///
  /// **Never throws**; see [deepLink] for what is refused.
  static Uri? resolveDeepLink(
    String? value, {
    required Iterable<String> allow,
    Iterable<String> hosts = const [],
  }) => resolveDeepLinkResult(value, allow: allow, hosts: hosts).uriOrNull;

  /// The validation behind [deepLinkResult], for a value you already
  /// extracted. The checks run in this order, and the first that fails
  /// names the [DeepLinkRejection]. **Never throws.**
  static DeepLinkResult resolveDeepLinkResult(
    String? value, {
    required Iterable<String> allow,
    Iterable<String> hosts = const [],
  }) => _resolve(value, allow, hosts, detectDoubleEncoding: true);

  static DeepLinkResult _resolve(
    String? value,
    Iterable<String> allow,
    Iterable<String> hosts, {
    required bool detectDoubleEncoding,
  }) {
    DeepLinkResult reject(DeepLinkRejection reason) =>
        DeepLinkRejected(reason, value: value);

    if (value == null || isNotSet(value)) {
      return reject(DeepLinkRejection.absent);
    }
    final text = value.trim();
    if (text.contains(r'\')) return reject(DeepLinkRejection.unsafe);
    if (text.codeUnits.any((c) => c < 0x20 || c == 0x7f)) {
      return reject(DeepLinkRejection.unsafe);
    }
    // Every percent escape anywhere in the value (path, query, fragment)
    // must be well formed and decode as UTF-8. `Uri.decodeComponent` throws
    // `ArgumentError` for a malformed escape (`%`, `%ZZ`) but
    // `FormatException` for a well-formed one that is not UTF-8 (`%FF`), so
    // both are caught. Without this, `Uri.parse` would quietly turn a bare
    // `%` into `%25`, and a returned link with `%FF` in its query would
    // throw later, from the app's own `queryParameters`.
    final once = _decodeComponentOrNull(text);
    if (once == null) return reject(DeepLinkRejection.undecodable);
    if (text.startsWith('//')) return reject(DeepLinkRejection.unsafe);
    // `Uri.parse` removes dot segments (`/items/../admin` becomes `/admin`,
    // and so does `%2E%2E`), so they are looked for in the value as written.
    final end = text.indexOf(RegExp('[?#]'));
    for (final segment in (end < 0 ? text : text.substring(0, end)).split(
      '/',
    )) {
      final decoded = _decodeComponentOrNull(segment);
      if (decoded == '.' || decoded == '..') {
        return reject(DeepLinkRejection.unsafe);
      }
    }

    final Uri uri;
    try {
      uri = Uri.parse(text);
    } on FormatException {
      return reject(DeepLinkRejection.notAPath);
    }

    if (uri.hasScheme) {
      final scheme = uri.scheme.toLowerCase();
      if (scheme != 'https' && scheme != 'http') {
        return reject(DeepLinkRejection.notAPath);
      }
      final allowedHosts = {for (final h in hosts) h.toLowerCase()};
      final ok =
          scheme == 'https' &&
          uri.hasAuthority &&
          uri.userInfo.isEmpty &&
          !uri.hasPort &&
          allowedHosts.contains(uri.host.toLowerCase());
      if (!ok) return reject(DeepLinkRejection.hostNotAllowed);
    } else if (!text.startsWith('/')) {
      if (detectDoubleEncoding &&
          once != text &&
          _resolve(once, allow, hosts, detectDoubleEncoding: false)
              is DeepLinkFound) {
        return reject(DeepLinkRejection.looksDoubleEncoded);
      }
      return reject(DeepLinkRejection.notAPath);
    }

    final path = uri.path;
    if (!path.startsWith('/')) return reject(DeepLinkRejection.notAPath);
    if (path.startsWith('//')) return reject(DeepLinkRejection.unsafe);
    for (final segment in path.split('/')) {
      final decoded = _decodeComponentOrNull(segment);
      if (decoded == null) return reject(DeepLinkRejection.undecodable);
      if (decoded == '.' || decoded == '..') {
        return reject(DeepLinkRejection.unsafe);
      }
    }

    if (!allow.any((prefix) => _matchesPrefix(path, prefix))) {
      return reject(DeepLinkRejection.notAllowlisted);
    }

    return DeepLinkFound(
      Uri(
        path: path,
        query: uri.hasQuery ? uri.query : null,
        fragment: uri.hasFragment ? uri.fragment : null,
      ),
    );
  }

  /// `Uri.decodeComponent`, but `null` instead of a throw, and tolerant of
  /// unescaped non-ASCII text. `Uri.decodeComponent` refuses a raw `é`
  /// ("Illegal percent encoding"), while a value such as `/items/café` is a
  /// valid path that `Uri.parse` encodes, so non-ASCII runs are
  /// percent-encoded first and only the escapes are judged. A lone UTF-16
  /// surrogate is not text at all, and is refused: `Uri` would encode it
  /// into a link whose own `queryParameters` then throw.
  static String? _decodeComponentOrNull(String text) {
    if (_hasLoneSurrogate(text)) return null;
    try {
      final ascii = text.replaceAllMapped(
        _nonAscii,
        (match) => Uri.encodeComponent(match[0]!),
      );
      return Uri.decodeComponent(ascii);
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  }

  static bool _hasLoneSurrogate(String text) {
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        final next = i + 1 < text.length ? text.codeUnitAt(i + 1) : 0;
        if (next < 0xDC00 || next > 0xDFFF) return true;
        i++;
      } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
        return true;
      }
    }
    return false;
  }

  static final RegExp _nonAscii = RegExp(r'[^\x00-\x7F]+');

  static bool _matchesPrefix(String path, String prefix) {
    if (!prefix.startsWith('/')) return false;
    if (prefix == '/') return true;
    final base = prefix.endsWith('/')
        ? prefix.substring(0, prefix.length - 1)
        : prefix;
    return path == base || path.startsWith('$base/');
  }

  static Map<String, String> _parse(String raw, ReferrerDecoding decoding) {
    final result = <String, String>{};
    for (final pair in raw.split('&')) {
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      final key = _decodeOnce(eq < 0 ? pair : pair.substring(0, eq), decoding);
      final value = eq < 0 ? '' : _decodeOnce(pair.substring(eq + 1), decoding);
      if (key.isEmpty) continue;
      result.putIfAbsent(key, () => value);
    }
    return Map.unmodifiable(result);
  }

  /// One decode per [decoding]. A malformed escape (`%ZZ`) leaves the text
  /// as it was rather than throwing.
  static String _decodeOnce(String text, ReferrerDecoding decoding) {
    try {
      return switch (decoding) {
        ReferrerDecoding.form => Uri.decodeQueryComponent(text),
        ReferrerDecoding.rfc3986 => Uri.decodeComponent(text),
      };
    } on ArgumentError {
      return text;
    } on FormatException {
      return text;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is InstallReferrer &&
      other.raw == raw &&
      other.decoding == decoding;

  @override
  int get hashCode => Object.hash(raw, decoding);

  @override
  String toString() => 'InstallReferrer($raw)';
}

/// How [InstallReferrer] decodes each referrer value. Either way a value is
/// decoded exactly once.
enum ReferrerDecoding {
  /// `application/x-www-form-urlencoded`
  /// (<https://url.spec.whatwg.org/#application/x-www-form-urlencoded>):
  /// `+` is a space and `%XX` escapes are UTF-8. The default, and what
  /// [PlayStoreUrl] and every form encoder produce: they write a space as
  /// `+` and a `+` as `%2B`.
  form,

  /// RFC 3986 percent-decoding
  /// (<https://www.rfc-editor.org/rfc/rfc3986#section-2.1>): `%XX` only, so a
  /// literal `+` stays `+`. Matches code that decoded with
  /// `Uri.decodeComponent`. The two only disagree on a literal `+`, which a
  /// builder emits when it did not encode the value at all.
  rfc3986,
}

/// Why [InstallReferrer.deepLinkResult] found no link. Checked in this
/// order; the first that applies is reported.
enum DeepLinkRejection {
  /// The key is missing, empty, blank or Play's `(not set)`.
  absent,

  /// A backslash, a control character, a protocol-relative value
  /// (`//host/...`), a path starting with `//`, or a `.`/`..` segment
  /// (also when encoded, `%2e%2e`).
  unsafe,

  /// A malformed percent escape (`%`, `%ZZ`) or one that is not UTF-8
  /// (`%FF`, `%C3`).
  undecodable,

  /// Not an absolute path: relative (`items/42`), a non-web scheme
  /// (`intent:`, `mailto:`), or an `https` URL with no path.
  notAPath,

  /// An absolute `http`/`https` URL that is not `https` on a host listed in
  /// `hosts` with no port and no user info.
  hostNotAllowed,

  /// Not a path as it stands, but decoding it **once more** would give an
  /// allowlisted link: the link builder encoded the value twice. Reported,
  /// never repaired.
  looksDoubleEncoded,

  /// A safe path, but under none of the `allow` prefixes.
  notAllowlisted,
}

/// The answer of [InstallReferrer.deepLinkResult]: [DeepLinkFound] or
/// [DeepLinkRejected].
@immutable
sealed class DeepLinkResult {
  const DeepLinkResult();

  /// The link, or `null` when rejected.
  Uri? get uriOrNull;
}

/// A link that passed every check.
final class DeepLinkFound extends DeepLinkResult {
  /// Creates a found link.
  const DeepLinkFound(this.uri);

  /// The relative link to route: path, query and fragment.
  final Uri uri;

  @override
  Uri get uriOrNull => uri;

  @override
  bool operator ==(Object other) => other is DeepLinkFound && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;

  @override
  String toString() => 'DeepLinkFound($uri)';
}

/// No link, and why.
final class DeepLinkRejected extends DeepLinkResult {
  /// Creates a rejection.
  const DeepLinkRejected(this.reason, {this.value});

  /// Why no link was found.
  final DeepLinkRejection reason;

  /// The value that was checked, as decoded once (`null` when absent). It
  /// is attacker-controlled: log it with care.
  final String? value;

  @override
  Null get uriOrNull => null;

  @override
  bool operator ==(Object other) =>
      other is DeepLinkRejected &&
      other.reason == reason &&
      other.value == value;

  @override
  int get hashCode => Object.hash(reason, value);

  @override
  String toString() => 'DeepLinkRejected(${reason.name})';
}
