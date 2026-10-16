import 'dart:async';

import 'package:flutter/foundation.dart';

import 'install_facts.dart';
import 'install_source.dart';
import 'method_channel.dart';
import 'platform_interface.dart';
import 'result.dart';

/// Why [InstallAttribution.readOnce] returned `null`.
enum ReadOnceSkip {
  /// The install was already handled ([InstallAttribution.markHandled]).
  handled,

  /// The install existed before the plugin did: the app was updated since it
  /// was installed, and the plugin first ran after that update
  /// (`treatUpgradesAsHandled`). Marked handled.
  adoptedInUpdate,

  /// The Play click is older than `maxClickAge`. Marked handled.
  staleClick,

  /// The app's `pastInstallFlow` check answered `true`. Marked handled.
  pastInstallFlow,

  /// The app's `pastInstallFlow` check threw. Nothing was marked; the next
  /// launch asks again.
  pastInstallFlowFailed,
}

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

  /// Like [read], but for acting on the attribution **once per install**:
  /// returns `null` once the install is handled, and for an install whose
  /// attribution should not be acted on any more.
  ///
  /// Nothing is marked automatically when a result is returned: call
  /// [markHandled] only after the attribution was acted on (the deep link
  /// routed, the event sent). A crash between reading and routing then
  /// leaves it unhandled, and the next launch gets another chance.
  ///
  /// The marker is a tiny file excluded from backups (`noBackupFilesDir` on
  /// Android, an excluded file in Application Support on iOS), so an
  /// uninstall + reinstall starts unhandled again — which matches Play, since
  /// a reinstall from a new link carries a new referrer.
  ///
  /// Google's guidance is to act on the referrer only on the first execution
  /// after install. Three options make that the default rather than
  /// something every app re-implements. Each one that applies **marks the
  /// install handled and returns `null`**, with the reason in
  /// [lastSkipReason]; a suppressed referrer is silent — nothing is
  /// returned, so nothing can be routed or shown about it.
  ///
  /// - [treatUpgradesAsHandled] (default `true`, Android only): an install
  ///   that existed before the plugin did — the app was updated since it was
  ///   installed, and this plugin first ran after that update — is handled.
  ///   This is what stops an app that adopts the plugin in an update from
  ///   routing every existing user to the link they installed from weeks
  ///   ago; Play keeps returning that referrer for 90 days. See
  ///   [InstallFacts.predatesPlugin] for the exact rule. An app that already
  ///   shipped its own referrer handling should also call
  ///   [adoptExistingState] first. The check needs no Play Store call.
  /// - [maxClickAge] (default `null`, no limit): a Play referrer whose click
  ///   is older than this is handled. Play attributes installs to clicks up
  ///   to 90 days old, while a deferred link usually only makes sense within
  ///   the app's own window (an invite, an onboarding offer); pick that
  ///   window per app. The click time is Play's server clock
  ///   ([Attributed.clickedAtServer]) when reported, else the device clock
  ///   ([Attributed.clickedAt]); a referrer with no click time is never
  ///   stale. No effect on iOS, whose token carries no click time.
  /// - [pastInstallFlow] (default `null`): the app's own "this user is past
  ///   the install flow" check, asked before Play is. When it answers `true`
  ///   the install is handled without a read. Make it require **both**
  ///   "signed in" and "the first run already completed on this device", and
  ///   keep the first-run flag out of backups — see the README recipe. A
  ///   check that throws counts as "don't know": `null` is returned, nothing
  ///   is marked, and the next launch asks again.
  ///
  /// Never throws.
  static Future<InstallAttributionResult?> readOnce({
    Duration timeout = defaultTimeout,
    bool treatUpgradesAsHandled = true,
    Duration? maxClickAge,
    FutureOr<bool> Function()? pastInstallFlow,
  }) async {
    if (await isHandled()) return _skip(ReadOnceSkip.handled);

    if (pastInstallFlow != null) {
      final bool past;
      try {
        past = await pastInstallFlow();
      } on Object {
        return _skip(ReadOnceSkip.pastInstallFlowFailed);
      }
      if (past) return _suppress(ReadOnceSkip.pastInstallFlow);
    }

    if (treatUpgradesAsHandled) {
      final facts = await installFacts();
      if (facts != null && facts.predatesPlugin) {
        return _suppress(ReadOnceSkip.adoptedInUpdate);
      }
    }

    final result = await read(timeout: timeout);

    if (maxClickAge != null && result is Attributed) {
      final clickedAt = result.clickedAtServer ?? result.clickedAt;
      if (clickedAt != null && clock().difference(clickedAt) > maxClickAge) {
        return _suppress(ReadOnceSkip.staleClick);
      }
    }

    _lastSkipReason = null;
    return result;
  }

  static ReadOnceSkip? _lastSkipReason;

  /// Why the latest [readOnce] in this process returned `null`, or `null`
  /// when it returned a result (or has not run). For logs and analytics.
  static ReadOnceSkip? get lastSkipReason => _lastSkipReason;

  static Null _skip(ReadOnceSkip reason) {
    _lastSkipReason = reason;
    return null;
  }

  static Future<Null> _suppress(ReadOnceSkip reason) async {
    await markHandled();
    return _skip(reason);
  }

  /// The clock [readOnce] measures [Attributed.clickedAt] against.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// One-time migration from referrer handling the app shipped before this
  /// plugin. Call it before the first [readOnce].
  ///
  /// When [alreadyHandled] is `true` — the app's old code already acted on
  /// this install's referrer, or stored its own "done" flag — the install is
  /// marked handled. `false` changes nothing. Idempotent and cheap: safe to
  /// call on every launch with the legacy flag, for example
  /// `adoptExistingState(alreadyHandled: prefs.getBool('referrer_done') ??
  /// false)`.
  ///
  /// Returns whether the install is marked handled afterwards. Never throws.
  static Future<bool> adoptExistingState({required bool alreadyHandled}) async {
    if (await isHandled()) return true;
    if (!alreadyHandled) return false;
    return markHandled();
  }

  /// What the device knows about this install (Android), or `null` on iOS
  /// and when it could not be read. Never throws.
  static Future<InstallFacts?> installFacts() async {
    try {
      return await ImajiInstallAttributionPlatform.instance.installFacts();
    } on Object {
      return null;
    }
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
