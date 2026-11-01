# wherefrom

[![CI](https://github.com/saimskywalker/wherefrom/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/saimskywalker/wherefrom/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/github/license/saimskywalker/wherefrom)](LICENSE)

Install attribution and deferred deep links for Flutter apps, in two
packages that share one set of test vectors.

| Package | pub.dev | What it is |
|---|---|---|
| [`wherefrom`](packages/wherefrom) | [![pub](https://img.shields.io/pub/v/wherefrom)](https://pub.dev/packages/wherefrom) | Flutter plugin: reads the Play Install Referrer (Android) and the Apple AdServices token (iOS) and turns it into the deep link the user wanted |
| [`wherefrom_builder`](packages/wherefrom_builder) | [![pub](https://img.shields.io/pub/v/wherefrom_builder)](https://pub.dev/packages/wherefrom_builder) | Pure Dart, no dependencies: builds the referrer strings and Play Store URLs on a server |

The packages were called `imaji_install_attribution` and
`imaji_referrer_builder` before 0.3.0 and 0.2.0.

Start with the plugin's [README](packages/wherefrom/README.md).
The parsing and building rules are pinned by the JSON vectors in
[`packages/wherefrom/test/vectors`](packages/wherefrom/test/vectors),
which both packages' tests read.

[Contributing](CONTRIBUTING.md) · [Releasing](RELEASING.md) ·
[Security](SECURITY.md) · [Code of conduct](CODE_OF_CONDUCT.md)

## License

MIT © saimskywalker. See [LICENSE](LICENSE).
