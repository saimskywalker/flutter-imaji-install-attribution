// Runs on a real device or emulator:
//   cd example && flutter test integration_test
//
// It cannot assert a specific attribution (that depends on how the build was
// installed), only that the call completes with one of the three states and
// never throws.

import 'package:flutter_test/flutter_test.dart';
import 'package:imaji_install_attribution/imaji_install_attribution.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('read completes with a typed result', (tester) async {
    final result = await InstallAttribution.read(
      timeout: const Duration(seconds: 5),
    );
    expect(
      result,
      anyOf(isA<Attributed>(), isA<Organic>(), isA<Unavailable>()),
    );
  });

  testWidgets('consume-once marker round-trips', (tester) async {
    await InstallAttribution.clearHandled();
    expect(await InstallAttribution.isHandled(), isFalse);
    expect(await InstallAttribution.markHandled(), isTrue);
    expect(await InstallAttribution.readOnce(), isNull);
    await InstallAttribution.clearHandled();
  });
}
