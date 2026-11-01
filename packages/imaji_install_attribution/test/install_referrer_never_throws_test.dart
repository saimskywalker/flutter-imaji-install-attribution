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
    check(r.deepLinkResult(allow: allow, hosts: hosts).uriOrNull, raw);
    final rfc = r.withDecoding(ReferrerDecoding.rfc3986);
    rfc.parameters;
    rfc.isOrganic;
    check(rfc.deepLink(allow: allow, hosts: hosts), raw);
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

    test('unescaped non-ASCII text is still a link', () {
      // A builder that encodes the path once gives `/items/café` after
      // Play's and the parameter decode; it must not be mistaken for a bad
      // escape.
      for (final (raw, link) in [
        ('utm_content=%2Fitems%2Fcaf%C3%A9', '/items/caf%C3%A9'),
        (
          'utm_content=%2Fitems%2F%E2%82%AC%3Fq%3D%C3%A9',
          '/items/%E2%82%AC?q=%C3%A9',
        ),
        ('utm_content=%2Fitems%2F%F0%9F%98%80', '/items/%F0%9F%98%80'),
        ('utm_content=%2Fitems%2Fcaf%C3%A9%2F%25FF', null),
      ]) {
        expect(
          InstallReferrer(raw).deepLink(allow: allow)?.toString(),
          link,
          reason: raw,
        );
      }
      // A lone surrogate is not text: refused, not encoded into a link.
      for (final value in ['/items/\uD800', '/items?q=\uDC00', '/\uD83D/x']) {
        expect(
          InstallReferrer.resolveDeepLink(value, allow: allow),
          isNull,
          reason: value,
        );
      }
    });

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

    test('values without a percent sign resolve exactly as in 0.1.1', () {
      // #28 changed only how escapes are judged. A differential check
      // against the 0.1.1 algorithm keeps it from refusing anything else
      // (it once refused unescaped non-ASCII text).
      final random = Random(2801);
      const alphabet = [
        '/', '//', '.', '..', '?', '#', '&', '=', '+', ' ', ':', '@', //
        'https:', 'example.com', 'items', 'a', '0', '\u00e9', '\u20ac',
        '\u{1F600}', '[', ']', '~', '!', r'$', "'", '(', ')', '*', ',', ';',
      ];
      for (var i = 0; i < 5000; i++) {
        final buffer = StringBuffer(random.nextBool() ? '/' : '');
        final length = random.nextInt(10);
        for (var j = 0; j < length; j++) {
          buffer.write(alphabet[random.nextInt(alphabet.length)]);
        }
        final value = buffer.toString();
        expect(
          InstallReferrer.resolveDeepLink(
            value,
            allow: allow,
            hosts: hosts,
          )?.toString(),
          // 0.2.0 refuses `.`/`..` segments as written; 0.1.1 let
          // `Uri.parse` normalise them away first.
          hasDotSegment(value)
              ? null
              : legacyResolve(value, allow, hosts)?.toString(),
          reason: value,
        );
      }
    });
  });
}

/// Whether [value], before any `?` or `#`, has a `.` or `..` segment.
bool hasDotSegment(String value) {
  final end = value.indexOf(RegExp('[?#]'));
  return (end < 0 ? value : value.substring(0, end))
      .trim()
      .split('/')
      .any((segment) => segment == '.' || segment == '..');
}

/// `resolveDeepLink` exactly as 0.1.1 shipped it, for the differential test.
/// Only called with values that contain no `%`, where it cannot throw.
Uri? legacyResolve(String value, List<String> allow, List<String> hosts) {
  final text = value.trim();
  if (text.isEmpty || text.contains(r'\')) return null;
  if (text.codeUnits.any((c) => c < 0x20 || c == 0x7f)) return null;
  final Uri uri;
  try {
    uri = Uri.parse(text);
  } on FormatException {
    return null;
  }
  if (uri.hasScheme || text.startsWith('//')) {
    final allowedHosts = {for (final h in hosts) h.toLowerCase()};
    final ok =
        uri.scheme == 'https' &&
        uri.hasAuthority &&
        uri.userInfo.isEmpty &&
        !uri.hasPort &&
        allowedHosts.contains(uri.host.toLowerCase());
    if (!ok) return null;
  } else if (!text.startsWith('/')) {
    return null;
  }
  final path = uri.path;
  if (!path.startsWith('/') || path.startsWith('//')) return null;
  for (final segment in path.split('/')) {
    final decoded = Uri.decodeComponent(segment);
    if (decoded == '.' || decoded == '..') return null;
  }
  bool matches(String prefix) {
    if (!prefix.startsWith('/')) return false;
    if (prefix == '/') return true;
    final base = prefix.endsWith('/')
        ? prefix.substring(0, prefix.length - 1)
        : prefix;
    return path == base || path.startsWith('$base/');
  }

  if (!allow.any(matches)) return null;
  return Uri(
    path: path,
    query: uri.hasQuery ? uri.query : null,
    fragment: uri.hasFragment ? uri.fragment : null,
  );
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
