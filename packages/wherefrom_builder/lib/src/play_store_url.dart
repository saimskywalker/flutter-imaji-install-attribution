import 'path_check.dart';

/// Builds Google Play install-referrer strings and store links.
///
/// The referrer is a query string (`utm_source=x&utm_content=%2Finvite%2Fabc`)
/// placed as the value of the store URL's `referrer` parameter. Each inner
/// value is form-encoded once to build that query string, and the whole
/// string is encoded once more as the outer parameter — no more. Play strips
/// the outer layer; the app (`InstallReferrer` in
/// `imaji_install_attribution`) strips the inner one, exactly once.
///
/// [web], [market] and [encodeReferrer] behave exactly like the class of
/// the same name in `imaji_install_attribution`. [appendPath],
/// [webFromReferrer], [marketFromReferrer], [checkPath] and
/// [expectedDeepLink] are what a server needs on top.
abstract final class PlayStoreUrl {
  /// The referrer key the app reads the deep link from by default, the same
  /// default as `InstallReferrer.deepLink(key: …)`.
  static const defaultKey = 'utm_content';

  /// Appends [path] to the configured [campaign] string as one more
  /// `key=value` pair, the value encoded exactly once.
  ///
  /// [campaign] is a referrer query string as whoever runs campaigns
  /// configured it, for example
  /// `utm_source=share&utm_medium=social&utm_campaign=spring`. It is kept
  /// byte for byte — never parsed and re-encoded — so store-console
  /// campaign reporting is unaffected. It may be empty.
  ///
  /// - [path] `null`, or [targetIsPublic] `false`: [campaign] is returned
  ///   unchanged. A link to something deleted, private or hidden must not
  ///   name it: the referrer is visible in the URL and Play keeps it for 90
  ///   days.
  /// - Empty [campaign]: the result is just `utm_content=%2Finvite%2Fabc123`.
  ///
  /// Throws an [ArgumentError] (a server bug should fail in its tests) when
  /// - [path] is one the app would not route with the same [allow] and
  ///   [hosts] — see [checkPath] for the reason;
  /// - [campaign] already holds [key]: the app keeps the *first* occurrence
  ///   of a repeated key, so the path would be lost;
  /// - [campaign] starts with `?` (the app would read the first key as
  ///   `?utm_source`);
  /// - [key] is empty.
  ///
  /// The [campaign] checks run even when no path is appended, so a
  /// misconfigured campaign fails in every test, not only the ones with a
  /// path.
  static String appendPath(
    String campaign,
    String? path, {
    required Iterable<String> allow,
    Iterable<String> hosts = const [],
    String key = defaultKey,
    bool targetIsPublic = true,
  }) {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'must not be empty');
    }
    _checkCampaign(campaign, key);
    if (path == null || !targetIsPublic) return campaign;

    final refusal = checkPath(path, allow: allow, hosts: hosts);
    if (refusal != null) {
      throw ArgumentError.value(
        path,
        'path',
        'the app would not route it (${refusal.name}); '
            'allow: ${allow.toList()}, hosts: ${hosts.toList()}',
      );
    }

    final pair = Uri(queryParameters: {key: path}).query;
    if (campaign.isEmpty || campaign.endsWith('&')) return '$campaign$pair';
    return '$campaign&$pair';
  }

  /// Why the app would not route [path] with this [allow] list and these
  /// [hosts], or `null` when it would.
  ///
  /// The rules are those of `InstallReferrer.deepLink(allow: …, hosts: …)`:
  /// a path starting with `/` (or an `https` URL on one of [hosts], without
  /// port or user info), equal to or below one of the [allow] prefixes
  /// (`/items` allows `/items` and `/items/42`, never `/itemsX`), with no
  /// `//` start, no `.`/`..` segment, no backslash and no control character.
  /// The builder is stricter in two places — see [PathRefusal]: it also
  /// refuses leading or trailing whitespace, and a dot segment that the URI
  /// parser would silently remove (`/items/../admin` reads as `/admin`).
  static PathRefusal? checkPath(
    String path, {
    required Iterable<String> allow,
    Iterable<String> hosts = const [],
  }) => resolvePath(path, allow: allow, hosts: hosts).refusal;

  /// The deep link the app will route after it reads a referrer built from
  /// [path], or `null` when [checkPath] refuses it.
  ///
  /// Mostly the path itself; the app normalises it as a URI, so
  /// `/items/a b` becomes `/items/a%20b` and `https://example.com/items/5`
  /// (with `example.com` in [hosts]) becomes `/items/5`. Useful in a
  /// server's tests to assert what the app will open.
  static Uri? expectedDeepLink(
    String path, {
    required Iterable<String> allow,
    Iterable<String> hosts = const [],
  }) => resolvePath(path, allow: allow, hosts: hosts).link;

  /// An `https://play.google.com/store/apps/details` link for
  /// [packageName] carrying [referrer] — a string from [appendPath] or
  /// [encodeReferrer] — encoded once as the `referrer` parameter. An empty
  /// [referrer] adds no parameter.
  static Uri webFromReferrer({
    required String packageName,
    required String referrer,
  }) => Uri.https('play.google.com', '/store/apps/details', {
    'id': packageName,
    if (referrer.isNotEmpty) 'referrer': referrer,
  });

  /// A `market://details` link, which opens the Play Store app directly,
  /// carrying the same parameter as [webFromReferrer].
  static Uri marketFromReferrer({
    required String packageName,
    required String referrer,
  }) => Uri(
    scheme: 'market',
    host: 'details',
    queryParameters: {
      'id': packageName,
      if (referrer.isNotEmpty) 'referrer': referrer,
    },
  );

  /// An `https://play.google.com/store/apps/details` link for
  /// [packageName] whose referrer is built from the [referrer] map.
  static Uri web({
    required String packageName,
    required Map<String, String> referrer,
  }) => webFromReferrer(
    packageName: packageName,
    referrer: encodeReferrer(referrer),
  );

  /// A `market://details` link whose referrer is built from the [referrer]
  /// map.
  static Uri market({
    required String packageName,
    required Map<String, String> referrer,
  }) => marketFromReferrer(
    packageName: packageName,
    referrer: encodeReferrer(referrer),
  );

  /// The referrer query string for a map, with each key and value encoded
  /// once. This is what Play will hand back to the installed app. It does
  /// not validate a deep-link path; use [appendPath] for that.
  static String encodeReferrer(Map<String, String> referrer) =>
      Uri(queryParameters: referrer).query;

  static void _checkCampaign(String campaign, String key) {
    if (campaign.startsWith('?')) {
      throw ArgumentError.value(
        campaign,
        'campaign',
        "must be a referrer query string without the leading '?'",
      );
    }
    for (final pair in campaign.split('&')) {
      if (pair.isEmpty) continue;
      final eq = pair.indexOf('=');
      if (_decodeOnce(eq < 0 ? pair : pair.substring(0, eq)) == key) {
        throw ArgumentError.value(
          campaign,
          'campaign',
          'already holds "$key"; the app keeps the first occurrence of a '
              'repeated key, so the appended path would be lost',
        );
      }
    }
  }

  /// One `application/x-www-form-urlencoded` decode, the app's rule for
  /// keys and values. A malformed escape leaves the text as it was.
  static String _decodeOnce(String text) {
    try {
      return Uri.decodeQueryComponent(text);
    } on ArgumentError {
      return text;
    } on FormatException {
      return text;
    }
  }
}
