import 'package:flutter/foundation.dart';

/// The store (or mechanism) that put the app on the device.
enum InstallStore {
  /// Google Play (`com.android.vending`).
  googlePlay,

  /// Samsung Galaxy Store (`com.sec.android.app.samsungapps`).
  galaxyStore,

  /// Huawei AppGallery (`com.huawei.appmarket`).
  huaweiAppGallery,

  /// Amazon Appstore (`com.amazon.venezia`).
  amazonAppstore,

  /// Installed from an APK file or `adb install`: no installer package, or a
  /// system package installer.
  sideload,

  /// Restored by a backup / device-transfer tool (for example Samsung Smart
  /// Switch or Samsung Cloud) rather than installed from a store.
  restore,

  /// Some other installer; see [InstallSource.installerPackage].
  other,
}

/// Which package installed the app, as Android reports it.
///
/// This is all the platform knows. It cannot tell "shared in a chat app" from
/// "found in the store": a link shared through a messenger only shows up in
/// attribution if the link itself carried a `referrer` / `utm_*` parameter.
@immutable
class InstallSource {
  /// Creates an install source. Normally built by the plugin.
  const InstallSource({
    required this.store,
    this.installerPackage,
    this.initiatingPackage,
  });

  /// Builds an [InstallSource] from the raw installer package names.
  factory InstallSource.fromPackages({
    String? installerPackage,
    String? initiatingPackage,
  }) => InstallSource(
    store: storeForPackage(installerPackage),
    installerPackage: installerPackage,
    initiatingPackage: initiatingPackage,
  );

  /// The mapped store.
  final InstallStore store;

  /// The package that installed the app (`installingPackageName` on API 30+,
  /// `getInstallerPackageName` below). `null` for `adb install`.
  final String? installerPackage;

  /// The package that asked for the install (API 30+ only). Differs from
  /// [installerPackage] when, say, a browser handed an APK to the system
  /// installer.
  final String? initiatingPackage;

  /// Maps an installer package name to an [InstallStore].
  static InstallStore storeForPackage(String? package) {
    if (package == null || package.isEmpty) return InstallStore.sideload;
    return _known[package] ?? InstallStore.other;
  }

  static const Map<String, InstallStore> _known = {
    'com.android.vending': InstallStore.googlePlay,
    'com.google.android.feedback': InstallStore.googlePlay,
    'com.sec.android.app.samsungapps': InstallStore.galaxyStore,
    'com.huawei.appmarket': InstallStore.huaweiAppGallery,
    'com.amazon.venezia': InstallStore.amazonAppstore,
    'com.android.packageinstaller': InstallStore.sideload,
    'com.google.android.packageinstaller': InstallStore.sideload,
    'com.samsung.android.packageinstaller': InstallStore.sideload,
    'com.android.shell': InstallStore.sideload,
    'com.samsung.android.scloud': InstallStore.restore,
    'com.sec.android.easyMover': InstallStore.restore,
    'com.sec.android.easyMover.Agent': InstallStore.restore,
    'com.google.android.apps.restore': InstallStore.restore,
  };

  @override
  bool operator ==(Object other) =>
      other is InstallSource &&
      other.store == store &&
      other.installerPackage == installerPackage &&
      other.initiatingPackage == initiatingPackage;

  @override
  int get hashCode => Object.hash(store, installerPackage, initiatingPackage);

  @override
  String toString() =>
      'InstallSource(${store.name}, installer: $installerPackage, '
      'initiating: $initiatingPackage)';
}
