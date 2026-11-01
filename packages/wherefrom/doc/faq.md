# FAQ

## Why this exists

Firebase Dynamic Links has been shut down, and with it the easy way to carry
a link through an app-store install. What is left is the platform itself:
the Play Install Referrer on Android and the AdServices token on iOS.
Reading the referrer safely has a few traps, and this plugin handles each
of them:

| Trap | What this plugin does |
|---|---|
| Flutter warns that plugins applying the Kotlin Gradle Plugin will fail to build in a future release (AGP 9 Built-in Kotlin) | Built-in Kotlin from day one. Flutter's check is a text match on the plugin's build file, and there is nothing to match |
| The Binder call `getInstallReferrer()` blocks the thread it runs on, so on the platform thread a slow Play Store freezes the UI (ANR) | Every Binder call in the read (the Play Store presence check and `getInstallReferrer()`) runs on a background thread, with a timeout (default 10 s) |
| Play can answer `OK` with details whose bundle is null; reading them throws `NullPointerException` | Every read is guarded: `Unavailable(nullDetails)` |
| `DeadObjectException`, `PERMISSION_ERROR`, `FEATURE_NOT_SUPPORTED`, … are easy to lose in a generic error string | Each one is a distinct `UnavailableReason` |
| A second `SERVICE_DISCONNECTED` can leave a pending call unanswered | One reconnect, then `Unavailable(serviceDisconnected)`; a timeout bounds everything |
| A referrer can be acted on twice, and a failing read can retry on every launch forever | `claimOnce()`: one claim per process, a persisted retry budget, first-launch-only semantics |
| Decoding a referrer value twice corrupts `%2F` paths | `referrer.deepLink(allow: [...])` decodes exactly once and enforces an allowlist |
| "Unknown installer" errors for Samsung restores and other stores | `InstallSource` maps the installer package: Play, Galaxy Store, AppGallery, Amazon, side-load, restore |
| Testing normally needs a build installed from Play | `debugOverride()` and a real [testing guide](../TESTING.md) |

## Questions

**Do I need the App Tracking Transparency prompt on iOS?** No. Fetching the
AdServices token does not require ATT. Resolving it is a server-to-Apple call
outside this plugin.

**Why do I always get `Organic` while developing?** Because Play did not
install your debug build. See [TESTING.md](../TESTING.md).

**Is there a deferred deep link on iOS?** Not from the platform. The
AdServices token tells your server about Apple Ads campaigns; it carries no
custom payload.

**Can I call `read()` on every launch?** Yes. Concurrent calls share one
read, and Play keeps the referrer for 90 days. `readOnce()` skips the call
entirely once you have handled it.

**Does it build with AGP 8 or `builtInKotlin=false`?** Yes; see
[Android build setup](setup.md#android-build-setup).

**Does it fingerprint users?** No. It reads what the platform hands the app
and nothing else.

## Non-goals

- Fingerprinting, or any matching that identifies a person across apps.
- A hosted attribution service, or calling Apple's attribution API for you.

## Alternatives

Other Flutter plugins read the Play Install Referrer too, and one of them may
be all you need: [`play_install_referrer`](https://pub.dev/packages/play_install_referrer),
[`android_play_install_referrer`](https://pub.dev/packages/android_play_install_referrer)
and [`stack_deferred_link`](https://pub.dev/packages/stack_deferred_link).
Each package's own page says what it covers.

This plugin covers a wider job, install attribution on both platforms: the
iOS AdServices token, typed failure reasons, consume-once claiming, installer
detection and the allowlisted deep-link helper. If reading the Android
referrer is all you need, any of the plugins above may suit you better.
Thanks to their maintainers for their work.
