# flutter-imaji-install-attribution

[![CI](https://github.com/saimskywalker/flutter-imaji-install-attribution/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/saimskywalker/flutter-imaji-install-attribution/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/github/license/saimskywalker/flutter-imaji-install-attribution)](LICENSE)

Install attribution and deferred deep links for Flutter apps, in two
packages that share one set of test vectors.

| Package | pub.dev | What it is |
|---|---|---|
| [`imaji_install_attribution`](packages/imaji_install_attribution) | [![pub](https://img.shields.io/pub/v/imaji_install_attribution)](https://pub.dev/packages/imaji_install_attribution) | Flutter plugin: reads the Play Install Referrer (Android) and the Apple AdServices token (iOS) and turns it into the deep link the user wanted |
| [`imaji_referrer_builder`](packages/imaji_referrer_builder) | [![pub](https://img.shields.io/pub/v/imaji_referrer_builder)](https://pub.dev/packages/imaji_referrer_builder) | Pure Dart, no dependencies: builds the referrer strings and Play Store URLs on a server |

Start with the plugin's [README](packages/imaji_install_attribution/README.md).
The parsing and building rules are pinned by the JSON vectors in
[`packages/imaji_install_attribution/test/vectors`](packages/imaji_install_attribution/test/vectors),
which both packages' tests read.

[Contributing](CONTRIBUTING.md) · [Releasing](RELEASING.md) ·
[Security](SECURITY.md) · [Code of conduct](CODE_OF_CONDUCT.md)

## License

MIT © saimskywalker. See [LICENSE](LICENSE).
