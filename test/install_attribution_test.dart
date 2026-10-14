import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaji_install_attribution/imaji_install_attribution.dart';

/// A scriptable platform: no device, no channel.
class FakePlatform extends ImajiInstallAttributionPlatform {
  FakePlatform(this.onRead);

  Future<InstallAttributionResult> Function(Duration timeout) onRead;
  int reads = 0;
  Duration? lastTimeout;
  bool handled = false;
  bool failStore = false;
  InstallSource? source;

  @override
  Future<InstallAttributionResult> read({required Duration timeout}) {
    reads++;
    lastTimeout = timeout;
    return onRead(timeout);
  }

  @override
  Future<InstallSource?> installSource() async => source;

  @override
  Future<bool> isHandled() async {
    if (failStore) throw StateError('disk on fire');
    return handled;
  }

  @override
  Future<bool> markHandled() async {
    if (failStore) throw StateError('disk on fire');
    return handled = true;
  }

  @override
  Future<bool> clearHandled() async {
    handled = false;
    return true;
  }
}

class ImplementsInsteadOfExtends implements ImajiInstallAttributionPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _attributed = Attributed(
  source: AttributionSource.googlePlay,
  referrer: InstallReferrer('utm_source=x&utm_content=%2Fitems%2F1'),
);

void main() {
  late FakePlatform fake;

  setUp(() {
    fake = FakePlatform((_) async => _attributed);
    ImajiInstallAttributionPlatform.instance = fake;
    InstallAttribution.debugClearOverride();
  });

  test('the default instance talks over the method channel', () {
    expect(
      MethodChannelInstallAttribution(),
      isA<ImajiInstallAttributionPlatform>(),
    );
  });

  test('a platform must extend, not implement, the interface', () {
    expect(
      () => ImajiInstallAttributionPlatform.instance =
          ImplementsInsteadOfExtends(),
      throwsA(isA<AssertionError>()),
    );
  });

  group('read', () {
    test('returns what the platform returns and passes the timeout', () async {
      final result = await InstallAttribution.read(
        timeout: const Duration(seconds: 3),
      );
      expect(result, same(_attributed));
      expect(fake.lastTimeout, const Duration(seconds: 3));
    });

    test(
      'defaults to a 10 second timeout, and fixes a non-positive one',
      () async {
        await InstallAttribution.read();
        expect(fake.lastTimeout, const Duration(seconds: 10));
        await InstallAttribution.read(timeout: Duration.zero);
        expect(fake.lastTimeout, const Duration(seconds: 10));
      },
    );

    test('never throws: a throwing platform becomes internalError', () async {
      fake.onRead = (_) async => throw StateError('boom');
      final result = await InstallAttribution.read();
      expect(result, isA<Unavailable>());
      expect((result as Unavailable).reason, UnavailableReason.internalError);
      expect(result.message, contains('boom'));
    });

    test('never throws: an Error is caught too', () async {
      fake.onRead = (_) => throw UnimplementedError();
      final result = await InstallAttribution.read();
      expect((result as Unavailable).reason, UnavailableReason.internalError);
    });

    testWidgets('a platform that never replies becomes timeout', (
      tester,
    ) async {
      fake.onRead = (_) => Completer<InstallAttributionResult>().future;
      InstallAttributionResult? result;
      unawaited(
        InstallAttribution.read(
          timeout: const Duration(seconds: 1),
        ).then((r) => result = r),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(result, isNull, reason: 'grace period not over yet');
      await tester.pump(const Duration(seconds: 2));
      expect((result! as Unavailable).reason, UnavailableReason.timeout);
    });

    test('concurrent calls share one platform read', () async {
      final gate = Completer<InstallAttributionResult>();
      fake.onRead = (_) => gate.future;
      final a = InstallAttribution.read();
      final b = InstallAttribution.read();
      gate.complete(_attributed);
      expect(await a, same(await b));
      expect(fake.reads, 1);
      await InstallAttribution.read();
      expect(fake.reads, 2, reason: 'a finished read is not cached');
    });
  });

  group('readOnce / markHandled', () {
    test('returns the result until markHandled, then null', () async {
      expect(await InstallAttribution.readOnce(), same(_attributed));
      expect(
        await InstallAttribution.readOnce(),
        same(_attributed),
        reason: 'reading alone does not consume',
      );
      expect(await InstallAttribution.markHandled(), isTrue);
      expect(await InstallAttribution.isHandled(), isTrue);
      expect(await InstallAttribution.readOnce(), isNull);
      expect(fake.reads, 2, reason: 'a handled install never hits Play');
      await InstallAttribution.clearHandled();
      expect(await InstallAttribution.readOnce(), same(_attributed));
    });

    test('a broken store never throws and counts as not handled', () async {
      fake.failStore = true;
      expect(await InstallAttribution.isHandled(), isFalse);
      expect(await InstallAttribution.markHandled(), isFalse);
      expect(await InstallAttribution.readOnce(), same(_attributed));
    });
  });

  group('installSource', () {
    test('passes through, and never throws', () async {
      fake.source = InstallSource.fromPackages(
        installerPackage: 'com.android.vending',
      );
      expect(
        (await InstallAttribution.installSource())!.store,
        InstallStore.googlePlay,
      );
    });
  });

  group('debugOverride', () {
    test('a referrer is classified like a real one', () async {
      InstallAttribution.debugOverride(
        referrer: 'utm_source=news&utm_content=%2Fitems%2F3',
        clickedAt: DateTime.utc(2026, 1, 2),
      );
      final result = await InstallAttribution.read();
      expect(fake.reads, 0, reason: 'the platform is not asked');
      final attributed = result as Attributed;
      expect(attributed.source, AttributionSource.googlePlay);
      expect(attributed.clickedAt, DateTime.utc(2026, 1, 2));
      expect(
        attributed.referrer!.deepLink(allow: ['/items/']).toString(),
        '/items/3',
      );
    });

    test('an organic referrer stays organic', () async {
      InstallAttribution.debugOverride(
        referrer: 'utm_source=google-play&utm_medium=organic',
      );
      expect(await InstallAttribution.read(), isA<Organic>());
    });

    test('a ready-made result is returned as is', () async {
      const unavailable = Unavailable(UnavailableReason.featureNotSupported);
      InstallAttribution.debugOverride(result: unavailable);
      expect(await InstallAttribution.read(), same(unavailable));
      expect(InstallAttribution.debugHasOverride, isTrue);
      InstallAttribution.debugClearOverride();
      expect(InstallAttribution.debugHasOverride, isFalse);
      expect(await InstallAttribution.read(), same(_attributed));
    });
  });
}
