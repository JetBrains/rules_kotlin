#!/usr/bin/env bash
# Verifies that //shared:shared.fragments prints the exact inferred K2 fragment refinement graph.
set -euo pipefail

fragments_bin="$1"
tmp="$(mktemp -d "${TEST_TMPDIR:-/tmp}/shared_fragments_test.XXXXXX")"

cat > "$tmp/expected" <<'EOF'
fragment android-ios_arm64-ios_simulator_arm64-jvm-linux_arm64-linux_x64-macos_arm64
  srcs:
    common/Greeting.kt
    common/Platform.kt
    common/di/Clock.kt
    common/di/GreetingRepository.kt
    common/di/Injected.kt
fragment ios_arm64-ios_simulator_arm64-jvm-linux_arm64-linux_x64-macos_arm64
  refines: android-ios_arm64-ios_simulator_arm64-jvm-linux_arm64-linux_x64-macos_arm64
  srcs:
    non_android/Greeting.nonAndroid.kt
fragment ios_arm64-ios_simulator_arm64-macos_arm64
  refines: ios_arm64-ios_simulator_arm64-jvm-linux_arm64-linux_x64-macos_arm64
  srcs:
    apple/Platform.apple.kt
    apple/di/AppleComponent.kt
    apple/di/Clock.apple.kt
    shared_ksp_apple
fragment linux_arm64-linux_x64
  refines: ios_arm64-ios_simulator_arm64-jvm-linux_arm64-linux_x64-macos_arm64
  srcs:
    linux/Injected.linux.kt
    linux/Platform.linux.kt
    linux/di/Clock.linux.kt
leaf android
  refines: android-ios_arm64-ios_simulator_arm64-jvm-linux_arm64-linux_x64-macos_arm64
  srcs:
    android/Platform.android.kt
    android/di/AndroidComponent.kt
    android/di/Clock.android.kt
    shared_ksp_android
leaf ios_arm64
  refines: ios_arm64-ios_simulator_arm64-macos_arm64
leaf ios_simulator_arm64
  refines: ios_arm64-ios_simulator_arm64-macos_arm64
leaf jvm
  refines: ios_arm64-ios_simulator_arm64-jvm-linux_arm64-linux_x64-macos_arm64
  srcs:
    jvm/Platform.jvm.kt
    jvm/di/Clock.jvm.kt
    jvm/di/JvmComponent.kt
    shared_ksp_jvm
leaf linux_arm64
  refines: linux_arm64-linux_x64
leaf linux_x64
  refines: linux_arm64-linux_x64
leaf macos_arm64
  refines: ios_arm64-ios_simulator_arm64-macos_arm64
EOF

case "$fragments_bin" in
  *.bat) cmd.exe //c "$(cygpath -w "$fragments_bin")" | tr -d '\r' > "$tmp/actual" ;;
  *) "$fragments_bin" > "$tmp/actual" ;;
esac

if ! diff -u "$tmp/expected" "$tmp/actual" >&2; then
  echo "FAIL: //shared:shared.fragments stdout mismatch" >&2
  exit 1
fi

echo "OK: $fragments_bin"
