import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:imaji_install_attribution/imaji_install_attribution.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannelInstallAttribution.channel;
  final platform = MethodChannelInstallAttribution();
  final calls = <MethodCall>[];

  void answer(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(calls.clear);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('decodeReadReply', () {
    InstallAttributionResult decode(Object? reply) =>
        MethodChannelInstallAttribution.decodeReadReply(reply);

    test('a campaign referrer is Attributed with timestamps', () {
      final result =
          decode({
                'status': 'referrer',
                'referrer': 'utm_source=newsletter&utm_content=%2Fitems%2F42',
                'clickSeconds': 1700000000,
                'installBeginSeconds': 1700000060,
                'clickServerSeconds': 1700000001,
                'installBeginServerSeconds': 0,
                'installVersion': '1.2.3',
                'instantExperienceLaunched': false,
              })
              as Attributed;
      expect(result.source, AttributionSource.googlePlay);
      expect(result.referrer!.utmSource, 'newsletter');
      expect(
        result.clickedAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
      );
      expect(result.installBeganAt!.isAfter(result.clickedAt!), isTrue);
      expect(result.clickedAtServer, isNotNull);
      expect(result.installBeganAtServer, isNull, reason: '0 means unknown');
      expect(result.installVersion, '1.2.3');
    });

    test('the default Play referrer is Organic', () {
      final result = decode({
        'status': 'referrer',
        'referrer': 'utm_source=google-play&utm_medium=organic',
        'clickSeconds': 0,
        'installBeginSeconds': 1700000060,
      });
      expect(result, isA<Organic>());
      expect((result as Organic).referrer!.raw, contains('organic'));
      expect(result.installBeganAt, isNotNull);
    });

    test('a null referrer is Organic with no referrer', () {
      final result = decode({'status': 'referrer', 'referrer': null});
      expect((result as Organic).referrer, isNull);
    });

    test('an iOS token is Attributed(appleAds)', () {
      final result = decode({'status': 'token', 'token': 'abc'}) as Attributed;
      expect(result.source, AttributionSource.appleAds);
      expect(result.token, 'abc');
      expect(result.referrer, isNull);
    });

    test('an empty token is internalError', () {
      final result = decode({'status': 'token', 'token': ''}) as Unavailable;
      expect(result.reason, UnavailableReason.internalError);
    });

    test('every reason the native sides send is understood', () {
      // Kotlin `Reason` constants and the Swift strings.
      const native = [
        'timeout',
        'playStoreMissing',
        'featureNotSupported',
        'serviceUnavailable',
        'serviceDisconnected',
        'deadService',
        'permissionError',
        'developerError',
        'nullDetails',
        'unknownResponse',
        'internalError',
        'notSupported',
        'networkError',
      ];
      for (final name in native) {
        final result =
            decode({'status': 'unavailable', 'reason': name, 'message': 'm'})
                as Unavailable;
        expect(result.reason.name, name);
        expect(result.message, 'm');
      }
      expect(
        native.toSet(),
        UnavailableReason.values.map((r) => r.name).toSet(),
        reason: 'no Dart reason is unreachable',
      );
    });

    test('garbage never throws', () {
      for (final reply in <Object?>[
        null,
        'x',
        42,
        <String, Object?>{},
        {'status': 'wat'},
        {'status': 'unavailable', 'reason': 'fromTheFuture'},
      ]) {
        final result = decode(reply);
        expect(result, isA<Unavailable>(), reason: '$reply');
        expect((result as Unavailable).reason, UnavailableReason.internalError);
      }
    });
  });

  group('over the channel', () {
    test('read sends the timeout in milliseconds', () async {
      answer(
        (call) => switch (call.method) {
          'read' => {'status': 'referrer', 'referrer': 'gclid=1'},
          _ => null,
        },
      );
      final result = await platform.read(timeout: const Duration(seconds: 4));
      expect(result, isA<Attributed>());
      expect(calls.first.arguments, {'timeoutMs': 4000});
    });

    test('on Android the install source rides along', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      answer(
        (call) => switch (call.method) {
          'read' => {'status': 'unavailable', 'reason': 'playStoreMissing'},
          'installSource' => {
            'installerPackage': 'com.huawei.appmarket',
            'initiatingPackage': null,
            'sdkInt': 31,
          },
          _ => null,
        },
      );
      final result = await platform.read(timeout: const Duration(seconds: 1));
      expect(
        (result as Unavailable).reason,
        UnavailableReason.playStoreMissing,
      );
      expect(result.installSource!.store, InstallStore.huaweiAppGallery);
    });

    test('an install source error becomes null', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      answer((_) => {'error': 'java.lang.SecurityException'});
      expect(await platform.installSource(), isNull);
    });

    test('iOS reports no install source', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      answer((_) => throw StateError('must not be called'));
      expect(await platform.installSource(), isNull);
      expect(calls, isEmpty);
    });

    test('on Android installFacts decodes the native reply', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      answer(
        (call) => switch (call.method) {
          'installFacts' => {
            'firstInstallMs': 1700000000000,
            'lastUpdateMs': 1700000600000,
            'pluginFirstSeenMs': 1700000700000,
            'versionName': '2.0.0',
          },
          _ => null,
        },
      );
      final facts = (await platform.installFacts())!;
      expect(
        facts.firstInstalledAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
      );
      expect(facts.lastUpdatedAt!.isAfter(facts.firstInstalledAt!), isTrue);
      expect(facts.pluginFirstSeenAt!.isAfter(facts.lastUpdatedAt!), isTrue);
      expect(facts.appVersion, '2.0.0');
      expect(facts.predatesPlugin, isTrue);
    });

    test('installFacts: unknown values become null, never a throw', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      answer(
        (_) => {
          'firstInstallMs': null,
          'lastUpdateMs': 0,
          'pluginFirstSeenMs': 'x',
          'versionName': 7,
        },
      );
      final facts = (await platform.installFacts())!;
      expect(facts.firstInstalledAt, isNull);
      expect(facts.lastUpdatedAt, isNull);
      expect(facts.pluginFirstSeenAt, isNull);
      expect(facts.appVersion, isNull);
      answer((_) => 'not a map');
      expect(await platform.installFacts(), isNull);
      answer((_) => throw PlatformException(code: 'io'));
      expect(await platform.installFacts(), isNull);
    });

    test('iOS reports no install facts', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      answer((_) => throw StateError('must not be called'));
      expect(await platform.installFacts(), isNull);
      expect(calls, isEmpty);
    });

    test('no plugin registered is notSupported', () async {
      final result = await platform.read(timeout: const Duration(seconds: 1));
      expect((result as Unavailable).reason, UnavailableReason.notSupported);
    });

    test('a PlatformException is internalError, not a throw', () async {
      answer((_) => throw PlatformException(code: 'X', message: 'nope'));
      final result = await platform.read(timeout: const Duration(seconds: 1));
      expect((result as Unavailable).reason, UnavailableReason.internalError);
      expect(result.message, 'X: nope');
    });

    test('the failed-read count is an int, and anything else throws', () async {
      answer(
        (call) => switch (call.method) {
          'failedReads' => 2,
          'recordFailedRead' => 3,
          _ => null,
        },
      );
      expect(await platform.failedReads(), 2);
      expect(await platform.recordFailedRead(), 3);
      answer((_) => null); // iOS could not store it.
      expect(platform.recordFailedRead(), throwsStateError);
      // The public API turns that into "unknown", not a throw.
      ImajiInstallAttributionPlatform.instance = platform;
      expect(await InstallAttribution.failedReads(), isNull);
    });

    test('marker methods map replies and failures to bools', () async {
      answer((call) => call.method == 'isHandled' ? true : null);
      expect(await platform.isHandled(), isTrue);
      expect(await platform.markHandled(), isFalse);
      answer((_) => throw PlatformException(code: 'io'));
      expect(await platform.clearHandled(), isFalse);
    });
  });
}
