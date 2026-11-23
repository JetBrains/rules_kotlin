#!/usr/bin/env bash
# Upgrades the Kotlin release rules_kotlin pins, or Kotlin/Native alone, or checks an older release.
#
#   scripts/upgrade_kotlin.sh upgrade <new> [--keep <old>]...
#   scripts/upgrade_kotlin.sh upgrade-native <new> [--keep <old>]...
#   scripts/upgrade_kotlin.sh check-compat <old>
#
# See docs/upgrading_kotlin.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL=//src/main/kotlin/io/bazel/kotlin/upgrade:upgrade_kotlin

# The modules whose MODULE.bazel.lock pins the Kotlin release through rules_kotlin. The lockfiles
# are not committed (.gitignore); refreshing the local ones keeps them in step with the new pins.
LOCKED_MODULES=(. examples/jetpack_compose examples/kmp examples/kmp_app examples/native)

usage() {
  sed -n '2,8s/^# \{0,1\}//p' "${BASH_SOURCE[0]}" >&2
  exit 2
}

step() {
  echo "==> $*" >&2
}

# Runs the upgrade tool of this checkout; its output goes to stdout, Bazel's to stderr.
run_tool() {
  (cd "$ROOT" && bazel run --noshow_progress --ui_event_filters=-info "$TOOL" -- "$@")
}

# Sets TOOL_ARGS to the tool flag $1 with the release $2, and a --keep per `--keep <old>` after it.
tool_args() {
  local flag="$1"
  shift
  [[ $# -ge 1 && "$1" != --* ]] || usage
  TOOL_ARGS=("$flag" "$1")
  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --keep)
        [[ $# -ge 2 ]] || usage
        TOOL_ARGS+=(--keep "$2")
        shift 2
        ;;
      *) usage ;;
    esac
  done
}

# Refreshes the local MODULE.bazel.lock of each module given that has one.
refresh_lockfiles() {
  local module
  for module in "$@"; do
    if [[ -f "$module/MODULE.bazel.lock" ]]; then
      (cd "$module" && bazel mod deps --lockfile_mode=update >/dev/null)
    fi
  done
}

upgrade() {
  tool_args --version "$@"
  local args=("${TOOL_ARGS[@]}")

  cd "$ROOT"
  step "1/5 the pins of the release (upgrade_kotlin ${args[*]})"
  # The tool prints the Maven lock files that pin org.jetbrains.kotlin artifacts, one
  # "<module directory> <repository>" line each, also when the pins were already up to date.
  local repins
  repins="$(run_tool "${args[@]}")"
  step "2/5 the kotlinc capabilities of the release"
  bazel run //src/main/kotlin/io/bazel/kotlin/generate:kotlin_release_options
  # The generator does not write buildifier's layout; format what it wrote so that the files
  # stay lint-clean and a re-run leaves them unchanged.
  bazel run --noshow_progress --ui_event_filters=-info @buildifier_prebuilt//:buildifier -- \
    "$ROOT"/src/main/starlark/core/repositories/kotlin/templates.bzl \
    "$ROOT"/src/main/starlark/core/repositories/kotlin/capabilities_*.bzl
  step "3/5 the Maven pins of the org.jetbrains.kotlin artifacts of the examples"
  local locked=("${LOCKED_MODULES[@]}")
  local module repository
  while read -r module repository; do
    [[ -n "$module" ]] || continue
    step "    $module: @$repository//:pin"
    # </dev/null: the pin must not read the remaining lines of the loop.
    (cd "$module" && REPIN=1 bazel run "@$repository//:pin" </dev/null)
    [[ " ${locked[*]} " == *" $module "* ]] || locked+=("$module")
  done <<<"$repins"
  step "4/5 docs/kotlin.md"
  bazel run //docs:write_docs
  step "5/5 the lockfiles"
  refresh_lockfiles "${locked[@]}"
  step "done: review git diff, then run the checks of docs/upgrading_kotlin.md"
  step "note: possible required changes by hand: README.md, CHANGELOG.md, docs/*"
}

upgrade_native() {
  tool_args --native-version "$@"
  local args=("${TOOL_ARGS[@]}")

  cd "$ROOT"
  step "1/2 the Kotlin/Native pins (upgrade_kotlin ${args[*]})"
  run_tool "${args[@]}"
  step "2/2 the lockfiles"
  refresh_lockfiles "${LOCKED_MODULES[@]}"
  step "done: review git diff, then run the checks of docs/upgrading_kotlin.md"
  step "note: possible required changes by hand: README.md, CHANGELOG.md, docs/kmp.md"
}

check_compat() {
  [[ $# -eq 1 && "$1" != --* ]] || usage
  local release="$1"

  cd "$ROOT"
  step "1/3 the overrides of Kotlin $release"
  local overrides
  overrides="$(run_tool --emit-overrides "$release")"

  local scratch
  local tmp="${TMPDIR:-/tmp}"
  scratch="$(mktemp -d "${tmp%/}/rules_kotlin_compat.XXXXXX")"
  # Expunge the output base of the scratch module, so it leaves neither a server nor its outputs.
  trap '(cd "'"$scratch"'/kmp" 2>/dev/null && bazel clean --expunge >/dev/null 2>&1); rm -rf "'"$scratch"'"' EXIT

  step "2/3 a copy of examples/kmp on Kotlin $release in $scratch/kmp"
  mkdir "$scratch/kmp"
  (cd examples/kmp && tar --exclude='./bazel-*' -cf - .) | (cd "$scratch/kmp" && tar -xf -)
  local module="$scratch/kmp/MODULE.bazel"
  local content
  content="$(<"$module")"
  local relative='path = "../..",'
  [[ "$content" == *"$relative"* ]] || {
    echo "examples/kmp/MODULE.bazel has no local_path_override $relative" >&2
    exit 1
  }
  # Prefix and suffix removal instead of ${content/.../...}: its quoting differs in bash 3.2.
  printf '%s%s%s\n\n%s\n' \
    "${content%%"$relative"*}" \
    "path = \"$ROOT\"," \
    "${content#*"$relative"}" \
    "$overrides" >"$module"

  step "3/3 bazel test //... in the copy"
  local log="$scratch/test.log"
  # pipefail: a failing bazel test fails the pipeline, and set -e exits.
  (cd "$scratch/kmp" && bazel test //... --lockfile_mode=update) 2>&1 | tee "$log"
  # The toolchains follow the compiler of the overrides. An experimental language version would
  # only be a warning of kotlinc: fail on it here.
  if grep -q "is experimental, there are no backwards compatibility guarantees" "$log"; then
    echo "Kotlin $release compiled at an experimental language version" >&2
    exit 1
  fi
  step "done: examples/kmp passes on Kotlin $release"
}

[[ $# -ge 1 ]] || usage
command="$1"
shift
case "$command" in
  upgrade) upgrade "$@" ;;
  upgrade-native) upgrade_native "$@" ;;
  check-compat) check_compat "$@" ;;
  *) usage ;;
esac
