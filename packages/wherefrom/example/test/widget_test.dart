import 'package:flutter_test/flutter_test.dart';
import 'package:wherefrom/wherefrom.dart';
import 'package:wherefrom_example/main.dart';

class _FakePlatform extends WherefromPlatform {
  bool handled = false;

  @override
  Future<InstallAttributionResult> read({required Duration timeout}) async =>
      Attributed(
        source: AttributionSource.googlePlay,
        referrer: InstallReferrer('utm_source=test&utm_content=%2Fitems%2F7'),
      );

  @override
  Future<bool> isHandled() async => handled;

  @override
  Future<bool> markHandled() async => handled = true;

  @override
  Future<bool> clearHandled() async {
    handled = false;
    return true;
  }
}

void main() {
  testWidgets('shows the attributed result and its deep link', (tester) async {
    WherefromPlatform.instance = _FakePlatform();
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('Attributed (Google Play)'), findsOneWidget);
    expect(find.text('deep link: /items/7'), findsOneWidget);
  });
}
