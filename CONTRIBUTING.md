# Contributing

Issues and pull requests are welcome, especially device reports
("Play returned X on <OEM> Android N"), since referrer behaviour varies by
vendor and Play Store version.

Run the checks CI runs:

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
(cd example && flutter build apk --debug)
(cd example/android && ./gradlew :imaji_install_attribution:testDebugUnitTest)
```

Building the example **for iOS** has one quirk: Xcode resolves the plugin's
Swift package through its real path, and that package's identity is its
directory name. Clone into a folder named `imaji_install_attribution` (CI does
the same) or `xcodebuild` refuses to resolve packages with *"unable to
override package 'imaji_install_attribution'"*. Apps that depend on the
plugin are not affected.

The pure-Dart builder in `packages/imaji_referrer_builder` has its own CI job
(Dart 3.8.0 and stable):

```bash
cd packages/imaji_referrer_builder
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
dart run example/imaji_referrer_builder_example.dart
```

To see a real referrer on a device, follow [TESTING.md](TESTING.md).

## How changes land

Every change reaches `main` through a pull request that the maintainer
reviews and merges, including changes from forks. For anything larger than a
small fix, open an issue first so the approach can be agreed before you spend
time on it.

## Ground rules

- **No Kotlin Gradle Plugin.** The Android plugin uses AGP built-in Kotlin;
  CI fails if `android/build.gradle.kts` references KGP.
- **Shared vectors.** Parsing and building rules live in `test/vectors/*.json`
  and are read by both packages, so the plugin and the builder cannot drift
  apart. A change in behaviour is a change to the vectors.
- **Never throw on input.** Referrer and deep link parsing return a typed
  result for malformed strings; a fix comes with a vector for the string that
  broke it.
- **No real data.** Fixtures and examples use invented package names,
  campaigns and domains such as `com.example.app`.

## AI-assisted contributions

AI tools are fine to use; we just ask you to be open about it.

- Say in the PR description which AI tools you used, if any: none, some or
  most, plus the tool or agent and the model (for example "Claude Code,
  Opus 5.5" or "Copilot, GPT-5"). The pull request template has a box for it.
- Write the PR description and issues yourself, in your own words. Please
  don't paste generated text; short, plain descriptions are welcome.
- Read, run and test every line you submit, and be ready to explain it in
  review.
- Pull requests without the disclosure may be closed.

## Commits

One focused change per pull request. Commit subjects are a single line that
says what changed, either plain (`claimOnce(): one in-process claim ...`) or
with a type prefix (`docs: ...`, `fix: ...`). Add a `CHANGELOG.md` entry for
anything users of the package will notice. Releases follow
[RELEASING.md](RELEASING.md).

If this plugin saved you a day of chasing referrers, a star on the
repository helps other Flutter developers find it.
