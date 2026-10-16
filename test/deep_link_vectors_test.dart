// The app half of the deferred-deep-link contract, pinned by a
// language-neutral file: test/vectors/deep_link_vectors.json. A parser or a
// link builder in any language can be tested against the same rows.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaji_install_attribution/imaji_install_attribution.dart';

void main() {
  final doc =
      jsonDecode(File('test/vectors/deep_link_vectors.json').readAsStringSync())
          as Map<String, Object?>;
  final packageName = doc['package_name']! as String;
  final key = doc['key']! as String;
  final allow = (doc['allow']! as List<Object?>).cast<String>();
  final hosts = (doc['hosts']! as List<Object?>).cast<String>();
  final rows = (doc['vectors']! as List<Object?>).cast<Map<String, Object?>>();

  ReferrerDecoding decodingOf(Map<String, Object?> row) =>
      ReferrerDecoding.values.byName(row['decoding']! as String);

  test('the file is well formed', () {
    expect(doc['format_version'], 1);
    expect(rows, isNotEmpty);
    final names = rows.map((r) => r['name']).toList();
    expect(names.toSet().length, names.length, reason: 'names are unique');
    for (final row in rows) {
      final link = row['expected_deep_link'];
      final rejection = row['rejection'];
      expect(
        (link == null) != (rejection == null),
        isTrue,
        reason: '${row['name']}: exactly one of link and rejection',
      );
    }
  });

  test('every rejection reason and every decoding has a row', () {
    expect(
      rows.map((r) => r['rejection']).whereType<String>().toSet(),
      DeepLinkRejection.values.map((r) => r.name).toSet(),
    );
    expect(
      rows.map((r) => r['decoding']).toSet(),
      ReferrerDecoding.values.map((d) => d.name).toSet(),
    );
  });

  group('InstallReferrer against every row', () {
    for (final row in rows) {
      test(row['name']! as String, () {
        final referrer = InstallReferrer(
          row['referrer_as_play_returns_it']! as String,
          decoding: decodingOf(row),
        );
        expect(referrer[key], row['value'], reason: 'decoded exactly once');

        final result = referrer.deepLinkResult(
          key: key,
          allow: allow,
          hosts: hosts,
        );
        final link = row['expected_deep_link'] as String?;
        if (link != null) {
          expect(result, isA<DeepLinkFound>());
          expect(result.uriOrNull.toString(), link);
        } else {
          expect((result as DeepLinkRejected).reason.name, row['rejection']);
        }
        expect(
          referrer.deepLink(key: key, allow: allow, hosts: hosts)?.toString(),
          link,
        );
      });
    }
  });

  group('PlayStoreUrl against every row with a path', () {
    for (final row in rows.where((r) => r.containsKey('path'))) {
      test(row['name']! as String, () {
        final path = row['path']! as String;
        final asPlayReturnsIt = row['referrer_as_play_returns_it']! as String;
        expect(PlayStoreUrl.encodeReferrer({key: path}), asPlayReturnsIt);

        final url = PlayStoreUrl.web(
          packageName: packageName,
          referrer: {key: path},
        );
        expect(url.toString(), row['play_store_url']);
        expect(
          Uri.encodeQueryComponent(asPlayReturnsIt),
          row['play_url_referrer_param'],
        );
        // Play removes the outer layer once.
        expect(
          Uri.parse(
            row['play_store_url']! as String,
          ).queryParameters['referrer'],
          asPlayReturnsIt,
        );
      });
    }
  });
}
