#!/bin/bash
# Tests the output contract of the script of the KSP actions (kotlin/internal/kmp/ksp_run.sh) with a fake java
# that plays the KSP tool: the Kotlin files it writes must be the declared ones, and nothing else.
set -eu

script="$1"
tmp="$(mktemp -d "${TEST_TMPDIR:-/tmp}/ksp_run_test.XXXXXX")"

cat > "$tmp/java" <<'JAVA'
#!/bin/sh
printf '%s\n' "$@" > "$FAKE_ARGS"
for arg in "$@"; do
  case "$arg" in
    -kotlin-output-dir=*) kotlin="${arg#-kotlin-output-dir=}" ;;
    -java-output-dir=*) java="${arg#-java-output-dir=}" ;;
  esac
done
for rel in ${FAKE_KOTLIN:-}; do
  mkdir -p "$kotlin/$(dirname "$rel")"
  echo "// generated $rel" > "$kotlin/$rel"
done
for rel in ${FAKE_JAVA:-}; do
  echo "class A {}" > "$java/$rel"
done
if [ -n "${FAKE_LOG:-}" ]; then
  echo "$FAKE_LOG"
fi
exit "${FAKE_EXIT:-0}"
JAVA
chmod +x "$tmp/java"

cat > "$tmp/params" <<'PARAMS'
-cp
tool.jar
Main
-kotlin-output-dir=__KSP_WORK__/kotlin
-java-output-dir=__KSP_WORK__/java
-libraries=a.klib:b.klib
processor.jar
PARAMS

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# run <name> <declared relative paths>...: runs the script with FAKE_* from the environment.
run() {
  name="$1"
  shift
  : > "$tmp/outs"
  for rel in "$@"; do
    printf '%s\n%s\n' "$rel" "$tmp/out_$name/$rel" >> "$tmp/outs"
  done
  mkdir -p "$tmp/out_$name"
  FAKE_ARGS="$tmp/args_$name" "$script" "$tmp/java" "$tmp/params" "$tmp/outs" "${STDLIB:-}" "${PLATFORM_LIBS:-}" \
    > "$tmp/stdout_$name" 2> "$tmp/stderr_$name"
}

expect_failure() {
  name="$1"
  needle="$2"
  if run "$@"; then
    fail "$name: the script succeeded"
  fi
  grep -q -- "$needle" "$tmp/stderr_$name" || { cat "$tmp/stderr_$name" >&2; fail "$name: no '$needle' in the message"; }
}

# The generated files are the declared ones: they are copied to the declared paths.
FAKE_KOTLIN="p/A.kt p/q/B.kt" run ok p/A.kt p/q/B.kt || { cat "$tmp/stderr_ok" >&2; fail "ok: the script failed"; }
grep -q "generated p/A.kt" "$tmp/out_ok/p/A.kt" || fail "ok: A.kt was not copied"
grep -q "generated p/q/B.kt" "$tmp/out_ok/p/q/B.kt" || fail "ok: B.kt was not copied"

# The processors write the paths to the output root of the tool, which the script substitutes.
grep -q -- "-kotlin-output-dir=/" "$tmp/args_ok" || fail "the work directory was not substituted"
grep -q "__KSP_WORK__" "$tmp/args_ok" && fail "the work directory placeholder is left in the arguments"

# A declared file the processors do not write.
FAKE_KOTLIN="p/A.kt" expect_failure missing "declared but not generated:" p/A.kt p/Missing.kt
grep -q "p/Missing.kt" "$tmp/stderr_missing" || fail "missing: the file is not named"

# A file the processors write that is not declared.
FAKE_KOTLIN="p/A.kt p/Extra.kt" expect_failure extra "generated but not declared:" p/A.kt
grep -q "p/Extra.kt" "$tmp/stderr_extra" || fail "extra: the file is not named"
[ ! -e "$tmp/out_extra/p/A.kt" ] || fail "extra: a file was copied despite the mismatch"

# Java sources are not compiled by the rules: the action fails instead of dropping them.
FAKE_KOTLIN="p/A.kt" FAKE_JAVA="J.java" expect_failure java "not supported" p/A.kt

# An error of KSP fails the action, even when the tool exits normally.
FAKE_KOTLIN="p/A.kt" FAKE_LOG="e: [ksp] boom" expect_failure error "KSP reported errors" p/A.kt

# A tool that fails fails the action, and its output is shown.
FAKE_KOTLIN="" FAKE_EXIT=3 FAKE_LOG="crashed" expect_failure crash "KSP failed" p/A.kt
grep -q crashed "$tmp/stderr_crash" || fail "crash: the output of the tool is not shown"

# The standard library and the platform libraries of a konan target are appended to -libraries.
mkdir -p "$tmp/platform/p1.klib" "$tmp/platform/p2.klib"
STDLIB="$tmp/stdlib" PLATFORM_LIBS="$tmp/platform" FAKE_KOTLIN="p/A.kt" run libs p/A.kt || { cat "$tmp/stderr_libs" >&2; fail "libs: the script failed"; }
libraries="$(grep -- '^-libraries=' "$tmp/args_libs")"
case "$libraries" in
  "-libraries=a.klib:b.klib:$tmp/stdlib:$tmp/platform/p1.klib:$tmp/platform/p2.klib") ;;
  *) fail "libs: unexpected libraries $libraries" ;;
esac
# The processor classpath is passed on as the last argument.
[ "$(tail -1 "$tmp/args_libs")" = "processor.jar" ] || fail "libs: the processor classpath is not last"

echo PASS
