#!/usr/bin/env bash
# Generate App Store screenshots (6.9" = 1320x2868) for ZeroWallet.
#
# Boots the 6.9" simulator, builds the integration-test app, runs the
# screenshot test, and writes PNGs to ./screenshots/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# iPhone 18 Pro Max simulator (iOS 27). Falls back to the first booted device.
DEVICE_UDID="${ZERO_SIM_UDID:-5E46D1FE-D427-4EA1-ABCD-0CFC48DB3BCC}"

# Ensure the simulator is booted.
if ! xcrun simctl list devices booted | grep -q "$DEVICE_UDID"; then
  echo "Booting simulator $DEVICE_UDID ..."
  xcrun simctl boot "$DEVICE_UDID" || true
  xcrun simctl bootstatus "$DEVICE_UDID" -b
fi

# Reset simulator state so the app boots to the welcome screen on every run.
#
# iOS keychain entries persist across app reinstall/uninstall, and
# flutter_secure_storage stores wallets as kSecClassGenericPassword items with
# accessibility "first_unlock_this_device". SecureStorageService.clearAll()
# currently issues its SecItemDelete with the default "unlocked" accessibility,
# which does not match those items — so a leftover wallet from a prior run
# would otherwise land the app on wallet home instead of the welcome screen.
# Resetting the simulator keychain (a test-device-only, destructive reset) is
# the deterministic way to get a clean first-launch state.
echo "Resetting keychain + app state on $DEVICE_UDID ..."
xcrun simctl keychain "$DEVICE_UDID" reset || true
xcrun simctl uninstall "$DEVICE_UDID" com.derekdeng.zerowallet 2>/dev/null || true

# Unset proxy (Flutter needs direct access to pub.dev / services).
env \
  -u all_proxy \
  -u ALL_PROXY \
  -u http_proxy \
  -u https_proxy \
  -u HTTP_PROXY \
  -u HTTPS_PROXY \
  -u no_proxy \
  -u NO_PROXY \
  flutter drive \
    --driver=test_driver/app_store_screenshots_driver_test.dart \
    --target=integration_test/app_store_screenshots_test.dart \
    -d "$DEVICE_UDID"

echo "Done. Screenshots are in $PROJECT_ROOT/screenshots/"
