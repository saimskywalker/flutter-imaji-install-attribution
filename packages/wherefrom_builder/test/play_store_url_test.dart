import 'package:imaji_referrer_builder/imaji_referrer_builder.dart';
import 'package:test/test.dart';

const _package = 'com.example.app';
const _allow = ['/invite/', '/items/'];
const _campaign = 'utm_source=share&utm_medium=social&utm_campaign=spring';

/// What Play does with the store URL: take the `referrer` parameter and
/// decode it once.
String _asPlayReturnsIt(Uri url) => url.queryParameters['referrer']!;

void main() {
  group('appendPath', () {
    test('appends one key to the configured campaign, encoded once', () {
      expect(
        PlayStoreUrl.appendPath(_campaign, '/invite/abc123', allow: _allow),
        '$_campaign&utm_content=%2Finvite%2Fabc123',
      );
    });

    test('an empty campaign gives the path alone', () {
      expect(
        PlayStoreUrl.appendPath('', '/invite/abc123', allow: _allow),
        'utm_content=%2Finvite%2Fabc123',
      );
    });

    test('no path returns the campaign unchanged', () {
      expect(
        PlayStoreUrl.appendPath(_campaign, null, allow: _allow),
        _campaign,
      );
      expect(PlayStoreUrl.appendPath('', null, allow: _allow), '');
    });

    test('a target that is not public carries no path', () {
      expect(
        PlayStoreUrl.appendPath(
          _campaign,
          '/items/7',
          allow: _allow,
          targetIsPublic: false,
        ),
        _campaign,
      );
      // Not even validated: a hidden item's path never reaches the output.
      expect(
        PlayStoreUrl.appendPath(
          '',
          '/hidden/7',
          allow: _allow,
          targetIsPublic: false,
        ),
        '',
      );
    });

    test('keeps a + in the campaign as a +, byte for byte', () {
      const campaign = 'utm_campaign=spring+sale';
      final referrer = PlayStoreUrl.appendPath(
        campaign,
        '/items/1',
        allow: _allow,
      );
      expect(referrer, 'utm_campaign=spring+sale&utm_content=%2Fitems%2F1');
    });

    test('keeps a %20 in the campaign as %20, byte for byte', () {
      const campaign = 'utm_campaign=spring%20sale';
      final referrer = PlayStoreUrl.appendPath(
        campaign,
        '/items/1',
        allow: _allow,
      );
      expect(referrer, 'utm_campaign=spring%20sale&utm_content=%2Fitems%2F1');
    });

    test('keeps key order and a repeated campaign key exactly as given', () {
      const campaign = 'b=2&a=1&a=3&flag';
      expect(
        PlayStoreUrl.appendPath(campaign, '/items/1', allow: _allow),
        'b=2&a=1&a=3&flag&utm_content=%2Fitems%2F1',
      );
    });

    test('a campaign ending with & gets no second &', () {
      expect(
        PlayStoreUrl.appendPath('utm_source=share&', '/items/1', allow: _allow),
        'utm_source=share&utm_content=%2Fitems%2F1',
      );
    });

    test('a literal + in the path is encoded, a space becomes +', () {
      expect(
        PlayStoreUrl.appendPath('', '/items/a+b', allow: _allow),
        'utm_content=%2Fitems%2Fa%2Bb',
      );
      expect(
        PlayStoreUrl.appendPath('', '/items/a b', allow: _allow),
        'utm_content=%2Fitems%2Fa+b',
      );
    });

    test('a percent sign in the path is encoded once, never twice', () {
      expect(
        PlayStoreUrl.appendPath('', '/items/a%2Fb', allow: _allow),
        'utm_content=%2Fitems%2Fa%252Fb',
      );
    });

    test('a custom key', () {
      expect(
        PlayStoreUrl.appendPath(
          'utm_source=share',
          '/items/1',
          allow: _allow,
          key: 'link',
        ),
        'utm_source=share&link=%2Fitems%2F1',
      );
    });

    group('refuses', () {
      test('a path outside the allowlist', () {
        expect(
          () => PlayStoreUrl.appendPath(_campaign, '/admin', allow: _allow),
          throwsA(
            isA<ArgumentError>()
                .having((e) => e.name, 'name', 'path')
                .having(
                  (e) => e.message,
                  'message',
                  contains('notAllowlisted'),
                ),
          ),
        );
      });

      test('every path with an empty allowlist', () {
        expect(
          () => PlayStoreUrl.appendPath('', '/items/1', allow: const []),
          throwsArgumentError,
        );
      });

      test('a campaign that already holds the key', () {
        expect(
          () => PlayStoreUrl.appendPath(
            'utm_source=share&utm_content=spring',
            '/items/1',
            allow: _allow,
          ),
          throwsA(
            isA<ArgumentError>()
                .having((e) => e.name, 'name', 'campaign')
                .having((e) => e.message, 'message', contains('first')),
          ),
        );
      });

      test('a campaign that holds the key encoded, or as a bare token', () {
        for (final campaign in ['utm%5Fcontent=x', 'a=1&utm_content']) {
          expect(
            () => PlayStoreUrl.appendPath(campaign, '/items/1', allow: _allow),
            throwsArgumentError,
            reason: campaign,
          );
        }
      });

      test('a campaign holding the key even when no path is appended', () {
        expect(
          () => PlayStoreUrl.appendPath(
            'utm_content=spring',
            null,
            allow: _allow,
          ),
          throwsArgumentError,
        );
      });

      test('a campaign with a custom key already in it', () {
        expect(
          () => PlayStoreUrl.appendPath(
            'link=x&utm_content=y',
            '/items/1',
            allow: _allow,
            key: 'link',
          ),
          throwsArgumentError,
        );
        // utm_content is just another campaign key when the key is custom.
        expect(
          PlayStoreUrl.appendPath(
            'utm_content=y',
            '/items/1',
            allow: _allow,
            key: 'link',
          ),
          'utm_content=y&link=%2Fitems%2F1',
        );
      });

      test("a campaign that starts with '?'", () {
        expect(
          () => PlayStoreUrl.appendPath(
            '?utm_source=share',
            '/items/1',
            allow: _allow,
          ),
          throwsArgumentError,
        );
      });

      test('an empty key', () {
        expect(
          () => PlayStoreUrl.appendPath('', '/items/1', allow: _allow, key: ''),
          throwsArgumentError,
        );
      });
    });
  });

  group('checkPath', () {
    final cases = <String, PathRefusal?>{
      '/invite/abc123': null,
      '/items': null,
      '/items/42?ref=campaign-42#top': null,
      'https://example.com/items/5': null,
      '': PathRefusal.empty,
      '   ': PathRefusal.empty,
      ' /items/1': PathRefusal.surroundingWhitespace,
      '/items/1\n': PathRefusal.surroundingWhitespace,
      r'/items\1': PathRefusal.forbiddenCharacter,
      '/items\u0000/1': PathRefusal.forbiddenCharacter,
      '/items\u007f/1': PathRefusal.forbiddenCharacter,
      'items/1': PathRefusal.notAPath,
      'https://evil.example/items/1': PathRefusal.hostNotAllowed,
      'http://example.com/items/1': PathRefusal.hostNotAllowed,
      'https://example.com:8443/items/1': PathRefusal.hostNotAllowed,
      'https://user@example.com/items/1': PathRefusal.hostNotAllowed,
      '//example.com/items/1': PathRefusal.hostNotAllowed,
      'intent://items/1': PathRefusal.hostNotAllowed,
      '/items/../admin': PathRefusal.unsafe,
      '/items/./1': PathRefusal.unsafe,
      '/items/%2e%2e/admin': PathRefusal.unsafe,
      '/items/%2E/1': PathRefusal.unsafe,
      'https://example.com/items/../admin': PathRefusal.unsafe,
      '/admin': PathRefusal.notAllowlisted,
      '/itemsX': PathRefusal.notAllowlisted,
      '/invite': null, // the base of the /invite/ prefix is allowed too
    };
    cases.forEach((path, expected) {
      test('${Uri.encodeComponent(path)} -> ${expected?.name ?? 'ok'}', () {
        expect(
          PlayStoreUrl.checkPath(path, allow: _allow, hosts: ['Example.com']),
          expected,
        );
      });
    });

    test('a prefix that does not start with / allows nothing', () {
      expect(
        PlayStoreUrl.checkPath('/items/1', allow: ['items']),
        PathRefusal.notAllowlisted,
      );
    });

    test('the / prefix allows every safe path', () {
      expect(PlayStoreUrl.checkPath('/anything/1', allow: ['/']), isNull);
      expect(
        PlayStoreUrl.checkPath('/a/../b', allow: ['/']),
        PathRefusal.unsafe,
      );
    });
  });

  group('expectedDeepLink', () {
    test('is what the app will route', () {
      expect(
        PlayStoreUrl.expectedDeepLink('/items/a b', allow: _allow).toString(),
        '/items/a%20b',
      );
      expect(
        PlayStoreUrl.expectedDeepLink(
          'https://example.com/items/5?x=1',
          allow: _allow,
          hosts: ['example.com'],
        ).toString(),
        '/items/5?x=1',
      );
      expect(PlayStoreUrl.expectedDeepLink('/admin', allow: _allow), isNull);
    });
  });

  group('store links', () {
    test('webFromReferrer encodes the referrer once as the parameter', () {
      final referrer = PlayStoreUrl.appendPath(
        'utm_source=a',
        '/items/1',
        allow: _allow,
      );
      final url = PlayStoreUrl.webFromReferrer(
        packageName: _package,
        referrer: referrer,
      );
      expect(
        url.toString(),
        'https://play.google.com/store/apps/details?id=com.example.app'
        '&referrer=utm_source%3Da%26utm_content%3D%252Fitems%252F1',
      );
      expect(_asPlayReturnsIt(url), referrer);
      expect(
        Uri.splitQueryString(_asPlayReturnsIt(url))['utm_content'],
        '/items/1',
      );
    });

    test('marketFromReferrer carries the same parameter', () {
      final referrer = PlayStoreUrl.appendPath(
        _campaign,
        '/invite/abc123',
        allow: _allow,
      );
      final web = PlayStoreUrl.webFromReferrer(
        packageName: _package,
        referrer: referrer,
      );
      final market = PlayStoreUrl.marketFromReferrer(
        packageName: _package,
        referrer: referrer,
      );
      expect(market.scheme, 'market');
      expect(market.host, 'details');
      expect(market.queryParameters['id'], _package);
      expect(market.query, web.query);
    });

    test('an empty referrer adds no parameter', () {
      for (final url in [
        PlayStoreUrl.webFromReferrer(packageName: _package, referrer: ''),
        PlayStoreUrl.marketFromReferrer(packageName: _package, referrer: ''),
        PlayStoreUrl.web(packageName: _package, referrer: const {}),
        PlayStoreUrl.market(packageName: _package, referrer: const {}),
      ]) {
        expect(url.queryParameters.keys, ['id'], reason: '$url');
      }
    });

    test('the map form matches the Flutter plugin byte for byte', () {
      // The literal pinned by the plugin's own PlayStoreUrl test.
      final url = PlayStoreUrl.web(
        packageName: _package,
        referrer: const {'utm_source': 'a', 'utm_content': '/items/1'},
      );
      expect(
        url.toString(),
        'https://play.google.com/store/apps/details?id=com.example.app'
        '&referrer=utm_source%3Da%26utm_content%3D%252Fitems%252F1',
      );
      expect(
        PlayStoreUrl.encodeReferrer(const {
          'utm_source': 'newsletter',
          'utm_content': '/items/a%2Fb',
        }),
        'utm_source=newsletter&utm_content=%2Fitems%2Fa%252Fb',
      );
    });
  });
}
