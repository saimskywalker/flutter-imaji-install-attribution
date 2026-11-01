# imaji_install_attribution example

A Flutter app that shows every state of
[`imaji_install_attribution`](../README.md): `Attributed`, `Organic` and
`Unavailable(reason)`, the install source, the deep-link helper with an
allowlist, and the consume-once store.

On an emulator or a side-loaded build the real read reports `Organic` or
`Unavailable` — that is expected. Use the **Simulate** buttons (debug builds
only) to exercise the routing, and see [TESTING.md](../TESTING.md) for getting
a real referrer from a Play-installed build.

```bash
flutter run
```
