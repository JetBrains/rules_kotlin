#!/usr/bin/env bash
# Validates the Android app: its APK has dex code, and its deploy jar, the classes the APK is dexed
# from, has the Android actual of //shared and kotlinx.coroutines, but not the JVM actual, which
# shows android_binary built //shared and @kmp_maven for the Android platform.
# Usage: check_android_app.sh <apk> <deploy jar>
set -euo pipefail

apk="$1"
deploy_jar="$2"

fail() { echo "FAIL: $*"; exit 1; }

[[ -f "$apk" ]] || fail "APK not found: $apk"
[[ -f "$deploy_jar" ]] || fail "deploy jar not found: $deploy_jar"

apk_entries="$(unzip -Z1 "$apk")"
grep -qxF "classes.dex" <<<"$apk_entries" || fail "$apk has no classes.dex"
grep -qxF "AndroidManifest.xml" <<<"$apk_entries" || fail "$apk has no AndroidManifest.xml"

jar_entries="$(unzip -Z1 "$deploy_jar")"
for class in \
  org/example/kmpapp/android/MainActivity.class \
  org/example/kmpapp/Greeting.class \
  org/example/kmpapp/AndroidPlatform.class; do
  grep -qxF "$class" <<<"$jar_entries" || fail "$deploy_jar has no $class"
done
grep -q "^kotlinx/coroutines/.*\.class$" <<<"$jar_entries" || fail "$deploy_jar has no kotlinx.coroutines classes"
if grep -qxF "org/example/kmpapp/JvmPlatform.class" <<<"$jar_entries"; then
  fail "$deploy_jar has the JVM actual of //shared, not the Android one only"
fi

echo "OK: $apk"
