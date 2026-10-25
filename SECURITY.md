# Security policy

## Supported versions

Fixes land on the latest minor release of each package in this repository.

| Package | Supported |
|---|---|
| `imaji_install_attribution` | 0.2.x |
| `imaji_referrer_builder` | 0.1.x |

Older versions do not get backports. Upgrade to the latest release first.

## Reporting a vulnerability

Please report privately: open this repository's **Security** tab and choose
**Report a vulnerability**. This creates a private advisory that only you and
the maintainer can see.

Do **not** open a public issue, pull request or discussion for a
vulnerability.

Useful things to include:

- the package and version, and the platform (Android, iOS, or the Dart
  builder on a server)
- what an attacker controls (for example a crafted referrer or deep link
  string) and what they can achieve
- a minimal reproduction: the input, the call, and the result
- any fix you have in mind

Please replace real install referrers, advertising tokens and user
identifiers with made-up values.

## What to expect

You will usually get a first reply within a week. Once the issue is
confirmed, a fix is prepared in the private advisory, released, and the
advisory is published with credit to you unless you prefer otherwise.
