import 'package:flutter_test/flutter_test.dart';
import 'package:imaji_install_attribution/imaji_install_attribution.dart';

void main() {
  group('parameters', () {
    test('decodes each value exactly once', () {
      final r = InstallReferrer(
        'utm_source=news%20letter&utm_content=%2Fitems%2F42&q=a+b',
      );
      expect(r['utm_source'], 'news letter');
      expect(r['utm_content'], '/items/42');
      expect(r['q'], 'a b');
    });

    test('keeps an encoded slash that was encoded twice as one escape', () {
      // The path really is "/tags/a%2Fb"; it was encoded once more to sit
      // inside the referrer query string.
      final r = InstallReferrer('utm_content=%2Ftags%2Fa%252Fb');
      expect(r['utm_content'], '/tags/a%2Fb');
    });

    test('first occurrence wins, bare tokens and junk survive', () {
      final r = InstallReferrer('a=1&a=2&abc123&=x&&bad=%ZZ');
      expect(r['a'], '1');
      expect(r.parameters.containsKey('abc123'), isTrue);
      expect(r['abc123'], '');
      expect(r['bad'], '%ZZ');
      expect(r.parameters.containsKey(''), isFalse);
    });

    test('utm getters treat "(not set)" as absent', () {
      final r = InstallReferrer(
        'utm_source=(not%20set)&utm_medium=(not%20set)&utm_campaign=spring',
      );
      expect(r['utm_source'], '(not set)');
      expect(r.utmSource, isNull);
      expect(r.utmMedium, isNull);
      expect(r.utmCampaign, 'spring');
      expect(r.utmContent, isNull);
      expect(r.utmTerm, isNull);
    });
  });

  group('isOrganic', () {
    final cases = <String, bool>{
      '': true,
      'utm_source=google-play&utm_medium=organic': true,
      'utm_medium=organic&utm_source=google-play': true,
      'utm_source=(not%20set)&utm_medium=(not%20set)': true,
      'utm_source=&utm_medium=': true,
      'utm_source=google-play&utm_medium=organic&utm_content=%2Fitems%2F1':
          false,
      'utm_source=newsletter&utm_medium=email': false,
      'utm_source=google-play&utm_medium=cpc': false,
      'gclid=abc': false,
      'custom_id=8': false,
      'abc123': false,
      'utm_source=(not%20set)&custom_id=8': false,
    };
    cases.forEach((raw, organic) {
      test('"$raw" -> ${organic ? 'organic' : 'attributed'}', () {
        expect(InstallReferrer(raw).isOrganic, organic);
      });
    });
  });

  group('deepLink', () {
    const allow = ['/items/', '/profile'];

    // (description, raw referrer, expected link or null)
    final table = <(String, String, String?)>[
      ('single-encoded path', 'utm_content=%2Fitems%2F42', '/items/42'),
      ('unencoded path', 'utm_content=/items/42', '/items/42'),
      (
        'double-encoded escape stays one escape',
        'utm_content=%2Fitems%2Fa%252Fb',
        '/items/a%2Fb',
      ),
      (
        'query and fragment are kept',
        'utm_content=%2Fitems%2F42%3Fref%3Dmail%23top',
        '/items/42?ref=mail#top',
      ),
      ('prefix itself', 'utm_content=%2Fprofile', '/profile'),
      ('below prefix', 'utm_content=%2Fprofile%2Fme', '/profile/me'),
      ('missing key', 'utm_source=newsletter', null),
      ('empty value', 'utm_content=', null),
      ('(not set) value', 'utm_content=(not%20set)', null),
      ('outside the allowlist', 'utm_content=%2Fadmin', null),
      ('prefix lookalike', 'utm_content=%2Fprofiles', null),
      ('relative path', 'utm_content=items%2F42', null),
      (
        'foreign host',
        'utm_content=https%3A%2F%2Fevil.example%2Fitems%2F1',
        null,
      ),
      ('protocol-relative', 'utm_content=%2F%2Fevil.example%2Fitems%2F1', null),
      ('custom scheme', 'utm_content=intent%3A%2F%2Fitems%2F1', null),
      ('dot-dot segment', 'utm_content=%2Fitems%2F..%2Fadmin', null),
      ('encoded dot-dot', 'utm_content=%2Fitems%2F%252e%252e%2Fadmin', null),
      ('backslash', 'utm_content=%2Fitems%5C..%5Cadmin', null),
      ('control character', 'utm_content=%2Fitems%2F1%0A', '/items/1'),
      ('control character inside', 'utm_content=%2Fitems%0A%2F1', null),
    ];

    for (final (name, raw, expected) in table) {
      test(name, () {
        final link = InstallReferrer(raw).deepLink(allow: allow);
        expect(link?.toString(), expected);
      });
    }

    test('custom key', () {
      final r = InstallReferrer('link=%2Fitems%2F9');
      expect(r.deepLink(key: 'link', allow: allow).toString(), '/items/9');
    });

    test('an allowlisted https host yields its path only', () {
      final r = InstallReferrer(
        'utm_content=https%3A%2F%2Fexample.com%2Fitems%2F5%3Fx%3D1',
      );
      expect(
        r.deepLink(allow: allow, hosts: ['Example.com']).toString(),
        '/items/5?x=1',
      );
      expect(r.deepLink(allow: allow), isNull);
    });

    test(
      'an allowlisted host over http, with a port or userinfo is refused',
      () {
        for (final value in [
          'http://example.com/items/5',
          'https://example.com:8443/items/5',
          'https://user@example.com/items/5',
        ]) {
          expect(
            InstallReferrer.resolveDeepLink(
              value,
              allow: allow,
              hosts: ['example.com'],
            ),
            isNull,
            reason: value,
          );
        }
      },
    );

    test('an empty allowlist refuses everything', () {
      expect(
        InstallReferrer('utm_content=%2Fitems%2F1').deepLink(allow: const []),
        isNull,
      );
    });
  });

  group('PlayStoreUrl', () {
    const package = 'com.example.app';
    const referrer = {
      'utm_source': 'newsletter',
      'utm_content': '/items/a%2Fb',
    };

    /// What Play does: take the `referrer` parameter and decode it once.
    String asPlayReturnsIt(Uri url) => url.queryParameters['referrer']!;

    test('round-trips through Play and the deep-link helper', () {
      final url = PlayStoreUrl.web(packageName: package, referrer: referrer);
      final received = InstallReferrer(asPlayReturnsIt(url));
      expect(received['utm_source'], 'newsletter');
      expect(received['utm_content'], '/items/a%2Fb');
      expect(received.deepLink(allow: ['/items/']).toString(), '/items/a%2Fb');
    });

    test('encodes the referrer once as the outer parameter', () {
      final url = PlayStoreUrl.web(
        packageName: package,
        referrer: const {'utm_source': 'a', 'utm_content': '/items/1'},
      );
      expect(
        url.toString(),
        'https://play.google.com/store/apps/details?id=com.example.app'
        '&referrer=utm_source%3Da%26utm_content%3D%252Fitems%252F1',
      );
    });

    test('market links carry the same referrer', () {
      final web = PlayStoreUrl.web(packageName: package, referrer: referrer);
      final market = PlayStoreUrl.market(
        packageName: package,
        referrer: referrer,
      );
      expect(market.scheme, 'market');
      expect(market.host, 'details');
      expect(
        market.queryParameters['referrer'],
        web.queryParameters['referrer'],
      );
    });

    test('no referrer, no parameter', () {
      final url = PlayStoreUrl.web(packageName: package, referrer: const {});
      expect(url.queryParameters.containsKey('referrer'), isFalse);
    });
  });
}
