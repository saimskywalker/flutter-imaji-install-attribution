import 'package:flutter_test/flutter_test.dart';
import 'package:imaji_install_attribution/imaji_install_attribution.dart';

void main() {
  final table = <String?, InstallStore>{
    'com.android.vending': InstallStore.googlePlay,
    'com.sec.android.app.samsungapps': InstallStore.galaxyStore,
    'com.huawei.appmarket': InstallStore.huaweiAppGallery,
    'com.amazon.venezia': InstallStore.amazonAppstore,
    null: InstallStore.sideload,
    '': InstallStore.sideload,
    'com.google.android.packageinstaller': InstallStore.sideload,
    'com.android.packageinstaller': InstallStore.sideload,
    'com.samsung.android.scloud': InstallStore.restore,
    'com.sec.android.easyMover': InstallStore.restore,
    'org.fdroid.fdroid': InstallStore.other,
  };

  table.forEach((package, store) {
    test('$package -> ${store.name}', () {
      expect(InstallSource.storeForPackage(package), store);
      final source = InstallSource.fromPackages(installerPackage: package);
      expect(source.store, store);
      expect(source.installerPackage, package);
    });
  });

  test('value equality', () {
    expect(
      InstallSource.fromPackages(
        installerPackage: 'com.android.vending',
        initiatingPackage: 'com.android.vending',
      ),
      InstallSource.fromPackages(
        installerPackage: 'com.android.vending',
        initiatingPackage: 'com.android.vending',
      ),
    );
  });
}
