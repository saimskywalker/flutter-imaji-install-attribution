import 'package:flutter_test/flutter_test.dart';
import 'package:imaji_install_attribution/imaji_install_attribution.dart';

void main() {
  final installed = DateTime.utc(2026, 1, 1);

  test('a fresh install is not updated and does not predate the plugin', () {
    final facts = InstallFacts(
      firstInstalledAt: installed,
      lastUpdatedAt: installed,
      pluginFirstSeenAt: installed.add(const Duration(minutes: 3)),
    );
    expect(facts.updatedSinceInstall, isFalse);
    expect(facts.pluginArrivedWithLatestUpdate, isTrue);
    expect(facts.predatesPlugin, isFalse);
  });

  test('the update tolerance absorbs rounding only', () {
    InstallFacts after(Duration d) => InstallFacts(
      firstInstalledAt: installed,
      lastUpdatedAt: installed.add(d),
    );
    expect(after(const Duration(seconds: 30)).updatedSinceInstall, isFalse);
    expect(InstallFacts.updateTolerance, const Duration(minutes: 1));
    expect(after(const Duration(minutes: 2)).updatedSinceInstall, isTrue);
  });

  test('an update that brought the plugin predates it', () {
    final updated = installed.add(const Duration(days: 40));
    final facts = InstallFacts(
      firstInstalledAt: installed,
      lastUpdatedAt: updated,
      pluginFirstSeenAt: updated.add(const Duration(seconds: 5)),
    );
    expect(facts.predatesPlugin, isTrue);
  });

  test('an update after the plugin first ran does not', () {
    final facts = InstallFacts(
      firstInstalledAt: installed,
      lastUpdatedAt: installed.add(const Duration(days: 40)),
      pluginFirstSeenAt: installed.add(const Duration(minutes: 1)),
    );
    expect(facts.updatedSinceInstall, isTrue);
    expect(facts.pluginArrivedWithLatestUpdate, isFalse);
    expect(facts.predatesPlugin, isFalse);
  });

  test('unknown facts never count as an upgrade', () {
    expect(const InstallFacts().predatesPlugin, isFalse);
    expect(const InstallFacts().updatedSinceInstall, isNull);
    expect(const InstallFacts().pluginArrivedWithLatestUpdate, isNull);
    expect(
      InstallFacts(
        firstInstalledAt: installed,
        lastUpdatedAt: installed.add(const Duration(days: 1)),
      ).predatesPlugin,
      isFalse,
    );
  });
}
