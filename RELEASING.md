# Releasing and going public

The checklist for flipping the repository to public and publishing
`imaji_install_attribution` 0.1.0. Steps marked **(owner)** need repository
or pub.dev rights.

## 1. Before the repository goes public

- [x] Leak scan of the tree and the whole history. Both commands must print
      nothing:

      ```bash
      git grep -inE "<private terms>"
      git log -p | grep -inE "<private terms>"
      ```

      Keep the list of private terms (employer, product, people, hostnames,
      emails) outside the repository.
- [x] `dart pub publish --dry-run` reports 0 warnings (CI runs it on every
      push).
- [ ] `pana` reviewed locally: `dart pub global activate pana && pana .`
- [x] README: problem statement, quick start, migration guides, comparison
      table, FAQ. TESTING.md linked.
- [x] CHANGELOG has a 0.1.0 entry.
- [ ] **(owner)** Real-device check of a Play-installed build (internal app
      sharing or a testing track), following TESTING.md section 3. CI cannot
      do this: only a build that Google Play installed carries a referrer.
- [ ] **(owner)** Real-device check of the iOS token on a physical iPhone.

## 2. Going public

- [ ] **(owner)** Repository settings → *Change visibility* → Public.
- [ ] The `iOS (example build)` CI job starts running by itself (it is
      skipped while the repository is private, to save macOS minutes).
      Re-run CI once and confirm it is green.
- [ ] **(owner)** Branch protection on `main` (not available for private
      repositories on the free plan): require a pull request, 0 approvals,
      and these required status checks — the names must match the CI job
      names exactly:
  - `Dart (format, analyze, test)`
  - `Android (example build, Kotlin unit tests)`
  - `iOS (example build)`

## 3. Release v0.1.0

- [ ] Tag and push: `git tag v0.1.0 && git push origin v0.1.0`
- [ ] **(owner)** GitHub release from the tag, notes copied from
      CHANGELOG.md.
- [ ] **(owner)** `dart pub publish` (after one more `--dry-run`), then
      verify the pub.dev page: platforms Android + iOS, topics, score.
- [ ] Switch the README install snippet from the Git dependency to
      `imaji_install_attribution: ^0.1.0`.
