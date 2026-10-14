import 'package:flutter/foundation.dart';

import 'install_referrer.dart';
import 'install_source.dart';

/// Which attribution channel produced an [Attributed] result.
enum AttributionSource {
  /// The Google Play Install Referrer (Android).
  googlePlay,

  /// The Apple AdServices attribution token (iOS 14.3+).
  ///
  /// The token only says "an attribution record may exist". Resolving it
  /// into a campaign means a POST from your server to Apple's attribution
  /// API, which this plugin deliberately does not do.
  appleAds,
}

/// Why no attribution could be read. Every failure the platforms can produce
/// maps to exactly one of these; nothing is thrown.
enum UnavailableReason {
  /// The platform has no attribution API: web, desktop, an iOS simulator,
  /// iOS older than 14.3, or a platform with no plugin registered.
  notSupported,

  /// The read did not finish within the `timeout` given to
  /// [InstallAttribution.read]. The connection was closed.
  timeout,

  /// The Google Play Store is not installed (AOSP, Huawei without GMS,
  /// Amazon Fire, many emulator images).
  playStoreMissing,

  /// The installed Play Store app is too old to offer the Install Referrer
  /// API (`FEATURE_NOT_SUPPORTED`). Common on emulators.
  featureNotSupported,

  /// The Play Store referrer service could not be reached
  /// (`SERVICE_UNAVAILABLE`), or it failed with a `RemoteException`.
  serviceUnavailable,

  /// The service connection was lost and one reconnect did not help
  /// (`SERVICE_DISCONNECTED`).
  serviceDisconnected,

  /// The Play Store process died during the Binder call
  /// (`DeadObjectException`).
  deadService,

  /// The app may not bind to the referrer service (`PERMISSION_ERROR`,
  /// "App is not allowed to bind to the Service"). Usually a manifest merge
  /// that removed `BIND_GET_INSTALL_REFERRER_SERVICE`.
  permissionError,

  /// The Install Referrer library reported `DEVELOPER_ERROR`.
  developerError,

  /// Play answered `OK` but its referrer details had no data bundle. Reading
  /// it would have thrown a fatal `NullPointerException`.
  nullDetails,

  /// Play answered with a response code this version does not know.
  unknownResponse,

  /// AdServices could not reach Apple to generate a token
  /// (`AAAttributionErrorCode.networkError`). Worth retrying later.
  networkError,

  /// Anything else: an unexpected exception inside the platform code, or a
  /// reply this version cannot decode. [Unavailable.message] has details.
  internalError;

  /// Parses a reason name sent by the platform side. Unknown names become
  /// [internalError] rather than throwing.
  static UnavailableReason parse(Object? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return internalError;
  }
}

/// The answer to "where did this install come from?".
///
/// Switch over it exhaustively:
///
/// ```dart
/// switch (await InstallAttribution.read()) {
///   case Attributed(:final referrer):
///     // a campaign, a shared link, an Apple Ads token
///   case Organic():
///     // installed with no campaign
///   case Unavailable(:final reason):
///     // nothing could be read; `reason` says why
/// }
/// ```
@immutable
sealed class InstallAttributionResult {
  const InstallAttributionResult({this.installSource});

  /// Which package installed the app (Android only; `null` on iOS and when
  /// it could not be read).
  final InstallSource? installSource;
}

/// The install carries attribution: a Play referrer with a campaign or
/// custom payload, or an Apple AdServices token.
final class Attributed extends InstallAttributionResult {
  /// Creates an attributed result.
  const Attributed({
    required this.source,
    this.referrer,
    this.token,
    this.clickedAt,
    this.installBeganAt,
    this.clickedAtServer,
    this.installBeganAtServer,
    this.installVersion,
    super.installSource,
  });

  /// Which channel produced this result.
  final AttributionSource source;

  /// The parsed Play referrer ([AttributionSource.googlePlay] only).
  final InstallReferrer? referrer;

  /// The AdServices attribution token ([AttributionSource.appleAds] only).
  /// Valid for 24 hours; send it to your server to resolve it.
  final String? token;

  /// When the user tapped the Play Store link, by the device clock.
  final DateTime? clickedAt;

  /// When the install began, by the device clock.
  final DateTime? installBeganAt;

  /// [clickedAt] by Play's server clock (immune to a wrong device clock).
  final DateTime? clickedAtServer;

  /// [installBeganAt] by Play's server clock.
  final DateTime? installBeganAtServer;

  /// The app version that was first installed, when Play reports it.
  final String? installVersion;

  @override
  String toString() =>
      'Attributed(source: ${source.name}, referrer: ${referrer?.raw}, '
      'token: ${token == null ? null : '<${token!.length} chars>'}, '
      'clickedAt: $clickedAt)';
}

/// The install has no campaign: Play reported the default
/// `utm_source=google-play&utm_medium=organic`, an empty referrer, or only
/// `(not set)` values.
final class Organic extends InstallAttributionResult {
  /// Creates an organic result.
  const Organic({this.referrer, this.installBeganAt, super.installSource});

  /// What Play returned, kept so callers can log or inspect it.
  final InstallReferrer? referrer;

  /// When the install began, by the device clock, if known.
  final DateTime? installBeganAt;

  @override
  String toString() => 'Organic(referrer: ${referrer?.raw})';
}

/// Nothing could be read. [reason] says why; [message] carries the
/// platform's own words, for logs.
final class Unavailable extends InstallAttributionResult {
  /// Creates an unavailable result.
  const Unavailable(this.reason, {this.message, super.installSource});

  /// Why nothing could be read.
  final UnavailableReason reason;

  /// A human-readable detail for logs. Not stable; do not branch on it.
  final String? message;

  @override
  String toString() => 'Unavailable(${reason.name}: $message)';
}
