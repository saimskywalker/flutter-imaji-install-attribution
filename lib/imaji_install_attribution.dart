/// Flutter install attribution and deferred deep links.
///
/// Reads the Google Play Install Referrer on Android and the Apple
/// AdServices attribution token on iOS, and returns one typed
/// [InstallAttributionResult]: [Attributed], [Organic] or
/// [Unavailable] — never an exception.
///
/// ```dart
/// import 'package:imaji_install_attribution/imaji_install_attribution.dart';
///
/// final result = await InstallAttribution.read();
/// if (result case Attributed(:final referrer?)) {
///   final link = referrer.deepLink(allow: ['/items/']);
/// }
/// ```
library;

export 'src/install_attribution.dart';
export 'src/install_facts.dart';
export 'src/install_referrer.dart';
export 'src/install_source.dart';
export 'src/method_channel.dart' show MethodChannelInstallAttribution;
export 'src/platform_interface.dart';
export 'src/play_store_url.dart';
export 'src/result.dart';
