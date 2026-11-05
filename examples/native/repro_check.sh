#!/usr/bin/env bash
# Manual check (not a Bazel test): the Kotlin/Native outputs of this example do not depend on the
# path of the checkout. It copies the example into two directories whose paths differ in length,
# builds it in each, with an output base of its own and no disk or remote cache, and compares the
# klibs (the private ones too), the executables and test runners and, on macOS, the frameworks
# byte for byte. It exits with 1 when an output differs.
# Usage: repro_check.sh (bazelisk or bazel on the PATH; it takes a few minutes)
set -euo pipefail

example="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo="$(cd "$example/../.." && pwd -P)"
work="$(mktemp -d "${TMPDIR:-/tmp}/kt_native_repro.XXXXXX")"
checkouts=("$work/a" "$work/a_much_longer_checkout_path/nested")
flags=(--override_module=rules_kotlin="$repo" --disk_cache= --noremote_accept_cached --lockfile_mode=off)

cleanup() {
  for i in 0 1; do
    if [[ -d "${checkouts[$i]}" ]]; then
      (cd "${checkouts[$i]}" && bazel --output_base="$work/output_base_$i" shutdown >/dev/null 2>&1) || true
    fi
  done
  chmod -R u+w "$work" 2>/dev/null || true
  rm -rf "$work"
}
trap cleanup EXIT

# The klibs, executables and frameworks under the execroot $1, relative to it, without runfiles.
outputs() {
  (cd "$1" && find bazel-out/ -name '*.runfiles' -prune -o \
    -name '*.framework' -type d -prune -print -o \
    \( -name '*.klib' -o -name '*.kexe' \) -type f -print) | sort
}

execroots=()
for i in 0 1; do
  dir="${checkouts[$i]}"
  mkdir -p "$dir"
  for f in "$example"/* "$example"/.bazelrc "$example"/.bazelversion; do
    case "$(basename "$f")" in
      bazel-* | MODULE.bazel.lock) continue ;;
    esac
    cp -RL "$f" "$dir/"
  done
  echo "== building the example in $dir"
  (cd "$dir" && bazel --output_base="$work/output_base_$i" build "${flags[@]}" //...)
  execroots+=("$(cd "$dir" && bazel --output_base="$work/output_base_$i" info "${flags[@]}" execution_root 2>/dev/null)")
done

a="${execroots[0]}"
b="${execroots[1]}"
listed="$(outputs "$a")"
[[ -n "$listed" ]] || { echo "FAIL: no outputs under $a"; exit 1; }
if [[ "$listed" != "$(outputs "$b")" ]]; then
  echo "FAIL: the checkouts have different outputs:"
  diff <(echo "$listed") <(outputs "$b") || true
  exit 1
fi

differences=0
files=0
while IFS= read -r output; do
  if [[ -d "$a/$output" ]] && [[ "$(cd "$a" && find "$output" | sort)" != "$(cd "$b" && find "$output" | sort)" ]]; then
    echo "DIFFERS: the content of $output"
    differences=$((differences + 1))
    continue
  fi
  while IFS= read -r file; do
    files=$((files + 1))
    if [[ -L "$a/$file" ]]; then
      [[ "$(readlink "$a/$file")" == "$(readlink "$b/$file")" ]] && continue
    elif cmp -s "$a/$file" "$b/$file"; then
      continue
    fi
    echo "DIFFERS: $file"
    differences=$((differences + 1))
  done < <(cd "$a" && find "$output" \( -type f -o -type l \) | sort)
done <<<"$listed"

if [[ $differences -gt 0 ]]; then
  echo "FAIL: $differences of $files files differ between the checkouts"
  exit 1
fi
echo "OK: $files files of $(wc -l <<<"$listed" | tr -d ' ') outputs are byte-identical in both checkouts"
