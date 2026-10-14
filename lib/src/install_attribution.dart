import 'dart:async';

import 'package:flutter/foundation.dart';

import 'install_source.dart';
import 'method_channel.dart';
import 'platform_interface.dart';
import 'result.dart';

/// Where did this install come from?
///
/// One call on both platforms: the Google Play Install Referrer on Android,
/// the Apple AdServices attribution token on iOS.
///
/// ```dart
/// final result = await InstallAttribution.read();
/// switch (result) {
///   case Attributed(:final referrer?):
///     final link = referrer.deepLink(allow: ['/items/']);
///     if (link != null) router.go(link.toString());
///   case Attributed():
///     // iOS: send `result.token` to your server.
///   case Organic():
///   case Unavailable():
/// }
/// ```
abstract final class InstallAttribution {
  /// The timeout [read] uses when none is given.
  static const Duration defaultTimeout = Duration(seconds: 10);

  /// Extra time the Dart side waits beyond the native timeout before it gives
  /// up on a reply, so a lost platform message can never hang [read].
  static const Duration _replyGrace = Duration(seconds: 2);

  static Future<InstallAttributionResult>? _inFlight;
  static InstallAttributionResult? _override;

  /// Reads the install attribution. **Never throws.**
  ///
  /// Every failure becomes [Unavailable] with a typed [UnavailableReason].
  /// On Android the Play Store Binder call runs off the platform thread and
  /// the read ends as [UnavailableReason.timeout] after [timeout].
  ///
  /// The referrer does not change after install, so this is safe to call on
  /// every launch; concurrent calls share one read.
  static Future<InstallAttributionResult> read({
    Duration timeout = defaultTimeout,
  }) {
    final override = _override;
    if (override != null) return Future.value(override);
    return _inFlight ??= _read(timeout).whenComplete(() => _inFlight = null);
  }

  static Future<InstallAttributionResult> _read(Duration timeout) async {
    final effective = timeout <= Duration.zero ? defaultTimeout : timeout;
    try {
      return await ImajiInstallAttributionPlatform.instance
          .read(timeout: effective)
          // Re-type: an implementation may hand back a Future of a subtype
          // (`Future<Attributed>`), whose `timeout` would reject our
          // `Unavailable` fallback.
          .then<InstallAttributionResult>((result) => result)
          .timeout(
            effective + _replyGrace,
            onTimeout: () => const Unavailable(
              UnavailableReason.timeout,
              message: 'The platform did not reply in time.',
            ),
          );
    } on Object catch (error) {
      return Unavailable(
        UnavailableReason.internalError,
        message: error.toString(),
      );
    }
  }

  /// Which package installed the app (Android), or `null` when unknown or
  /// on iOS. Never throws.
  static Future<InstallSource?> installSource() async {
    try {
      return await ImajiInstallAttributionPlatform.instance.installSource();
    } on Object {
      return null;
    }
  }

  /// Like [read], but returns `null` once [markHandled] has been called on
  /// this install.
  ///
  /// Nothing is marked automatically: call [markHandled] only after the
  /// attribution was acted on (the deep link routed, the event sent). A
  /// crash between reading and routing then leaves it unhandled, and the next
  /// launch gets another chance.
  ///
  /// The marker is a tiny file excluded from backups (`noBackupFilesDir` on
  /// Android, an excluded file in Application Support on iOS), so an
  /// uninstall + reinstall starts unhandled again — which matches Play, since
  /// a reinstall from a new link carries a new referrer.
  static Future<InstallAttributionResult?> readOnce({
    Duration timeout = defaultTimeout,
  }) async {
    if (await isHandled()) return null;
    return read(timeout: timeout);
  }

  /// Whether [markHandled] has been called on this install. Never throws;
  /// an unreadable marker counts as not handled.
  static Future<bool> isHandled() async {
    try {
      return await ImajiInstallAttributionPlatform.instance.isHandled();
    } on Object {
      return false;
    }
  }

  /// Records that the attribution has been acted on, so [readOnce] returns
  /// `null` from now on. Returns `false` if the marker could not be written.
  static Future<bool> markHandled() async {
    try {
      return await ImajiInstallAttributionPlatform.instance.markHandled();
    } on Object {
      return false;
    }
  }

  /// Removes the marker written by [markHandled]. Meant for tests and debug
  /// menus.
  static Future<bool> clearHandled() async {
    try {
      return await ImajiInstallAttributionPlatform.instance.clearHandled();
    } on Object {
      return false;
    }
  }

  /// Makes [read] return a fake result, so routing can be exercised on any
  /// emulator or simulator. **Debug builds only.**
  ///
  /// Pass a [referrer] string exactly as Play would return it (for example
  /// `utm_source=newsletter&utm_content=%2Fitems%2F42`); it is classified by
  /// the same rule as a real one. Or pass a ready-made [result], for example
  /// `Unavailable(UnavailableReason.timeout)`.
  ///
  /// The body runs inside an `assert`, so in profile and release builds this
  /// does nothing and [read] always asks the platform: a forgotten call can
  /// never ship a fake attribution.
  static void debugOverride({
    String? referrer,
    DateTime? clickedAt,
    DateTime? installBeganAt,
    InstallAttributionResult? result,
  }) {
    assert(() {
      _override =
          result ??
          MethodChannelInstallAttribution.classifyReferrer(
            referrer ?? '',
            clickedAt: clickedAt,
            installBeganAt: installBeganAt,
          );
      return true;
    }());
  }

  /// Removes a [debugOverride].
  static void debugClearOverride() {
    _override = null;
  }

  /// Whether a [debugOverride] is active.
  @visibleForTesting
  static bool get debugHasOverride => _override != null;
}
