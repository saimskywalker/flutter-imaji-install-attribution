# install_attribution

> Status: **pre-alpha, not published.** The API below is the design target;
> nothing is implemented yet. Progress is tracked in the issues.

A Flutter plugin that answers one question on both platforms: **where did
this install come from?**

- **Android** reads the Google Play Install Referrer.
- **iOS** reads the AdServices attribution token (Apple Search Ads).
- Both return one typed result, and a helper turns the referrer into the
  deep link the user was trying to reach before they installed.

## Why another referrer plugin

The existing Play Install Referrer plugins share a few problems:

| Problem | What this plugin does instead |
|---|---|
| The Kotlin Gradle Plugin is applied in the build file, which Flutter warns will fail on future releases (AGP 9 Built-in Kotlin) | Built-in Kotlin from day one. No KGP line anywhere |
| The Binder call to the Play Store service runs on the platform thread, so a slow Play service can freeze the app (ANR) | The call runs on a background thread with a timeout |
| Play can answer `OK` with an empty details bundle, and reading it throws a fatal `NullPointerException` | Every read is guarded and becomes a typed result |
| Failures arrive as `PlatformException` with string codes | A sealed result type: `Attributed`, `Organic`, `Unavailable(reason)` |
| Nothing stops the referrer being processed twice | An opt-in "consume once" store |
| Android only | iOS AdServices token behind the same API |

## Planned API

```dart
final result = await InstallAttribution.read(
  timeout: const Duration(seconds: 10),
);

switch (result) {
  case Attributed(:final referrer, :final clickedAt, :final source):
    final link = referrer.deepLink(key: 'utm_content'); // e.g. /s/abc123
    // route to `link`
  case Organic():
    // installed with no campaign
  case Unavailable(:final reason):
    // not installed from Play, service missing, timed out, …
}
```

## Non-goals

- Fingerprinting or any matching that identifies a person across apps.
- A hosted attribution service. This plugin reads what the platform
  gives you, and nothing else.

## Contributing

Issues and pull requests are welcome — especially device reports
("Play returned X on <OEM> Android N"), since referrer behaviour varies by
vendor and Play Store version.

## Support

If this plugin saved you a day of chasing referrers, a ⭐ on the repository
helps other Flutter developers find it.

## License

MIT © saimskywalker. See [LICENSE](LICENSE).
