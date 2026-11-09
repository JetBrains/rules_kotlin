#!/bin/sh
# Runs a KSP command-line tool in a scratch directory, checks the Kotlin files it generates against the ones the
# rule declares and copies them. See ksp.bzl.
#
# Arguments: the java executable, the params file of the java command (one argument per line, in which
# __KSP_WORK__ stands for the scratch directory), the params file of the outputs (`<path relative to the output
# root of KSP>` and `<declared path>` on alternating lines), then optionally the standard library klib and the
# directory of the platform libraries of a konan target, which are appended to -libraries.
set -eu
java="$1"
params="$2"
outs="$3"
stdlib="${4:-}"
platform_libs="${5:-}"
work="$(mktemp -d "${TMPDIR:-/tmp}/ksp.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/kotlin" "$work/java" "$work/class" "$work/resource" "$work/caches" "$work/base"
set --
while IFS= read -r line; do
  line="$(printf '%s' "$line" | sed "s#__KSP_WORK__#$work#g")"
  case "$line" in
    -libraries=*)
      if [ -n "$stdlib" ]; then
        line="$line:$stdlib"
      fi
      if [ -n "$platform_libs" ]; then
        for lib in "$platform_libs"/*; do
          line="$line:$lib"
        done
      fi
      ;;
  esac
  set -- "$@" "$line"
done < "$params"
if ! "$java" "$@" > "$work/ksp.log" 2>&1; then
  cat "$work/ksp.log" >&2
  echo "KSP failed" >&2
  exit 1
fi
if grep -q '^e: ' "$work/ksp.log"; then
  cat "$work/ksp.log" >&2
  echo "KSP reported errors" >&2
  exit 1
fi
other="$(cd "$work" && find java class resource -type f | sort)"
if [ -n "$other" ]; then
  echo "KSP generated files this rule does not compile (Java sources, class files and resources are not supported):" >&2
  echo "$other" >&2
  exit 1
fi
(cd "$work/kotlin" && find . -type f | sed 's#^\./##' | sort) > "$work/actual"
sed -n 'p;n' "$outs" | sort > "$work/expected"
missing="$(comm -13 "$work/actual" "$work/expected")"
extra="$(comm -23 "$work/actual" "$work/expected")"
if [ -n "$missing" ] || [ -n "$extra" ]; then
  echo "The generated files of KSP differ from the ones declared in 'generated':" >&2
  [ -z "$missing" ] || { echo "declared but not generated:" >&2; echo "$missing" >&2; }
  [ -z "$extra" ] || { echo "generated but not declared:" >&2; echo "$extra" >&2; }
  exit 1
fi
while IFS= read -r rel && IFS= read -r out; do
  mkdir -p "$(dirname "$out")"
  cp "$work/kotlin/$rel" "$out"
done < "$outs"
