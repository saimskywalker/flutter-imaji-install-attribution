# Consume once, on the first launch only

Play keeps returning the same referrer for 90 days, and a failing read can
be retried on every launch. `readOnce()` and `claimOnce()` make sure a
referrer is acted on once, on the first launch after install.

## `readOnce()`

`readOnce()` returns `null` after `markHandled()`. Nothing is marked
automatically, so a crash between reading and routing does not lose the
link. The marker is a tiny file excluded from backups (`noBackupFilesDir` on
Android, an excluded file in Application Support on iOS): an uninstall and
reinstall starts unhandled again, which matches Play, since a reinstall gets
a fresh referrer. `isHandled()` and `clearHandled()` exist for debug menus.

Google's guidance is to act on the referrer only on the first execution
after install. Play keeps returning the same referrer for 90 days, so
"unhandled" alone is not enough. `readOnce()` has three options for that.
Each one that applies marks the install handled and returns `null`, and
`InstallAttribution.lastSkipReason` (a `ReadOnceSkip`) says why. `claimOnce()`
takes the same options. A suppressed referrer is silent: nothing is
returned, so nothing can route or show a banner about it.

| Option | Default | What it does |
|---|---|---|
| `treatUpgradesAsHandled` | `true` | An install that existed before the plugin is handled. That is an app updated since it was installed, where the plugin first ran after that update. Android only; it needs no Play Store call. |
| `maxClickAge` | `null` (no limit) | A Play click older than this is handled. Uses Play's server clock (`clickedAtServer`) when reported, else `clickedAt`; an unknown click time is never stale. Pick the window your links are meant for, such as an invite's validity. |
| `pastInstallFlow` | `null` | Your own "this user is past the install flow" check, asked before Play. See [the recipe](#route-only-while-the-user-is-still-in-the-install-flow). |

```dart
final result = await InstallAttribution.readOnce(
  maxClickAge: const Duration(days: 7), // your link's lifetime
  pastInstallFlow: () => session.isSignedIn && firstRunDoneOnThisDevice,
);
```

**How upgrades are detected (Android).** The plugin records the first time
it starts on an install, in `noBackupFilesDir`. `readOnce()` treats the
install as an upgrade when two conditions both hold:

- `PackageInfo.lastUpdateTime` is more than a minute after
  `firstInstallTime`, so the app has been updated since it was installed.
- The plugin's first start came after that update.

A fresh install is never affected, and neither is an install that had
0.2.0 or later from day one. Unknown facts never count as an upgrade.

Two known limits:

- **An install that started on 0.1.x** counts as adopted in an update on
  its first 0.2.0 launch, and is marked handled. 0.1.x kept no first-seen
  record, so the record is written after the update that brought 0.2.0.
  That install already had its first launch under 0.1.x. Pass
  `treatUpgradesAsHandled: false` if an app on 0.1.x still needs that
  install's referrer.
- An app installed from a link, never opened, and auto-updated before its
  first launch counts as an upgrade, so its link is skipped. Its click is
  at least as old as that update anyway.

Pass `treatUpgradesAsHandled: false` to keep the 0.1 behaviour.

**iOS.** There is no referrer to protect, so `treatUpgradesAsHandled` and
`maxClickAge` are no-ops (the AdServices token carries no click time).
`pastInstallFlow` is app state and applies on both platforms.

## Route only while the user is still in the install flow

A deferred link belongs to the install, sign-up and first-run flow. A
reliable "past the install flow" check needs **both** halves:

1. **Signed in.** Signed in alone is wrong: a reinstall that restores a
   session (an account manager, a credential restore, a server that
   remembers the device) is still a first run, and its link should route.
2. **The first run already completed on this device.** Keep this flag out
   of backups. Android Auto Backup and device-to-device transfer restore
   `SharedPreferences` by default. A reinstall would then inherit "first
   run done" and spend the link silently. Keep the flag in a file under
   `noBackupFilesDir`, or exclude its preferences file from backup:

```xml
<!-- res/xml/data_extraction_rules.xml (Android 12+), referenced from
     android:dataExtractionRules; mirror it in android:fullBackupContent
     for Android 11 and lower. -->
<data-extraction-rules>
  <cloud-backup>
    <exclude domain="sharedpref" path="first_run.xml"/>
  </cloud-backup>
  <device-transfer>
    <exclude domain="sharedpref" path="first_run.xml"/>
  </device-transfer>
</data-extraction-rules>
```

```dart
final result = await InstallAttribution.readOnce(
  pastInstallFlow: () async =>
      await auth.isSignedIn() && await firstRun.completedOnThisDevice(),
);
```

If the check throws, `readOnce()` returns `null` without marking anything,
and the next launch asks again.

## `claimOnce()`: one claim, a retry budget

`claimOnce()` is `readOnce()` with three guarantees for apps that have more
than one startup path:

- **One claim per process.** While a claim is held, every other
  `claimOnce()` in the process returns `null` (`claimedElsewhere`). A link
  cannot be dispatched twice by a first-frame callback and a later "router
  ready" path. The lock is taken before the first `await`.
  `claim.complete()` marks the install handled. `claim.release()` leaves it
  unhandled, for when the link did not land (no router, or a newer tapped
  link took precedence). The next launch, or a later `claimOnce()`, then
  tries again.
- **A retry budget across launches.** A failed read returns `null`
  (`readFailed`, details in `lastFailure`). The failure is counted in a file
  next to the handled marker, which survives process death, is excluded
  from backups and is cleared by `clearHandled()`. After `maxFailedReads`
  failures the install is marked handled (`budgetSpent`), and no later
  launch binds to the Play Store again.
- **Terminal reasons** in `terminal` mark the install handled on first sight
  (`terminalFailure`).

| Parameter | Default | Why |
|---|---|---|
| `maxFailedReads` | `3` | A failed Android read costs a service bind and up to the timeout (10 s) of background work, on every launch, forever. Three launches separate a transient failure (Play updating itself, a busy device) from a device that cannot answer. Raise it if first launches are often offline. |
| `terminal` | `{playStoreMissing}` | Without the Play Store there is no Play install, and so no referrer, even if Play is installed later. Add `permissionError` if you would rather not retry a manifest problem; pass `const {}` to count everything against the budget. |

`readOnce()` keeps its 0.1 shape (no lock, no budget) for apps that manage
those themselves.
