#!/usr/bin/env bash
# Validates a kt_native_framework output: a static framework of an arm64 Apple target, whose
# Info.plist names its platform and bundle id, and whose header declares the given Objective-C
# interfaces. A macOS framework has the versioned layout of a macOS bundle. macOS only.
# Usage: check_framework.sh <framework> <iPhoneOS|iPhoneSimulator|MacOSX> <bundle id> [interface ...]
set -euo pipefail

framework="$1"
platform="$2"
bundle_id="$3"
shift 3

fail() { echo "FAIL: $*"; exit 1; }

[[ -d "$framework" ]] || fail "framework not found: $framework"
name="$(basename "$framework" .framework)"

# The LC_BUILD_VERSION platform of the binary, by number or by name (see mach-o/loader.h).
case "$platform" in
  MacOSX) build_platform="1|MACOS" ;;
  iPhoneOS) build_platform="2|IOS" ;;
  iPhoneSimulator) build_platform="7|IOSSIMULATOR" ;;
  *) fail "unknown platform: $platform" ;;
esac

if [[ "$platform" == "MacOSX" ]]; then
  # The bundle is in Versions/A, which Versions/Current and the top-level entries lead to.
  for path in "Versions/A/$name" "Versions/A/Headers/$name.h" "Versions/A/Resources/Info.plist" \
    "Versions/Current/$name" "$name" "Headers/$name.h" "Resources/Info.plist"; do
    [[ -f "$framework/$path" ]] || fail "no $path in $framework"
  done
  plist="$framework/Resources/Info.plist"
else
  plist="$framework/Info.plist"
fi

binary="$framework/$name"
[[ -f "$binary" ]] || fail "no binary: $binary"
[[ "$(od -An -tx1 -N 8 "$binary" | tr -d ' \n')" == "213c617263683e0a" ]] ||
  fail "not a static library (an ar archive): $binary"
lipo -info "$binary" | grep -q "architecture: arm64$" || fail "not an arm64 library: $(lipo -info "$binary")"
built_for="$(otool -l "$binary" | awk '/cmd LC_BUILD_VERSION/ { found = 1 } found && $1 == "platform" { print $2; found = 0 }' | sort -u)"
[[ "$built_for" =~ ^($build_platform)$ ]] || fail "$binary is built for platform '$built_for', not $platform"

plist_value() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist"; }
[[ "$(plist_value CFBundleSupportedPlatforms:0)" == "$platform" ]] ||
  fail "$plist supports $(plist_value CFBundleSupportedPlatforms), not $platform"
[[ "$(plist_value CFBundleIdentifier)" == "$bundle_id" ]] ||
  fail "$plist has the bundle id $(plist_value CFBundleIdentifier), not $bundle_id"
[[ "$(plist_value CFBundleExecutable)" == "$name" ]] || fail "$plist names another executable than $name"

header="$framework/Headers/$name.h"
for interface in "$@"; do
  grep -qE "^@interface ${interface}[ :<]" "$header" || fail "$header declares no $interface"
done

echo "OK: $framework is a static $platform framework"
