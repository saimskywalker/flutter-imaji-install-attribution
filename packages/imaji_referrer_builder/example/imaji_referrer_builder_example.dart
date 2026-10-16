// A command-line link builder: prints the Play Store links for a few
// targets, as a redirect server or a campaign tool would build them.
import 'package:imaji_referrer_builder/imaji_referrer_builder.dart';

/// The campaign string as whoever runs campaigns configured it.
const campaign = 'utm_source=share&utm_medium=social&utm_campaign=spring';

/// The paths the app routes; the same list the app passes to `deepLink()`.
const allow = ['/invite/', '/items/'];

void main() {
  final targets = <(String, bool)>[
    ('/invite/abc123', true),
    ('/items/42?ref=campaign-42', true),
    ('/items/7', false), // hidden item: campaign-only link
  ];

  for (final (path, isPublic) in targets) {
    final referrer = PlayStoreUrl.appendPath(
      campaign,
      path,
      allow: allow,
      targetIsPublic: isPublic,
    );
    final url = PlayStoreUrl.webFromReferrer(
      packageName: 'com.example.app',
      referrer: referrer,
    );
    print('$path -> $url');
  }

  // A path the app would not route is refused before it reaches a link.
  print(PlayStoreUrl.checkPath('/admin', allow: allow)); // notAllowlisted
}
