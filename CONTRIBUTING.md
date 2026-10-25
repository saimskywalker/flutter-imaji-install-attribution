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

If this plugin saved you a day of chasing referrers, a star on the
repository helps other Flutter developers find it.
