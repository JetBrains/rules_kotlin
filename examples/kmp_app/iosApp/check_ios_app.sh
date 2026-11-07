#!/usr/bin/env bash
# Validates the iOS app: the app of the IPA has the bundle id, and its executable is an arm64
# Mach-O for the iOS simulator that links the given Objective-C classes, those of the Kotlin classes
# of a static framework, which are named after it. macOS only.
# Usage: check_ios_app.sh <ipa> <bundle id> [Objective-C class ...]
set -euo pipefail

ipa="$1"
bundle_id="$2"
shift 2

fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$ipa" ]] || fail "IPA not found: $ipa"
dir="$(mktemp -d "${TEST_TMPDIR:-${TMPDIR:-/tmp}}/ipa.XXXXXX")"
unzip -q "$ipa" -d "$dir"
apps=("$dir"/Payload/*.app)
app="${apps[0]}"
[[ -d "$app" ]] || fail "no app in $ipa"
name="$(basename "$app" .app)"

plist="$app/Info.plist"
[[ -f "$plist" ]] || fail "no Info.plist in $app"
actual_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist")"
[[ "$actual_id" == "$bundle_id" ]] || fail "$plist has the bundle id $actual_id, not $bundle_id"
executable="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$plist")"
binary="$app/$executable"
[[ -f "$binary" ]] || fail "no executable $executable in $app"

info="$(lipo -info "$binary")"
[[ "$info" == *"architecture: arm64" ]] || fail "not an arm64 executable: $info"
# The LC_BUILD_VERSION platform of the executable, by number or by name (see mach-o/loader.h).
built_for="$(otool -l "$binary" | awk '/cmd LC_BUILD_VERSION/ { found = 1 } found && $1 == "platform" { print $2; found = 0 }' | sort -u)"
[[ "$built_for" =~ ^(7|IOSSIMULATOR)$ ]] || fail "$binary is built for platform '$built_for', not the iOS simulator"

symbols="$(nm "$binary")"
for class in "$@"; do
  grep -qE "[[:space:]]_OBJC_CLASS_\\\$_${class}$" <<<"$symbols" || fail "$binary does not link the Objective-C class $class"
done

echo "OK: $name of $ipa"
