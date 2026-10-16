// The builder half of the shared vectors. The Flutter plugin's
// test/referrer_vectors_test.dart reads the same file for the parser half,
// so a change to either side that the other does not share fails a test.
import 'dart:convert';
import 'dart:io';

import 'package:imaji_referrer_builder/imaji_referrer_builder.dart';
import 'package:test/test.dart';

/// The vectors live at the repository root, next to the plugin's tests.
const _vectorsPath = '../../test/vectors/referrer_vectors.json';

void main() {
  final file = File(_vectorsPath);
  if (!file.existsSync()) {
    // Expected only outside the repository, e.g. from the pub.dev archive,
    // which does not ship the root test directory. In CI it is a failure:
    // a moved file must not turn the contract test into a skip.
    final inCi = Platform.environment['CI'] == 'true';
    test(
      'shared vectors',
      () => fail('$_vectorsPath not found'),
      skip: inCi
          ? false
          : '$_vectorsPath not found: run the tests from a repository clone',
    );
    return;
  }

  final doc = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
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

  group('builds', () {
    for (final row in vectors) {
      final campaign = row['campaign']! as String;
      final path = row['path'] as String?;
      test(row['name'], () {
        final referrer = PlayStoreUrl.appendPath(
          campaign,
          path,
          allow: allow,
          hosts: hosts,
          key: key,
        );
        expect(referrer, row['referrer_as_play_returns_it']);

        final url = PlayStoreUrl.webFromReferrer(
          packageName: packageName,
          referrer: referrer,
        );
        expect(url.toString(), row['play_store_url']);
        expect(
          url.query.split('&referrer=').last,
          row['play_url_referrer_param'],
        );

        // Play's single outer decode gives the referrer back unchanged, and
        // one inner decode gives the path back unchanged.
        expect(url.queryParameters['referrer'], referrer);
        if (path != null) {
          expect(Uri.splitQueryString(referrer)[key], path);
        }

        final link = path == null
            ? null
            : PlayStoreUrl.expectedDeepLink(path, allow: allow, hosts: hosts);
        expect(link?.toString(), row['expected_deep_link']);
      });
    }
  });

  group('refuses', () {
    for (final row in refused) {
      test(row['name'], () {
        final path = row['path']! as String;
        expect(
          () => PlayStoreUrl.appendPath(
            row['campaign']! as String,
            path,
            allow: allow,
            hosts: hosts,
            key: key,
          ),
          throwsArgumentError,
        );
        if (row['app_drops_path'] != null) {
          expect(
            PlayStoreUrl.checkPath(path, allow: allow, hosts: hosts)?.name,
            row['reason'],
          );
        }
      });
    }
  });
}
