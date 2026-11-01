#!/usr/bin/env bash
# Installs the example's release APK (built with R8) on a running emulator,
# launches it and checks what the app logs for read() and installSource().
#
#   .github/scripts/android_release_smoke.sh path/to/app-release.apk
#
# A missing keep rule shows up here as a crash, a MissingPluginException
# (read() then returns Unavailable(notSupported)), an internalError, or a
# null install source, instead of on a Play-installed phone.
set -euo pipefail

apk=$1
app=io.github.saimskywalker.wherefrom_example

adb install -r "$apk" >/dev/null
adb logcat -c
adb shell am start -W -n "$app/.MainActivity" >/dev/null

log=""
for _ in $(seq 1 60); do
  log=$(adb logcat -d -v brief flutter:I AndroidRuntime:E '*:S')
  grep -q 'installSource(): ' <<<"$log" && break
  sleep 1
done
echo "$log"

if grep -q 'FATAL EXCEPTION' <<<"$log"; then
  echo "::error::the release build crashed"
  exit 1
fi
read_line=$(grep -o 'read(): .*' <<<"$log" | head -n1 || true)
source_line=$(grep -o 'installSource(): .*' <<<"$log" | head -n1 || true)
if [ -z "$read_line" ] || [ -z "$source_line" ]; then
  echo "::error::the app did not log read() and installSource() within 60 seconds"
  exit 1
fi

# Any outcome the platform can legitimately give an adb-installed app on an
# emulator. notSupported (no plugin registered), internalError, timeout and
# the like point at the build, not the device.
if ! grep -Eq '^read\(\): (Attributed|Organic)\(|^read\(\): Unavailable\((playStoreMissing|featureNotSupported|serviceUnavailable|serviceDisconnected|deadService|nullDetails):' <<<"$read_line"; then
  echo "::error::unexpected read() result in the release build: $read_line"
  exit 1
fi
if ! grep -q '^installSource(): InstallSource(sideload,' <<<"$source_line"; then
  echo "::error::unexpected installSource() in the release build: $source_line"
  exit 1
fi
if [ -z "$(adb shell pidof "$app" || true)" ]; then
  echo "::error::the app is no longer running"
  exit 1
fi
echo "Release build smoke test passed: $read_line"
