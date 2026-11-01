# Contributing

Issues and pull requests are welcome, especially device reports
("Play returned X on <OEM> Android N"), since referrer behaviour varies by
vendor and Play Store version.

The repository holds two packages: the Flutter plugin in
`packages/imaji_install_attribution` and the pure-Dart builder in
`packages/imaji_referrer_builder`. Run the checks CI runs for the plugin:

```bash
cd packages/imaji_install_attribution
dart format --set-exit-if-changed .
flutter analyze
flutter test
(cd example && flutter build apk --debug)
(cd example/android && ./gradlew :imaji_install_attribution:testDebugUnitTest)
(cd example && flutter build ios --simulator --debug --no-codesign)
```

CI also builds release versions. To run the Android checks locally (from the
repository root, with an emulator running for the last one):

```bash
(cd packages/imaji_install_attribution/example && flutter build appbundle --release && flutter build apk --release)
python3 .github/scripts/merged_manifest_snapshot.py   # --update to accept a manifest change
python3 .github/scripts/check_native_libs.py packages/imaji_install_attribution/example/build/app/outputs/bundle/release/app-release.aab
.github/scripts/android_release_smoke.sh packages/imaji_install_attribution/example/build/app/outputs/flutter-apk/app-release.apk
```

and on iOS:

```bash
(cd packages/imaji_install_attribution/example && flutter build ios --release --no-codesign)
.github/scripts/check_ios_privacy_manifest.sh packages/imaji_install_attribution/example/build/ios/iphoneos/Runner.app
```

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

To see a real referrer on a device, follow
[TESTING.md](packages/imaji_install_attribution/TESTING.md).

## How changes land

Every change reaches `main` through a pull request that the maintainer
reviews and merges, including changes from forks. For anything larger than a
small fix, open an issue first so the approach can be agreed before you spend
time on it.

## Ground rules

- **No Kotlin Gradle Plugin.** The Android plugin uses AGP built-in Kotlin;
  CI fails if the plugin's `android/build.gradle.kts` references KGP.
- **Shared vectors.** Parsing and building rules live in
  `packages/imaji_install_attribution/test/vectors/*.json` and are read by
  both packages, so the plugin and the builder cannot drift apart. A change
  in behaviour is a change to the vectors.
- **Never throw on input.** Referrer and deep link parsing return a typed
  result for malformed strings; a fix comes with a vector for the string that
  broke it.
- **No real data.** Fixtures and examples use invented package names,
  campaigns and domains such as `com.example.app`.

## AI-assisted contributions

Using AI tools is fine; please just be open about it.

- Say in the PR description which AI tools you used, if any: none, some or
  most, plus the tool or agent and the model (for example "Claude Code,
  Opus 5.5" or "Copilot, GPT-5").
- Write the PR description and any issues yourself, in your own words. Short,
  plain descriptions are welcome; please don't paste generated text.
- Read, run and test every line you submit, and be ready to explain it in
  review.
- PRs without the disclosure may be closed.

## Commits

One focused change per pull request. Commit subjects are a single line that
says what changed, either plain (`claimOnce(): one in-process claim ...`) or
with a type prefix (`docs: ...`, `fix: ...`). Add an entry to the package's
`CHANGELOG.md` for anything its users will notice. Releases follow
[RELEASING.md](RELEASING.md).

If this plugin saved you a day of chasing referrers, a star on the
repository helps other Flutter developers find it.
