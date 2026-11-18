#!/bin/bash
# Tests executing :<name>.fragments targets end-to-end and checking exact deterministic stdout.
set -eu

mpp="$1"
mpp_collapse="$2"
mpp_incomparable="$3"
mpp_single="$4"
mpp_special="$5"

tmp="$(mktemp -d "${TEST_TMPDIR:-/tmp}/fragments_graph_test.XXXXXX")"

run_graph() {
  case "$1" in
    *.bat) cmd.exe //c "$(cygpath -w "$1")" | tr -d '\r' ;;
    *) "$1" ;;
  esac
}

assert_graph() {
  name="$1"
  bin="$2"
  cat > "$tmp/expected_$name"
  run_graph "$bin" > "$tmp/actual_$name"
  if ! diff -u "$tmp/expected_$name" "$tmp/actual_$name" >&2; then
    echo "FAIL: $name stdout mismatch" >&2
    exit 1
  fi
}

assert_graph mpp "$mpp" <<'EOF'
fragment ios_simulator_arm64-jvm-linux_arm64-macos_arm64
  srcs:
    testdata/Platform.kt
    testdata/Greeting.kt
fragment ios_simulator_arm64-linux_arm64-macos_arm64
  refines: ios_simulator_arm64-jvm-linux_arm64-macos_arm64
  srcs:
    testdata/Description.native.kt
fragment ios_simulator_arm64-macos_arm64
  refines: ios_simulator_arm64-linux_arm64-macos_arm64
  srcs:
    testdata/Platform.apple.kt
leaf ios_simulator_arm64
  refines: ios_simulator_arm64-macos_arm64
leaf jvm
  refines: ios_simulator_arm64-jvm-linux_arm64-macos_arm64
  srcs:
    testdata/Platform.jvm.kt
leaf linux_arm64
  refines: ios_simulator_arm64-linux_arm64-macos_arm64
  srcs:
    testdata/Platform.linux.kt
leaf macos_arm64
  refines: ios_simulator_arm64-macos_arm64
EOF

assert_graph mpp_collapse "$mpp_collapse" <<'EOF'
fragment jvm-linux_arm64
  srcs:
    testdata/Platform.kt
    testdata/Platform.linux.kt
leaf jvm
  refines: jvm-linux_arm64
leaf linux_arm64
  refines: jvm-linux_arm64
EOF

assert_graph mpp_incomparable "$mpp_incomparable" <<'EOF'
fragment jvm-linux_arm64-macos_arm64
  srcs:
    testdata/Platform.kt
fragment jvm-linux_arm64
  refines: jvm-linux_arm64-macos_arm64
  srcs:
    testdata/Description.native.kt
fragment jvm-macos_arm64
  refines: jvm-linux_arm64-macos_arm64
  srcs:
    testdata/Platform.apple.kt
leaf jvm
  refines: jvm-linux_arm64, jvm-macos_arm64
  srcs:
    testdata/Platform.jvm.kt
leaf linux_arm64
  refines: jvm-linux_arm64
leaf macos_arm64
  refines: jvm-macos_arm64
EOF

assert_graph mpp_single "$mpp_single" <<'EOF'
leaf jvm
  srcs:
    testdata/Platform.kt
    testdata/Greeting.kt
    testdata/Platform.jvm.kt
EOF

assert_graph mpp_special "$mpp_special" <<'EOF'
-e 'single' "double" $VAR `cmd` \back %1% ^caret & < > | (paren) !bang
EOF

echo PASS
