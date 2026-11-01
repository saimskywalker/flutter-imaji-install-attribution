// The parser half of the shared vectors in test/vectors/referrer_vectors.json.
// packages/imaji_referrer_builder/test/referrer_vectors_test.dart reads the
// same file for the builder half: the builder must emit these referrers and
// store URLs byte for byte, and the app must route these links from them.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaji_install_attribution/imaji_install_attribution.dart';

void main() {
  final doc =
      jsonDecode(File('test/vectors/referrer_vectors.json').readAsStringSync())
          as Map<String, Object?>;
  final packageName = doc['package_name']! as String;
  final key = doc['key']! as String;
  final allow = (doc['allow']! as List<Object?>).cast<String>();
  final hosts = (doc['hosts']! as List<Object?>).cast<String>();
  final vectors = (doc['vectors']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final refused = (doc['refused']! as List<Object?>)
      .cast<Map<String, Object?>>();

  test('the file has rows', () {
    expect(doc['format_version'], 1);
    expect(vectors, isNotEmpty);
    expect(refused, isNotEmpty);
  });

  group('store URL -> Play -> InstallReferrer -> deepLink()', () {
    for (final row in vectors) {
      final campaign = row['campaign']! as String;
      final path = row['path'] as String?;
      final url = Uri.parse(row['play_store_url']! as String);
      final asPlayReturnsIt = row['referrer_as_play_returns_it']! as String;

      test(row['name']! as String, () {
        // Play removes the outer layer once.
        expect(url.queryParameters['id'], packageName);
        expect(url.queryParameters['referrer'], asPlayReturnsIt);
        expect(
          Uri.decodeQueryComponent(row['play_url_referrer_param']! as String),
          asPlayReturnsIt,
        );

        // The app removes the inner layer once and routes the path.
        final referrer = InstallReferrer(asPlayReturnsIt);
        expect(
          referrer.deepLink(key: key, allow: allow, hosts: hosts)?.toString(),
          row['expected_deep_link'],
        );
        if (path != null) expect(referrer[key], path);

        // Every configured campaign key reaches the app as configured.
        InstallReferrer(campaign).parameters.forEach((k, v) {
          expect(referrer[k], v, reason: 'campaign key $k');
        });
      });

      // Where the configured campaign is in canonical form, the plugin's
      // own map builder must produce the very same store URL.
      final parsed = InstallReferrer(campaign).parameters;
      if (path != null && PlayStoreUrl.encodeReferrer(parsed) == campaign) {
        test('${row['name']} (PlayStoreUrl.web agrees)', () {
          expect(
            PlayStoreUrl.web(
              packageName: packageName,
              referrer: {...parsed, key: path},
            ).toString(),
            row['play_store_url'],
          );
        });
      }
    }
  });

  group('paths the builder refuses are paths the app drops', () {
    for (final row in refused) {
      final drops = row['app_drops_path'] as bool?;
      if (drops == null) continue; // a campaign refusal, not a path one
      test(row['name']! as String, () {
        final path = row['path']! as String;
        // Encoded once, the way a correct builder would have sent it.
        final referrer = InstallReferrer(
          PlayStoreUrl.encodeReferrer({key: path}),
        );
        final link = referrer.deepLink(key: key, allow: allow, hosts: hosts);
        expect(link == null, drops);
      });
    }
  });
}
