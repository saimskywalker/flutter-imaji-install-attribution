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
  InstallFacts? facts;
  int marks = 0;

  @override
  Future<InstallAttributionResult> read({required Duration timeout}) {
    reads++;
    lastTimeout = timeout;
    return onRead(timeout);
  }

  @override
  Future<InstallSource?> installSource() async => source;

  @override
  Future<InstallFacts?> installFacts() async => facts;

  @override
  Future<bool> isHandled() async {
    if (failStore) throw StateError('disk on fire');
    return handled;
  }

  @override
  Future<bool> markHandled() async {
    if (failStore) throw StateError('disk on fire');
    marks++;
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
    InstallAttribution.clock = DateTime.now;
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

  group('readOnce: first launch only (#30)', () {
    final now = DateTime.utc(2026, 6, 1, 12);
    final fortyDaysAgo = now.subtract(const Duration(days: 40));

    /// A user installed from a link 40 days ago; Play still returns it.
    final oldLink = Attributed(
      source: AttributionSource.googlePlay,
      referrer: InstallReferrer('utm_source=x&utm_content=%2Finvite%2Fabc123'),
      clickedAt: fortyDaysAgo,
      clickedAtServer: fortyDaysAgo,
      installBeganAt: fortyDaysAgo,
      installBeganAtServer: fortyDaysAgo,
      installVersion: '1.0.0',
    );

    setUp(() {
      InstallAttribution.clock = () => now;
      fake.onRead = (_) async => oldLink;
    });

    test('an app that adopts the plugin in an update does not re-deliver an '
        'old referrer, and marks the install handled', () async {
      // Installed 40 days ago, updated an hour ago to the first version with
      // the plugin, which first ran just now.
      fake.facts = InstallFacts(
        firstInstalledAt: fortyDaysAgo,
        lastUpdatedAt: now.subtract(const Duration(hours: 1)),
        pluginFirstSeenAt: now,
        appVersion: '2.0.0',
      );
      expect(await InstallAttribution.readOnce(), isNull);
      expect(InstallAttribution.lastSkipReason, ReadOnceSkip.adoptedInUpdate);
      expect(fake.handled, isTrue);
      expect(fake.reads, 0, reason: 'decided without a Play Store call');
      expect(await InstallAttribution.readOnce(), isNull);
      expect(InstallAttribution.lastSkipReason, ReadOnceSkip.handled);
    });

    test('a fresh install is delivered', () async {
      final installed = now.subtract(const Duration(minutes: 1));
      fake.onRead = (_) async => Attributed(
        source: AttributionSource.googlePlay,
        referrer: oldLink.referrer,
        clickedAt: installed,
        installBeganAt: installed,
        installVersion: '2.0.0',
      );
      fake.facts = InstallFacts(
        firstInstalledAt: installed,
        lastUpdatedAt: installed,
        pluginFirstSeenAt: now,
        appVersion: '2.0.0',
      );
      final result = await InstallAttribution.readOnce();
      expect((result! as Attributed).referrer, oldLink.referrer);
      expect(InstallAttribution.lastSkipReason, isNull);
      expect(fake.handled, isFalse, reason: 'the app marks it after routing');
    });

    test(
      'an update after the plugin was already present is not an adoption',
      () async {
        // The plugin ran on day one; the read never got handled (for example
        // the app had not reached routing yet); the app was updated since.
        fake.facts = InstallFacts(
          firstInstalledAt: fortyDaysAgo,
          lastUpdatedAt: now.subtract(const Duration(days: 1)),
          pluginFirstSeenAt: fortyDaysAgo.add(const Duration(minutes: 2)),
        );
        expect(await InstallAttribution.readOnce(), same(oldLink));
      },
    );

    test('treatUpgradesAsHandled: false keeps the 0.1 behaviour', () async {
      fake.facts = InstallFacts(
        firstInstalledAt: fortyDaysAgo,
        lastUpdatedAt: now.subtract(const Duration(hours: 1)),
        pluginFirstSeenAt: now,
      );
      expect(
        await InstallAttribution.readOnce(treatUpgradesAsHandled: false),
        same(oldLink),
      );
      expect(fake.handled, isFalse);
    });

    test('no facts (iOS, an old implementation) or unknown facts never '
        'suppress', () async {
      fake.facts = null;
      expect(await InstallAttribution.readOnce(), same(oldLink));
      fake.facts = InstallFacts(pluginFirstSeenAt: now);
      expect(await InstallAttribution.readOnce(), same(oldLink));
      fake.facts = InstallFacts(
        firstInstalledAt: fortyDaysAgo,
        lastUpdatedAt: now.subtract(const Duration(hours: 1)),
      );
      expect(await InstallAttribution.readOnce(), same(oldLink));
      expect(fake.handled, isFalse);
    });

    group('maxClickAge', () {
      Attributed clicked({DateTime? device, DateTime? server}) => Attributed(
        source: AttributionSource.googlePlay,
        referrer: oldLink.referrer,
        clickedAt: device,
        clickedAtServer: server,
      );

      test(
        'a click older than the limit is handled and not delivered',
        () async {
          expect(
            await InstallAttribution.readOnce(
              maxClickAge: const Duration(days: 7),
            ),
            isNull,
          );
          expect(InstallAttribution.lastSkipReason, ReadOnceSkip.staleClick);
          expect(fake.handled, isTrue);
        },
      );

      test('a recent click is delivered', () async {
        final recent = clicked(
          device: now.subtract(const Duration(days: 2)),
          server: now.subtract(const Duration(days: 2)),
        );
        fake.onRead = (_) async => recent;
        expect(
          await InstallAttribution.readOnce(
            maxClickAge: const Duration(days: 7),
          ),
          same(recent),
        );
      });

      test("Play's server clock wins over a wrong device clock", () async {
        // The device clock says yesterday, Play's server says 30 days ago.
        fake.onRead = (_) async => clicked(
          device: now.subtract(const Duration(days: 1)),
          server: now.subtract(const Duration(days: 30)),
        );
        expect(
          await InstallAttribution.readOnce(
            maxClickAge: const Duration(days: 7),
          ),
          isNull,
        );

        await InstallAttribution.clearHandled();
        final fresh = clicked(
          device: now.subtract(const Duration(days: 30)),
          server: now.subtract(const Duration(days: 1)),
        );
        fake.onRead = (_) async => fresh;
        expect(
          await InstallAttribution.readOnce(
            maxClickAge: const Duration(days: 7),
          ),
          same(fresh),
        );
      });

      test('falls back to the device clock, and an unknown click time is '
          'never stale', () async {
        fake.onRead = (_) async =>
            clicked(device: now.subtract(const Duration(days: 30)));
        expect(
          await InstallAttribution.readOnce(
            maxClickAge: const Duration(days: 7),
          ),
          isNull,
        );

        await InstallAttribution.clearHandled();
        final unknown = clicked(); // Play reported 0: decoded as null.
        fake.onRead = (_) async => unknown;
        expect(
          await InstallAttribution.readOnce(
            maxClickAge: const Duration(days: 7),
          ),
          same(unknown),
        );
      });

      test('organic and unavailable results are not affected', () async {
        const unavailable = Unavailable(UnavailableReason.timeout);
        fake.onRead = (_) async => unavailable;
        expect(
          await InstallAttribution.readOnce(maxClickAge: Duration.zero),
          same(unavailable),
        );
        expect(fake.handled, isFalse);
      });
    });

    group('pastInstallFlow', () {
      test('true: handled without a read, and nothing is delivered', () async {
        expect(
          await InstallAttribution.readOnce(pastInstallFlow: () => true),
          isNull,
        );
        expect(InstallAttribution.lastSkipReason, ReadOnceSkip.pastInstallFlow);
        expect(fake.handled, isTrue);
        expect(fake.reads, 0);
      });

      test('false: delivered', () async {
        expect(
          await InstallAttribution.readOnce(pastInstallFlow: () async => false),
          same(oldLink),
        );
      });

      test('a check that throws marks nothing and returns null', () async {
        expect(
          await InstallAttribution.readOnce(
            pastInstallFlow: () => throw StateError('session not loaded'),
          ),
          isNull,
        );
        expect(
          InstallAttribution.lastSkipReason,
          ReadOnceSkip.pastInstallFlowFailed,
        );
        expect(fake.handled, isFalse);
        expect(fake.reads, 0);
      });

      test(
        'the README recipe: a reinstall with restored prefs still routes',
        () async {
          // After a reinstall the plugin's marker is gone (it is excluded from
          // backups), but Auto Backup restored the app's SharedPreferences,
          // including its own "first run done" flag and a remembered session.
          final restoredPrefs = {'signedIn': true, 'firstRunDone': true};
          // The recipe keeps its first-run flag in no-backup storage instead;
          // a reinstall starts it empty.
          final noBackupStore = <String, bool>{};

          bool recipe() =>
              restoredPrefs['signedIn'] == true &&
              (noBackupStore['firstRunDone'] ?? false);
          bool naive() =>
              restoredPrefs['signedIn'] == true &&
              restoredPrefs['firstRunDone'] == true;

          expect(
            await InstallAttribution.readOnce(pastInstallFlow: recipe),
            same(oldLink),
            reason: 'signed in, but this device never finished a first run',
          );
          expect(
            await InstallAttribution.readOnce(pastInstallFlow: naive),
            isNull,
            reason: 'the backed-up flag spends the link silently',
          );
        },
      );
    });

    test('lastSkipReason clears once a result is delivered', () async {
      fake.handled = true;
      await InstallAttribution.readOnce();
      expect(InstallAttribution.lastSkipReason, ReadOnceSkip.handled);
      fake.handled = false;
      await InstallAttribution.readOnce();
      expect(InstallAttribution.lastSkipReason, isNull);
    });
  });

  group('adoptExistingState', () {
    test('true marks the install handled, once', () async {
      expect(
        await InstallAttribution.adoptExistingState(alreadyHandled: true),
        isTrue,
      );
      expect(fake.handled, isTrue);
      expect(await InstallAttribution.readOnce(), isNull);
      expect(
        await InstallAttribution.adoptExistingState(alreadyHandled: true),
        isTrue,
      );
      expect(fake.marks, 1, reason: 'idempotent: no second write');
    });

    test('false is a no-op, and never unmarks', () async {
      expect(
        await InstallAttribution.adoptExistingState(alreadyHandled: false),
        isFalse,
      );
      expect(fake.marks, 0);
      expect(await InstallAttribution.readOnce(), same(_attributed));
      await InstallAttribution.markHandled();
      expect(
        await InstallAttribution.adoptExistingState(alreadyHandled: false),
        isTrue,
      );
      expect(fake.handled, isTrue);
    });

    test('never throws', () async {
      fake.failStore = true;
      expect(
        await InstallAttribution.adoptExistingState(alreadyHandled: true),
        isFalse,
      );
    });
  });

  group('installFacts', () {
    test('passes through, and never throws', () async {
      final facts = InstallFacts(appVersion: '1.0.0');
      fake.facts = facts;
      expect(await InstallAttribution.installFacts(), same(facts));
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
