/// Google Play install-referrer strings and store links for deferred deep
/// links, built on a server, in pure Dart.
///
/// The app half of the contract is `InstallReferrer` in the Flutter plugin
/// `imaji_install_attribution`: it decodes the referrer value exactly once
/// and routes only allowlisted paths. This package is the builder half, with
/// no Flutter dependency, so a `shelf` server, a Cloud Run job or a CLI can
/// use it.
///
/// ```dart
/// import 'package:imaji_referrer_builder/imaji_referrer_builder.dart';
///
/// final referrer = PlayStoreUrl.appendPath(
///   'utm_source=share&utm_medium=social&utm_campaign=spring',
///   '/invite/abc123',
///   allow: ['/invite/', '/items/'],
/// );
/// // utm_source=share&utm_medium=social&utm_campaign=spring&utm_content=%2Finvite%2Fabc123
///
/// final url = PlayStoreUrl.webFromReferrer(
///   packageName: 'com.example.app',
///   referrer: referrer,
/// );
/// ```
library;

export 'src/path_check.dart' show PathRefusal;
export 'src/play_store_url.dart';
