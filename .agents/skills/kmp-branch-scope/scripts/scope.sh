#!/usr/bin/env bash
# Scope of the Kotlin/Native and Kotlin Multiplatform feature branch of rules_kotlin: the commits from
# FIRST_COMMIT to HEAD, and which files they own or changed upstream. Runs in the worktree it is called
# from (the shared checkout or a Branch Deck lease). Bash 3.2 compatible (macOS).
set -euo pipefail
export GIT_PAGER=cat

FIRST_COMMIT=09145518c337df0542542e4654a7dd3e98698fe7
FIRST_SUBJECT='Kotlin/Native support (prototype): kt_native_library + kt_native_binary'
REMOTE_BRANCH=${KMP_SCOPE_REMOTE:-origin/kmp}
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MAP="$SKILL_DIR/references/branch-map.md"

usage() {
  cat <<'EOF'
usage: scope.sh [summary]               base, commits of the branch (* = not in the map yet), uncommitted files
       scope.sh base                    the base commit: the parent of the first commit of the branch
       scope.sh files [--all]           upstream files the branch changes, with their commits (--all: added files too)
       scope.sh owner <path>...         who owns each path: branch-added, branch-deleted, upstream-modified,
                                        upstream-untouched or new
       scope.sh log <path>...           messages of the branch commits that touched the paths, oldest first
       scope.sh diff <path>...          delta of the branch to the base for the paths, uncommitted edits included
       scope.sh check [<rev>|<a>..<b>]  classify the uncommitted files, or the files of a commit or of a range
       scope.sh delivery [<rev>|<a>..<b>]
                                        the commits origin/kmp lacks, or a commit or a range, with the parts
                                        of each message (! = differs from references/delivery.md)

Paths are relative to the current directory, or absolute. KMP_SCOPE_BASE=<commit> overrides the base,
KMP_SCOPE_REMOTE=<ref> the branch that delivery compares with.
EOF
}

case "${1:-}" in
  -h | --help | help)
    usage
    exit 0
    ;;
esac

CALLER_PWD=$(pwd -P)
TOP=$(git rev-parse --show-toplevel) || exit 1
TOP=$(cd "$TOP" && pwd -P)
cd "$TOP"

base() {
  if [ -n "${KMP_SCOPE_BASE:-}" ]; then
    git rev-parse --verify "${KMP_SCOPE_BASE}^{commit}"
    return
  fi
  if git merge-base --is-ancestor "$FIRST_COMMIT" HEAD 2>/dev/null; then
    git rev-parse "${FIRST_COMMIT}^"
    return
  fi
  # After a rebase the SHA changes but the subject stays.
  local c
  c=$(git log --reverse --format='%H%x09%s' HEAD | awk -F'\t' -v s="$FIRST_SUBJECT" '$2 == s && !found { print $1; found = 1 }')
  if [ -n "$c" ]; then
    git rev-parse "${c}^"
    return
  fi
  echo "error: neither $FIRST_COMMIT nor a commit titled '$FIRST_SUBJECT' is in the history of HEAD;" >&2
  echo "       not on the kmp branch? Set KMP_SCOPE_BASE=<parent of the first branch commit>." >&2
  exit 1
}

