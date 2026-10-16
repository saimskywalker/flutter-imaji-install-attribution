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
@immutable
class InstallReferrer {
  /// Parses [raw] as Play returned it.
  InstallReferrer(this.raw) : parameters = _parse(raw);

  /// The referrer string exactly as Play returned it.
  final String raw;

  /// The referrer's key/value pairs, each value decoded exactly once. The
  /// first occurrence of a repeated key wins. A bare token with no `=`
  /// (`abc123`) is kept as a key with an empty value.
  final Map<String, String> parameters;

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
  /// from the parameter [key] (default `utm_content`).
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
  /// **Never throws.** The referrer is input anyone can craft, so every
  /// value that is not a safe in-app path is `null`, not an exception.
  Uri? deepLink({
    String key = 'utm_content',
    required Iterable<String> allow,
    Iterable<String> hosts = const [],
  }) => resolveDeepLink(parameters[key], allow: allow, hosts: hosts);

  /// The validation behind [deepLink], for a value you already extracted.
  ///
  /// **Never throws**; see [deepLink] for what is refused.
  static Uri? resolveDeepLink(
    String? value, {
    required Iterable<String> allow,
    Iterable<String> hosts = const [],
  }) {
    if (value == null) return null;
    final text = value.trim();
    if (text.isEmpty || text.contains(r'\')) return null;
    if (text.codeUnits.any((c) => c < 0x20 || c == 0x7f)) return null;
    // Every percent escape anywhere in the value (path, query, fragment)
    // must be well formed and decode as UTF-8. `Uri.decodeComponent` throws
    // `ArgumentError` for a malformed escape (`%`, `%ZZ`) but
    // `FormatException` for a well-formed one that is not UTF-8 (`%FF`), so
    // both are caught. Without this, `Uri.parse` would quietly turn a bare
    // `%` into `%25`, and a returned link with `%FF` in its query would
    // throw later, from the app's own `queryParameters`.
    if (!_decodesCleanly(text)) return null;

    final Uri uri;
    try {
      uri = Uri.parse(text);
    } on FormatException {
      return null;
    }

    if (uri.hasScheme || text.startsWith('//')) {
      final allowedHosts = {for (final h in hosts) h.toLowerCase()};
      final ok =
          uri.scheme == 'https' &&
          uri.hasAuthority &&
          uri.userInfo.isEmpty &&
          !uri.hasPort &&
          allowedHosts.contains(uri.host.toLowerCase());
      if (!ok) return null;
    } else if (!text.startsWith('/')) {
      return null;
    }

    final path = uri.path;
    if (!path.startsWith('/') || path.startsWith('//')) return null;
    for (final segment in path.split('/')) {
      final String decoded;
      try {
        decoded = Uri.decodeComponent(segment);
      } on ArgumentError {
        return null;
      } on FormatException {
        return null;
      }
      if (decoded == '.' || decoded == '..') return null;
    }

    if (!allow.any((prefix) => _matchesPrefix(path, prefix))) return null;

    return Uri(
      path: path,
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.hasFragment ? uri.fragment : null,
    );
  }

  static bool _decodesCleanly(String text) {
    try {
      Uri.decodeComponent(text);
      return true;
    } on ArgumentError {
      return false;
    } on FormatException {
      return false;
    }
  }

  static bool _matchesPrefix(String path, String prefix) {
    if (!prefix.startsWith('/')) return false;
    if (prefix == '/') return true;
    final base = prefix.endsWith('/')
        ? prefix.substring(0, prefix.length - 1)
        : prefix;
    return path == base || path.startsWith('$base/');
  }

  static Map<String, String> _parse(String raw) {
    final result = <String, String>{};
    for (final pair in raw.split('&')) {
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      final key = _decodeOnce(eq < 0 ? pair : pair.substring(0, eq));
      final value = eq < 0 ? '' : _decodeOnce(pair.substring(eq + 1));
      if (key.isEmpty) continue;
      result.putIfAbsent(key, () => value);
    }
    return Map.unmodifiable(result);
  }

  /// One `application/x-www-form-urlencoded` decode. A malformed escape
  /// (`%ZZ`) leaves the text as it was rather than throwing.
  static String _decodeOnce(String text) {
    try {
      return Uri.decodeQueryComponent(text);
    } on ArgumentError {
      return text;
    } on FormatException {
      return text;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is InstallReferrer && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;

  @override
  String toString() => 'InstallReferrer($raw)';
}
