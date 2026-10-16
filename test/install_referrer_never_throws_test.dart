import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:imaji_install_attribution/imaji_install_attribution.dart';

/// The referrer is input anyone can craft: a Play URL can carry any
/// `referrer=`. Nothing on [InstallReferrer] may throw for it, and a link it
/// does return must be safe to use (its own decoders must not throw either).
void main() {
  const allow = ['/', '/items'];
  const hosts = ['example.com'];

  /// Touches every member of [InstallReferrer] and checks the deep link, if
  /// any, decodes cleanly. Fails the test on any exception.
  void exercise(String raw) {
    final r = InstallReferrer(raw);
    r.parameters.forEach((key, value) {
      r[key];
      check(
        InstallReferrer.resolveDeepLink(value, allow: allow, hosts: hosts),
        raw,
      );
    });
    r.isOrganic;
    r.utmSource;
    r.utmMedium;
    r.utmCampaign;
    r.utmContent;
    r.utmTerm;
    r.toString();
    r.hashCode;
    check(r.deepLink(allow: allow, hosts: hosts), raw);
    check(r.deepLink(key: 'link', allow: allow), raw);
    // The raw string itself as a value, without the parameter decode.
    check(InstallReferrer.resolveDeepLink(raw, allow: allow), raw);
  }

  group('deepLink never throws', () {
    // (raw referrer as Play returns it, the decoded utm_content)
    final malformed = <(String, String)>[
      ('utm_content=%2Fitems%2F%25FF', '/items/%FF'),
      ('utm_content=%2Fitems%2F%25C3', '/items/%C3'),
      ('utm_content=%2Fitems%2F%25E2%2582', '/items/%E2%82'),
      ('utm_content=%2Fitems%2F%25', '/items/%'),
      ('utm_content=%2Fitems%2F%25ZZ', '/items/%ZZ'),
      ('utm_content=%2Fitems%2F%252', '/items/%2'),
      ('utm_content=%2Fitems%3Fq%3D%25FF', '/items?q=%FF'),
      ('utm_content=%2Fitems%23%25C3', '/items#%C3'),
    ];
    for (final (raw, value) in malformed) {
      test('"$value" -> null', () {
        final r = InstallReferrer(raw);
        expect(r['utm_content'], value);
        expect(r.deepLink(allow: allow), isNull);
        expect(InstallReferrer.resolveDeepLink(value, allow: allow), isNull);
      });
    }

    test('a valid multi-byte escape is still a link', () {
      final r = InstallReferrer('utm_content=%2Fitems%2F%25E2%2582%25AC');
      expect(r.deepLink(allow: allow).toString(), '/items/%E2%82%AC');
    });

    test('every %XX escape, in every part of the value', () {
      for (var byte = 0; byte < 256; byte++) {
        final escape = '%${byte.toRadixString(16).padLeft(2, '0')}';
        for (final value in [
          '/items/$escape',
          '/items/a${escape}b',
          '/items?q=$escape',
          '/items#$escape',
          '/$escape/x',
          'https://example.com/items/$escape',
        ]) {
          exercise('utm_content=${Uri.encodeQueryComponent(value)}');
          exercise('utm_content=$value');
          check(
            InstallReferrer.resolveDeepLink(value, allow: allow, hosts: hosts),
            value,
          );
        }
        exercise('a=$escape&utm_content=$escape');
        exercise(escape);
      }
    });

    test('every pair of %XX escapes in a path segment', () {
      // Covers truncated and overlong multi-byte sequences.
      for (var first = 0x80; first < 0x100; first += 3) {
        for (var second = 0; second < 0x100; second += 5) {
          final value =
              '/items/%${first.toRadixString(16)}'
              '%${second.toRadixString(16).padLeft(2, '0')}';
          check(InstallReferrer.resolveDeepLink(value, allow: allow), value);
        }
      }
    });

    test('random input', () {
      // Fixed seed: a failure is reproducible.
      final random = Random(28);
      const alphabet = [
        '%', '%2', '%25', '%2F', '%2f', '%FF', '%C3', '%E2%82', '%ZZ', '/',
        '//', '.', '..', '?', '#', '&', '=', '+', ' ', r'\', ':', '@', '[',
        ']', 'https:', 'utm_content=', 'example.com', 'items', 'a', '0', //
        '\u0000', '\n', '\u007f', 'é', '€', '\u{1F600}', '\uD800',
        '\uDC00',
      ];
      for (var i = 0; i < 5000; i++) {
        final buffer = StringBuffer();
        final length = random.nextInt(12);
        for (var j = 0; j < length; j++) {
          if (random.nextInt(8) == 0) {
            buffer.writeCharCode(random.nextInt(0x10000));
          } else {
            buffer.write(alphabet[random.nextInt(alphabet.length)]);
          }
        }
        final text = buffer.toString();
        exercise(text);
        exercise('utm_content=$text');
        exercise('utm_content=${Uri.encodeQueryComponent(text)}');
      }
    });
  });
}

/// Fails unless [link] is `null` or a relative link whose own decoders
/// (`pathSegments`, `queryParameters`, `toString`) work.
void check(Uri? link, String input) {
  if (link == null) return;
  expect(link.hasScheme, isFalse, reason: input);
  expect(link.path, startsWith('/'), reason: input);
  link.toString();
  for (final segment in link.pathSegments) {
    expect(segment == '.' || segment == '..', isFalse, reason: input);
  }
  link.queryParameters;
  Uri.decodeComponent(link.path);
  Uri.decodeComponent(link.fragment);
}