rel() {
  # Repository-relative path of $1, given relative to the caller's directory or absolute.
  local p="$1" d b
  case "$p" in
    /*) ;;
    *) p="$CALLER_PWD/$p" ;;
  esac
  while [ "$p" != "/" ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  d=$(dirname "$p")
  b=$(basename "$p")
  # Resolves symlinks, . and .. through the directory when it exists; that of a deleted file may not.
  if d=$(cd "$d" 2>/dev/null && pwd -P); then
    case "$b" in
      .) p="$d" ;;
      ..) p=$(dirname "$d") ;;
      *) p="$d/$b" ;;
    esac
  fi
  case "$p" in
    "$TOP") echo "." ;;
    "$TOP"/*) echo "${p#"$TOP"/}" ;;
    *)
      echo "error: $1 is not in the worktree $TOP" >&2
      return 1
      ;;
  esac
}

commits_of() {
  git log --reverse --format=%h "$B"..HEAD -- "$1" | tr '\n' ' ' | sed 's/ $//'
}

classify() {
  # Owner of the path $1 as of the commit $2, HEAD by default.
  local p="$1" ref="${2:-HEAD}"
  if git cat-file -e "$B:$p" 2>/dev/null; then
    if git diff --quiet "$B" "$ref" -- "$p"; then
      echo "upstream-untouched"
    else
      echo "upstream-modified"
    fi
  elif git cat-file -e "$ref:$p" 2>/dev/null; then
    echo "branch-added"
  elif [ -n "$(git log -1 --format=%h "$B".."$ref" -- "$p")" ]; then
    echo "branch-deleted"
  else
    echo "new"
  fi
}

explain() {
  case "$1" in
    branch-added) echo "added by the branch, unreleased: rework it in place, without compatibility shims" ;;
    upstream-modified) echo "upstream file the branch already changes: keep its delta minimal and justified" ;;
    upstream-untouched) echo "upstream file the branch never touched: a first touch needs a Kotlin/Native or KMP reason" ;;
    branch-deleted) echo "added and deleted again by the branch: check the superseded designs of the map before reviving it" ;;
    new) echo "in neither the base nor HEAD: a new file becomes branch-owned" ;;
  esac
}

in_map() {
  # 0: the ledger of the map lists the commit; 2: only its subject, under another SHA (a rebase); 1: neither.
  [ -f "$MAP" ] || return 1
  if grep -qE "^ *[0-9]+\. \`$1\`" "$MAP"; then return 0; fi
  if grep -qF -- "$(printf '%s' "$2" | cut -c1-50)" "$MAP"; then return 2; fi
  return 1
}

map_gone() {
  # The commits the map names that are not in the history of HEAD.
  [ -f "$MAP" ] || return 0
  local h
  grep -oE '`[0-9a-f]{8}`' "$MAP" | tr -d '`' | sort -u | while IFS= read -r h; do
    git merge-base --is-ancestor "$h" HEAD 2>/dev/null || printf '%s ' "$h"
  done
}

report_map_gone() {
  local gone
  gone=$(map_gone)
  if [ -n "$gone" ]; then
    echo
    echo "the map names commits that are not in the history of HEAD: ${gone% }"
    echo "  squashed or rebased away (update the ledger and every mention), or this worktree is behind the branch."
  fi
}

cmd_summary() {
  local n added modified missing=0 moved=0
  n=$(git rev-list --count "$B"..HEAD)
  added=$(git diff --name-only --diff-filter=A "$B" HEAD | wc -l | tr -d ' ')
  modified=$(git diff --name-only --diff-filter=MDR "$B" HEAD | wc -l | tr -d ' ')
  echo "base:   $(git log -1 --format='%h %s' "$B")"
  echo "head:   $(git log -1 --format='%h %s' HEAD) [$(git branch --show-current 2>/dev/null || echo detached)]"
  echo "range:  $n commits; $added files added, $modified upstream files modified/deleted/renamed"
  echo
  echo "commits (oldest first; * = not in references/branch-map.md yet, ~ = in it under another SHA):"
  while IFS=$'\t' read -r h d s; do
    local short st=0 mark=" "
    short=$(printf '%s' "$h" | cut -c1-8)
    in_map "$short" "$s" || st=$?
    case "$st" in
      1) mark="*"; missing=$((missing + 1)) ;;
      2) mark="~"; moved=$((moved + 1)) ;;
    esac
    printf ' %s %s %s %s\n' "$mark" "$short" "$d" "$s"
  done < <(git log --reverse --format='%H%x09%ad%x09%s' --date=short "$B"..HEAD)
  if [ "$missing" -gt 0 ]; then
    echo
    echo "$missing commit(s) are newer than the map: read them (git show) before changing what they touched."
  fi
  if [ "$moved" -gt 0 ]; then
    echo
    echo "$moved commit(s) have another SHA in the map, e.g. after a rebase: update their SHAs in the ledger."
  fi
  report_map_gone
  echo
  local pending
  pending=$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u)
  if [ -n "$pending" ]; then
    echo "uncommitted changes (scope.sh check classifies them):"
    printf '%s\n' "$pending" | sed 's/^/  /'
  else
    echo "no uncommitted changes"
  fi
}

cmd_files() {
  echo "upstream files the branch modified (commits oldest first):"
  git diff --name-status --diff-filter=MDR "$B" HEAD | while IFS=$'\t' read -r st f rest; do
    [ -n "${rest:-}" ] && f="$rest"
    printf '  %s %-75s %s\n' "$(printf '%s' "$st" | cut -c1)" "$f" "$(commits_of "$f")"
  done
  if [ "${1:-}" = "--all" ]; then
    echo
    echo "files added by the branch:"
    git diff --name-only --diff-filter=A "$B" HEAD | sed 's/^/  /'
  else
    echo
    echo "$(git diff --name-only --diff-filter=A "$B" HEAD | wc -l | tr -d ' ') files added by the branch (--all lists them)"
  fi
}

cmd_owner() {
  [ $# -gt 0 ] || { usage >&2; exit 2; }
  local a p k
  for a in "$@"; do
    p=$(rel "$a")
    k=$(classify "$p")
    printf '%s: %s - %s\n' "$p" "$k" "$(explain "$k")"
    case "$k" in
      branch-added | branch-deleted | upstream-modified) git log --reverse --format='    %h %s' "$B"..HEAD -- "$p" ;;
    esac
  done
}

cmd_log() {
  [ $# -gt 0 ] || { usage >&2; exit 2; }
  local paths=() a p
  for a in "$@"; do
    p=$(rel "$a")
    paths+=("$p")
  done
  git log --reverse --date=short --format='=== %h %ad %s%n%n%b' "$B"..HEAD -- "${paths[@]}"
}

cmd_diff() {
  [ $# -gt 0 ] || { usage >&2; exit 2; }
  local paths=() a p
  for a in "$@"; do
    p=$(rel "$a")
    paths+=("$p")
  done
  git diff "$B" -- "${paths[@]}"
}

cmd_check() {
  # Without an argument the uncommitted files against HEAD; else the files of a commit against its
  # parent, or those of <a>..<b> against <a>: an upstream-untouched one is touched for the first time.
  local from to files f k first=0
  if [ $# -gt 0 ]; then
    case "$1" in
      *..*)
        from=${1%%..*}
        to=${1#*..}
        ;;
      *)
        from="$1^"
        to=$1
        ;;
    esac
    from=$(git rev-parse --verify "${from:-HEAD}^{commit}")
    to=$(git rev-parse --verify "${to:-HEAD}^{commit}")
    echo "files changed from $(git log -1 --format=%h "$from") to $(git log -1 --format='%h %s' "$to"), against the branch as of $(git log -1 --format=%h "$from"):"
    files=$(git diff --name-only "$from" "$to")
  else
    from=HEAD
    echo "uncommitted files, against HEAD:"
    files=$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u)
  fi
  if [ -z "$files" ]; then
    echo "  none"
    return
  fi
  while IFS= read -r f; do
    k=$(classify "$f" "$from")
    if [ "$k" = "upstream-untouched" ]; then first=$((first + 1)); fi
    printf '  %-18s %s\n' "$k" "$f"
  done <<EOF
$files
EOF
  if [ "$first" -gt 0 ]; then
    echo
    echo "$first upstream file(s) the branch had not touched before: justify each by Kotlin/Native or KMP support, or revert it."
  fi
}

describe_delivery() {
  # The parts of the message of the commit $1, and what references/delivery.md asks of it and it lacks.
  local c="$1" short subject second body trailers text width sections="" names="" files tests local_files t st=0
  short=$(printf '%s' "$c" | cut -c1-8)
  subject=$(git log -1 --format=%s "$c")
  second=$(git log -1 --format=%B "$c" | sed -n 2p)
  body=$(git log -1 --format=%b "$c")
  trailers=$(git log -1 --format='%(trailers:only,unfold)' "$c")
  text=$(printf '%s\n' "$body" | grep -c '[^[:space:]]' || true)
  if [ -n "$trailers" ]; then text=$((text - $(printf '%s\n' "$trailers" | grep -c '[^[:space:]]' || true))); fi
  width=$(printf '%s\n' "$body" | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')
  files=$(git diff-tree --no-commit-id --name-only -r "$c")
  tests=$(printf '%s\n' "$files" | grep -cE '(^|/)src/test/|(^|/)tests?/|_test\.' || true)
  local_files=$(printf '%s\n' "$files" | grep -c '^\.junie/' || true)
  for t in 'Tests:' 'Evidence:' 'Left out:'; do
    if printf '%s\n' "$body" | grep -qxF -- "$t"; then sections="$sections $t"; fi
  done

  printf '  %s %s\n' "$short" "$subject"
  printf '      %s file(s), %s of them tests; body: %s line(s) of text, the longest of %s columns\n' \
    "$(printf '%s\n' "$files" | grep -c . || true)" "$tests" "$text" "$width"
  printf '      sections:%s\n' "${sections:- none}"
  if [ -n "$trailers" ]; then printf '%s\n' "$trailers" | sed 's/^/      trailer: /'; fi

  in_map "$short" "$subject" || st=$?
  case "$st" in
    1) echo "    ! not in the ledger of the map yet" ;;
    2) echo "    ! in the ledger of the map under another SHA" ;;
  esac
  case "$subject" in
    'fixup! '* | 'squash! '* | 'amend! '*) echo "    ! a fixup: it is delivered as a part of its target, not as a commit" ;;
    *.) echo "    ! the subject ends with a period" ;;
  esac
  if [ -n "$second" ]; then echo "    ! no blank line after the subject"; fi
  if [ "$text" -le 0 ]; then
    echo "    ! no body: say what changes and why"
  else
    case "$sections" in
      *Evidence:*) ;;
      *) echo "    ! no 'Evidence:' section: say what ran on this tree and what it showed" ;;
    esac
    case "$sections" in
      *Tests:*) ;;
      *) if [ "$tests" -gt 0 ]; then echo "    ! changes tests, with no 'Tests:' section"; fi ;;
    esac
  fi
  if [ "$width" -gt 100 ]; then echo "    ! a line of $width columns: wrap the body at 100"; fi
  if [ "$local_files" -gt 0 ]; then
    echo "    ! holds $local_files file(s) under .junie/: plans and skills are local, take them out"
  fi
  # Words of 8 hex digits: a commit before this one is a commit it revises; any other commit, or a
  # word with digits and letters that names no commit, is one that a squash or a rebase took away.
  for t in $(printf '%s\n' "$body" | grep -oE '(^|[^0-9A-Za-z])[0-9a-f]{8}([^0-9A-Za-z]|$)' | tr -cd '0-9a-f\n' | sort -u); do
    if git cat-file -e "$t^{commit}" 2>/dev/null; then
      if git merge-base --is-ancestor "$t" "$c^" 2>/dev/null; then
        names="$names $t"
      else
        echo "    ! names $t, which is not a commit before it on the branch"
      fi
    else
      case "$t" in
        *[0-9]*) case "$t" in *[a-f]*) echo "    ! names $t, which is no commit of this repository" ;; esac ;;
      esac
    fi
  done
  if [ -n "$names" ]; then printf '      names the earlier commits:%s\n' "$names"; fi
}

cmd_delivery() {
  # The commits of <a>..<b>, or the commit <rev>; without an argument the commits that HEAD has and
  # REMOTE_BRANCH lacks: the ones a task delivered and nobody else has yet.
  local range n c pending
  if [ $# -gt 0 ]; then
    case "$1" in
      *..*) range=$1 ;;
      *) range="$1^..$1" ;;
    esac
    n=$(git rev-list --count "$range")
    echo "commits of $range, oldest first (! = differs from references/delivery.md):"
  else
    if ! git rev-parse --verify -q "$REMOTE_BRANCH^{commit}" >/dev/null; then
      echo "error: no $REMOTE_BRANCH here: fetch it, set KMP_SCOPE_REMOTE=<ref>, or name a commit or a range" >&2
      exit 1
    fi
    range="$REMOTE_BRANCH..HEAD"
    n=$(git rev-list --count "$range")
    echo "commits that $REMOTE_BRANCH ($(git log -1 --format=%h "$REMOTE_BRANCH"), as of the last fetch) lacks, oldest first"
    echo "(! = differs from references/delivery.md):"
  fi
  if [ "$n" -eq 0 ]; then echo "  none"; fi
  for c in $(git rev-list --reverse "$range"); do
    describe_delivery "$c"
  done
  if [ "$n" -gt 1 ]; then
    echo
    echo "$n commits. A change is one commit: when several of them are one task, make them one."
  fi
  report_map_gone
  pending=$( { git diff --name-only HEAD; git ls-files --others --exclude-standard; } | sort -u | grep -v '^\.junie/' || true)
  if [ -n "$pending" ]; then
    echo
    echo "uncommitted files, in no commit yet:"
    printf '%s\n' "$pending" | sed 's/^/  /'
  fi
}

B=$(base)
cmd=${1:-summary}
if [ $# -gt 0 ]; then shift; fi
case "$cmd" in
  summary) cmd_summary ;;
  base) echo "$B" ;;
  files) cmd_files "$@" ;;
  owner) cmd_owner "$@" ;;
  log) cmd_log "$@" ;;
  diff) cmd_diff "$@" ;;
  check) cmd_check "$@" ;;
  delivery) cmd_delivery "$@" ;;
  *)
    usage >&2
    exit 2
    ;;
esac
