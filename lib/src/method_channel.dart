import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'install_facts.dart';
import 'install_referrer.dart';
import 'install_source.dart';
import 'platform_interface.dart';
import 'result.dart';

/// The default implementation: talks to the Android and iOS code over a
/// [MethodChannel].
class MethodChannelInstallAttribution extends ImajiInstallAttributionPlatform {
  /// The channel shared with the native side.
  @visibleForTesting
  static const MethodChannel channel = MethodChannel(
    'io.github.saimskywalker/imaji_install_attribution',
  );

  @override
  Future<InstallAttributionResult> read({required Duration timeout}) async {
    final Object? reply;
    try {
      reply = await channel.invokeMethod<Object?>('read', {
        'timeoutMs': timeout.inMilliseconds,
      });
    } on MissingPluginException {
      return const Unavailable(
        UnavailableReason.notSupported,
        message: 'No install attribution implementation for this platform.',
      );
    } on PlatformException catch (e) {
      return Unavailable(
        UnavailableReason.internalError,
        message: '${e.code}: ${e.message}',
      );
    }
    final source = await installSource();
    return decodeReadReply(reply, installSource: source);
  }

  @override
  Future<InstallSource?> installSource() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final reply = await channel.invokeMethod<Object?>('installSource');
      return decodeInstallSource(reply);
    } on Object {
      return null;
    }
  }

  @override
  Future<InstallFacts?> installFacts() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return decodeInstallFacts(
        await channel.invokeMethod<Object?>('installFacts'),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<bool> isHandled() => _bool('isHandled');

  @override
  Future<bool> markHandled() => _bool('markHandled');

  @override
  Future<bool> clearHandled() => _bool('clearHandled');

  Future<bool> _bool(String method) async {
    try {
      return await channel.invokeMethod<bool>(method) ?? false;
    } on Object {
      return false;
    }
  }

  /// Turns the native `read` reply into a result. Never throws.
  @visibleForTesting
  static InstallAttributionResult decodeReadReply(
    Object? reply, {
    InstallSource? installSource,
  }) {
    if (reply is! Map) {
      return Unavailable(
        UnavailableReason.internalError,
        message: 'Unexpected reply: ${reply.runtimeType}',
        installSource: installSource,
      );
    }
    switch (reply['status']) {
      case 'referrer':
        return classifyReferrer(
          reply['referrer'] as String?,
          clickedAt: _seconds(reply['clickSeconds']),
          installBeganAt: _seconds(reply['installBeginSeconds']),
          clickedAtServer: _seconds(reply['clickServerSeconds']),
          installBeganAtServer: _seconds(reply['installBeginServerSeconds']),
          installVersion: reply['installVersion'] as String?,
          installSource: installSource,
        );
      case 'token':
        final token = reply['token'];
        if (token is String && token.isNotEmpty) {
          return Attributed(
            source: AttributionSource.appleAds,
            token: token,
            installSource: installSource,
          );
        }
        return Unavailable(
          UnavailableReason.internalError,
          message: 'Empty attribution token.',
          installSource: installSource,
        );
      case 'unavailable':
        return Unavailable(
          UnavailableReason.parse(reply['reason']),
          message: reply['message'] as String?,
          installSource: installSource,
        );
      default:
        return Unavailable(
          UnavailableReason.internalError,
          message: 'Unknown status: ${reply['status']}',
          installSource: installSource,
        );
    }
  }

  /// Decides [Attributed] vs [Organic] for a Play referrer string. See
  /// [InstallReferrer.isOrganic] for the rule.
  static InstallAttributionResult classifyReferrer(
    String? raw, {
    DateTime? clickedAt,
    DateTime? installBeganAt,
    DateTime? clickedAtServer,
    DateTime? installBeganAtServer,
    String? installVersion,
    InstallSource? installSource,
  }) {
    final referrer = InstallReferrer(raw ?? '');
    if (referrer.isOrganic) {
      return Organic(
        referrer: raw == null ? null : referrer,
        installBeganAt: installBeganAt,
        installSource: installSource,
      );
    }
    return Attributed(
      source: AttributionSource.googlePlay,
      referrer: referrer,
      clickedAt: clickedAt,
      installBeganAt: installBeganAt,
      clickedAtServer: clickedAtServer,
      installBeganAtServer: installBeganAtServer,
      installVersion: installVersion,
      installSource: installSource,
    );
  }

  /// Decodes the native `installSource` reply.
  @visibleForTesting
  static InstallSource? decodeInstallSource(Object? reply) {
    if (reply is! Map) return null;
    if (reply['error'] != null) return null;
    return InstallSource.fromPackages(
      installerPackage: reply['installerPackage'] as String?,
      initiatingPackage: reply['initiatingPackage'] as String?,
    );
  }

  /// Decodes the native `installFacts` reply.
  @visibleForTesting
  static InstallFacts? decodeInstallFacts(Object? reply) {
    if (reply is! Map) return null;
    return InstallFacts(
      firstInstalledAt: _millis(reply['firstInstallMs']),
      lastUpdatedAt: _millis(reply['lastUpdateMs']),
      pluginFirstSeenAt: _millis(reply['pluginFirstSeenMs']),
      appVersion: switch (reply['versionName']) {
        final String name => name,
        _ => null,
      },
    );
  }

  static DateTime? _millis(Object? value) {
    if (value is! num || value <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }

  /// Play reports 0 for "unknown"; that becomes `null`, not 1970.
  static DateTime? _seconds(Object? value) {
    if (value is! num || value <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      (value * 1000).toInt(),
      isUtc: true,
    );
  }
}
