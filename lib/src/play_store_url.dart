/// Builds Google Play links that carry an install referrer.
///
/// The referrer is a query string (`utm_source=x&utm_content=/items/42`)
/// placed as the value of the store URL's `referrer` parameter. Each inner
/// value is form-encoded once to build that query string, and the whole
/// string is encoded once more as the outer parameter — no more. Play strips
/// the outer layer; [InstallReferrer] strips the inner one. Hand-building
/// these URLs with an extra `Uri.encodeComponent` is how paths come back as
/// `%2Fitems%2F42`.
abstract final class PlayStoreUrl {
  /// An `https://play.google.com/store/apps/details` link for
  /// [packageName] whose referrer is [referrer].
  static Uri web({
    required String packageName,
    required Map<String, String> referrer,
  }) => Uri.https('play.google.com', '/store/apps/details', {
    'id': packageName,
    if (referrer.isNotEmpty) 'referrer': encodeReferrer(referrer),
  });

  /// A `market://details` link, which opens the Play Store app directly.
  static Uri market({
    required String packageName,
    required Map<String, String> referrer,
  }) => Uri(
    scheme: 'market',
    host: 'details',
    queryParameters: {
      'id': packageName,
      if (referrer.isNotEmpty) 'referrer': encodeReferrer(referrer),
    },
  );

  /// The referrer query string itself, with each value encoded once. This is
  /// what Play will hand back to the installed app.
  static String encodeReferrer(Map<String, String> referrer) =>
      Uri(queryParameters: referrer).query;
}
