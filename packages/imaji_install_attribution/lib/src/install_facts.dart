import 'package:flutter/foundation.dart';

/// What the device knows about this install, independent of any referrer.
///
/// [InstallAttribution.readOnce] uses it to tell a fresh install from an
/// existing install that has just been updated to a version using this
/// plugin. Android only; iOS reports no facts, and every member may be
/// `null` when the platform could not read it.
@immutable
class InstallFacts {
  /// Creates install facts. Platform implementations and tests build these.
  const InstallFacts({
    this.firstInstalledAt,
    this.lastUpdatedAt,
    this.pluginFirstSeenAt,
    this.appVersion,
  });

  /// When the app was first installed on this device
  /// (`PackageInfo.firstInstallTime`).
  final DateTime? firstInstalledAt;

  /// When the app was last installed or updated
  /// (`PackageInfo.lastUpdateTime`). Equal to [firstInstalledAt] until the
  /// first update.
  final DateTime? lastUpdatedAt;

  /// The first time a version of the app containing this plugin started on
  /// this install. Recorded once, in storage that is excluded from backups,
  /// so a reinstall or a restore onto a new device starts over.
  final DateTime? pluginFirstSeenAt;

  /// The running app's version name, for logs.
  final String? appVersion;

  /// How far apart [firstInstalledAt] and [lastUpdatedAt] may be and still
  /// count as "never updated".
  ///
  /// A fresh install reports the two as equal; the tolerance only absorbs
  /// rounding by the platform. No real update happens within a minute of
  /// the install that preceded it.
  static const Duration updateTolerance = Duration(minutes: 1);

  /// Whether the app has been updated since it was first installed. `null`
  /// when either timestamp is unknown.
  bool? get updatedSinceInstall {
    final first = firstInstalledAt;
    final last = lastUpdatedAt;
    if (first == null || last == null) return null;
    return last.difference(first) > updateTolerance;
  }

  /// Whether the plugin first ran only after the app's latest update, i.e.
  /// the version that adopted the plugin is the update itself. `null` when
  /// unknown.
  bool? get pluginArrivedWithLatestUpdate {
    final seen = pluginFirstSeenAt;
    final last = lastUpdatedAt;
    if (seen == null || last == null) return null;
    return !seen.isBefore(last);
  }

  /// The rule behind `treatUpgradesAsHandled`: this install existed before
  /// the plugin did. True only when the app has been updated since it was
  /// installed **and** the plugin first ran after that update. Unknown facts
  /// never count as an upgrade.
  ///
  /// 0.1.x kept no first-seen record, so an install that started on 0.1.x
  /// also matches on its first 0.2.0 launch: that install already had its
  /// first launch under 0.1.x.
  bool get predatesPlugin =>
      updatedSinceInstall == true && pluginArrivedWithLatestUpdate == true;

  @override
  String toString() =>
      'InstallFacts(firstInstalledAt: $firstInstalledAt, '
      'lastUpdatedAt: $lastUpdatedAt, pluginFirstSeenAt: $pluginFirstSeenAt, '
      'appVersion: $appVersion)';
}
