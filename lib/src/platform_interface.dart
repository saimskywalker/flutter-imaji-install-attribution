import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'install_facts.dart';
import 'install_source.dart';
import 'method_channel.dart';
import 'result.dart';

/// The contract a platform implementation fulfils.
///
/// Apps and tests can install a fake without a device:
///
/// ```dart
/// class FakeAttribution extends ImajiInstallAttributionPlatform {
///   @override
///   Future<InstallAttributionResult> read({required Duration timeout}) async =>
///       Attributed(
///         source: AttributionSource.googlePlay,
///         referrer: InstallReferrer('utm_content=%2Fitems%2F42'),
///       );
///   // ...
/// }
///
/// ImajiInstallAttributionPlatform.instance = FakeAttribution();
/// ```
///
/// Extend this class (do not `implement` it) so new methods added in minor
/// versions get a default.
abstract class ImajiInstallAttributionPlatform extends PlatformInterface {
  /// Constructs a platform implementation.
  ImajiInstallAttributionPlatform() : super(token: _token);

  static final Object _token = Object();

  static ImajiInstallAttributionPlatform _instance =
      MethodChannelInstallAttribution();

  /// The active implementation. Defaults to [MethodChannelInstallAttribution].
  static ImajiInstallAttributionPlatform get instance => _instance;

  static set instance(ImajiInstallAttributionPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Reads the install attribution. Implementations should not throw; the
  /// public API still guards against it.
  Future<InstallAttributionResult> read({required Duration timeout}) {
    throw UnimplementedError('read() has not been implemented.');
  }

  /// Which package installed the app, or `null` when unknown.
  Future<InstallSource?> installSource() async => null;

  /// What the device knows about this install, or `null` when the platform
  /// has nothing to report (iOS, or an implementation that predates 0.2.0).
  /// `null` turns `treatUpgradesAsHandled` into a no-op.
  Future<InstallFacts?> installFacts() async => null;

  /// Whether [markHandled] was called on this install.
  Future<bool> isHandled() {
    throw UnimplementedError('isHandled() has not been implemented.');
  }

  /// Persists the consume-once marker. Returns `true` when it was written.
  Future<bool> markHandled() {
    throw UnimplementedError('markHandled() has not been implemented.');
  }

  /// Removes the consume-once marker. Returns `true` when it was removed.
  Future<bool> clearHandled() {
    throw UnimplementedError('clearHandled() has not been implemented.');
  }
}
