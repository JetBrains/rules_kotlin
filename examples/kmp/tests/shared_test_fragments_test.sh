#!/usr/bin/env bash
# Verifies that //tests:shared_test.fragments prints the exact derived K2 test fragment graph.
set -euo pipefail

fragments_bin="$1"
tmp="$(mktemp -d "${TEST_TMPDIR:-/tmp}/shared_test_fragments_test.XXXXXX")"

cat > "$tmp/expected" <<'EOF'
fragment common
  platforms: jvm, android, linux_x64, macos_arm64
  srcs:
    common/SharedDiTest.kt
    common/SharedTest.kt
fragment non_android
  refines: common
  platforms: jvm, linux_x64, macos_arm64
  srcs:
    non_android/NonAndroidSharedTest.kt
fragment native
  refines: non_android
  platforms: linux_x64, macos_arm64
  srcs:
    native/PlatformOfTheTest.native.kt
    native/TestFixture.native.kt
fragment apple
  refines: native
  platforms: macos_arm64
  srcs:
    apple/AppleSharedTest.kt
fragment linux
  refines: native
  platforms: linux_x64
  srcs:
    linux/LinuxSharedTest.kt
leaf android
  refines: common
  srcs:
    android/AndroidSharedTest.kt
    android/PlatformOfTheTest.android.kt
leaf jvm
  refines: non_android
  srcs:
    jvm/JvmSharedTest.kt
    jvm/PlatformOfTheTest.jvm.kt
leaf linux_x64
  refines: linux
leaf macos_arm64
  refines: apple
EOF

case "$fragments_bin" in
  *.bat) cmd.exe //c "$(cygpath -w "$fragments_bin")" | tr -d '\r' > "$tmp/actual" ;;
  *) "$fragments_bin" > "$tmp/actual" ;;
esac

if ! diff -u "$tmp/expected" "$tmp/actual" >&2; then
  echo "FAIL: //tests:shared_test.fragments stdout mismatch" >&2
  exit 1
fi

echo "OK: $fragments_bin"
