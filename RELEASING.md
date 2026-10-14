# Releasing

The checklist for every release of `imaji_install_attribution`. Copy it into
the release pull request and tick it there. Steps marked **(owner)** need
repository or pub.dev rights.

Versioning follows [semver](https://semver.org): a patch for fixes and
documentation, a minor for features while the package is `0.x`.

## 1. In the release pull request

- [ ] The version is the same in all three places:
  - `pubspec.yaml` → `version:`
  - `android/build.gradle.kts` → `version =`
  - `ios/imaji_install_attribution.podspec` → `s.version`
- [ ] `CHANGELOG.md` has a `## <version>` entry at the top, written for
      users of the package.
- [ ] README and TESTING.md describe the new behaviour; any version
      constraint shown in them (`^0.x.y`) still admits the new version.
- [ ] Leak scan of the change. Both commands must print nothing:

      ```bash
      git grep -inE "<private terms>"
      git log -p origin/main..HEAD | grep -inE "<private terms>"
      ```

      Keep the list of private terms (employer, product, people, hostnames,
      emails) outside the repository.
- [ ] `dart pub publish --dry-run` reports 0 warnings (CI runs it on every
      push).
- [ ] CI is green: `Dart (format, analyze, test)`,
      `Android (example build, Kotlin unit tests)` and `iOS (example build)`.
- [ ] Optional: `dart pub global activate pana && pana .` scores 160/160.

## 2. After the pull request is merged

- [ ] Tag the merge commit on `main` and push the tag:
      `git tag v<version> && git push origin v<version>`
- [ ] **(owner)** GitHub release from the tag, notes copied from
      `CHANGELOG.md`.
- [ ] **(owner)** `dart pub publish` from the tagged commit (after one more
      `--dry-run`).
- [ ] Check the pub.dev page: the new version is listed, platforms Android
      and iOS, topics, 160/160 points, and the README badges and links
      render (relative links resolve to `blob/main` on GitHub).

## 3. When the release changes native code

- [ ] **(owner)** Real-device check of a Play-installed build (internal app
      sharing or a testing track), following TESTING.md section 3. CI cannot
      do this: only a build that Google Play installed carries a referrer.
- [ ] **(owner)** Real-device check of the iOS token on a physical iPhone.

## Repository settings (one-off, kept for reference)

- [x] Repository public; the `iOS (example build)` job runs on every push.
- [x] `v0.1.0` tagged, released on GitHub and published to pub.dev
      (2026-10-14).
- [ ] **(owner)** Branch protection on `main` requires a pull request and
      these status checks — the names must match the CI job names exactly.
      Today only the first two are required:
  - `Dart (format, analyze, test)`
  - `Android (example build, Kotlin unit tests)`
  - `iOS (example build)`
