#!/usr/bin/env bash
# Validates the output group framework_files of a kt_native_framework: the binary, header, module
# map and Info.plist of the framework, laid out as in an iOS framework under <name>.framework/, each
# a copy of the file of the framework. The Info.plist of a macOS framework is in Resources/, and
# its other files are reached through the symlinks of its versioned layout.
# Usage: check_framework_files.sh <framework> <file>...
set -euo pipefail

framework="$1"
shift

fail() { echo "FAIL: $*"; exit 1; }

[[ -d "$framework" ]] || fail "framework not found: $framework"
name="$(basename "$framework" .framework)"

expected="$(printf '%s\n' "$name" "Headers/$name.h" "Modules/module.modulemap" "Info.plist" | sort)"
paths=()
for file in "$@"; do
  # The path of the file in the framework: what follows <name>.framework/ in its own path.
  [[ "$file" == *"/$name.framework/"* ]] || fail "$file is not in a directory $name.framework"
  path="${file##*/"$name".framework/}"
  paths+=("$path")

  source="$framework/$path"
  if [[ "$path" == "Info.plist" && ! -e "$source" ]]; then
    source="$framework/Resources/Info.plist"
  fi
  [[ -f "$source" ]] || fail "no $path in $framework"
  cmp -s "$file" "$source" || fail "$file differs from $source"
done
[[ "$(printf '%s\n' "${paths[@]}" | sort)" == "$expected" ]] ||
  fail "the files are $(printf '%s ' "${paths[@]}")but should be $(echo "$expected" | tr '\n' ' ')"

echo "OK: the files of $framework"
