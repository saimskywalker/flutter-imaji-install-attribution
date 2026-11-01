#!/usr/bin/env bash
# Checks that the plugin's privacy manifest made it into a built app.
#
#   .github/scripts/check_ios_privacy_manifest.sh path/to/Runner.app
#
# Swift Package Manager puts it in wherefrom_wherefrom.bundle,
# CocoaPods in wherefrom_privacy.bundle (inside the plugin's
# framework). A wrong resource rule drops it without a build error.
set -euo pipefail

app=$1
source="$(cd "$(dirname "$0")/../.." && pwd)/packages/wherefrom/ios/wherefrom/Sources/wherefrom/PrivacyInfo.xcprivacy"

found=$(find "$app" -path '*/wherefrom*.bundle/PrivacyInfo.xcprivacy')
count=$(grep -c . <<<"$found" || true)
if [ "$count" -ne 1 ]; then
  echo "::error::expected one wherefrom PrivacyInfo.xcprivacy in $app, found $count"
  find "$app" -name '*.xcprivacy'
  exit 1
fi
echo "Found ${found#"$app"/}"
plutil -lint "$found"
if ! diff <(plutil -convert json -o - "$source") <(plutil -convert json -o - "$found"); then
  echo "::error::the bundled privacy manifest differs from the plugin's source file"
  exit 1
fi
echo "The plugin's privacy manifest is in the app bundle."
