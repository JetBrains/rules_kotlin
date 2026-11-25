---
name: kmp-branch-scope
description: Use at the start of every task that plans, makes, reviews or commits a change (code, Starlark, tests, docs, examples, CI) in this rules_kotlin checkout, before writing, squashing or rewording a commit or its message there, and whenever new commits land on it. The checkout is the `kmp` feature branch, which adds Kotlin/Native support first and Kotlin Multiplatform support on top. The skill scopes the work to the branch commits from 09145518 to HEAD. It shows what the branch owns and can still rework in place, which upstream files it touches and why, and which designs it dropped, and it enforces that every change serves Kotlin/Native or KMP support. It also says how a change is delivered to the branch, as one commit with a detailed message, and gives the form of that message.
---

# Scope of the Kotlin/Native and KMP feature branch

This checkout is the `kmp` branch of JetBrains/rules_kotlin (remote `origin`). It branches from master at `239007ef`,
which was also the tip of bazel-contrib/rules_kotlin master (remote `upstream`) when this skill was written. The branch
brings **Kotlin/Native support first** (toolchains, klibs, binaries, tests, frameworks), and **Kotlin
Multiplatform support** on top of it (fragments, `kt_multiplatform_library`, KMP Maven deps, KSP, app integration).

The scope of the branch is the commits from `09145518` (the first one, "Kotlin/Native support (prototype)") to the
**current HEAD**. HEAD moves with every new commit; it was `81e7457e` when this skill was written. Nothing in that range
is released (no tag contains it), so all of it can still be changed. Everything before it is upstream code.

Every change on this branch must be justified by Kotlin/Native or KMP support: either directly, or as support work those
features need (Kotlin upgrades, language levels, docs, CI, examples). A change that serves neither does not belong on
this branch. Say so, and propose it as a separate upstream change instead.

## Workflow for each task

`scripts/scope.sh` is in the folder of this skill, `.junie/skills/kmp-branch-scope` of the shared checkout. Call it by
its absolute path from the worktree you work in, the shared checkout or a Branch Deck lease:
`cd <worktree> && <skill folder>/scripts/scope.sh <command>`. It reads the git state of that worktree and takes paths
relative to it or absolute; `scope.sh help` lists the commands.

1. **See the current range.** Run `scope.sh`. It prints the base, the commits oldest first and the uncommitted
   files. A commit marked `*` is newer than `references/branch-map.md`. Read it (`git show --stat <sha>` and its message)
   before changing anything it touched. A commit marked `~` is in the map under an older SHA, after a rebase: update
   the ledger.
2. **Load the context.** Read the sections of `references/branch-map.md` the task needs. Read the commit ledger and
   "Superseded designs" before any design change, and "Upstream files the branch modifies" before editing upstream code.
3. **Classify every file before editing it.** Run `scope.sh owner <path>...`:
   - `branch-added`: owned by the branch. Rework it in place (rules below). `scope.sh log <path>` prints the messages
     of the commits that shaped it, which say why it looks the way it does.
   - `upstream-modified`: an upstream file the branch already changes. `scope.sh diff <path>` shows its whole delta to
     upstream, uncommitted edits included. Keep it minimal.
   - `upstream-untouched`: a first touch of upstream code. It needs an explicit Kotlin/Native or KMP justification;
     prefer a solution inside the branch-owned files.
   - `branch-deleted`: the branch added it and deleted it again. Check "Superseded designs" in the map before bringing
     it back.
   - `new`: a new file, which becomes branch-owned.
4. **State the scope in your plan or answer**, in one line: which part of the purpose the change serves (native, KMP or
   support), which earlier branch commits it revises (short SHAs), and which upstream files it touches.
5. **Check before you commit.** Run `scope.sh check`. Justify or revert every `upstream-untouched` file it lists.
6. **Deliver the change as one commit** (next section), then update the map (last section).

To review commits that arrived on the branch, run `scope.sh check <commit>` or `scope.sh check <from>..<to>` (e.g.
`scope.sh check HEAD..origin/kmp` after a fetch), then read their messages. It classifies their files against the
branch as it was before them, so `upstream-untouched` marks an upstream file they touch for the first time.

After a rebase that changes the SHAs, the script finds the first commit by its subject. If that fails, set
`KMP_SCOPE_BASE=<parent of the first branch commit>`.

## Delivering a change

A change is what one task asks for. It reaches `kmp` as **one commit, with a message that records it**, however many
steps its plan had. Read `references/delivery.md` before you write the commit. It has the way to one commit and the form
of the message, with models from the range.

- **One task, one commit.** The steps of a plan are not commits of the branch. Commit once, when the change is done, and
  land that commit as `brd workspace` says. Every commit of the branch passes on its own, and a step often does not.
- **The commit is complete.** It holds everything that carries the change: rules, tests, docs, the regenerated
  `docs/kotlin.md`, examples and the CHANGELOG entry, in a tree that was validated as a whole after the last edit. It
  holds nothing under `.junie/`: plans and this skill are local.
- **The message is the record of the change.** Nothing else on the branch says why it looks the way it does.
  - The subject is the behaviour change as a sentence, like those of the range.
  - The body says what a user of the rules gets, names the earlier branch commits the change revises by their short
    SHA, and gives the reason of each decision.
  - It ends with `Tests:` (what the changed tests cover), `Evidence:` (what ran on the committed tree, and the result)
    and `Left out:` (what is not done or not validated, and why).
  - It describes the result, not the route: no plan steps, and no state that the final tree lacks.
- **Check the delivery.** `scope.sh delivery` lists the commits that `origin/kmp` lacks with the parts of each message.
  `!` marks what differs from the form, and it says when there is more than one commit.
- **History that is on `kmp` already stays** unless the user asks: never rewrite, fold or reword it on your own.
  - Several commits of one task that landed apart are squashed into one once the user agrees.
  - A correction of an earlier branch commit can be offered as a fixup of it. Otherwise it is a commit of its own that
    names the one it revises.
- **No push** unless the user asks or `brd workspace` says so.

## Rules drawn from the branch history

**Branch-owned code is malleable.** Nothing in the range was released.
- Change a design where it lives: rename, reshape or delete the API the branch introduced.
- Add no deprecations, aliases, compatibility shims or migration errors for shapes that only existed on the branch, and
  no "Breaking" notes for them. Precedents: `3dcd5e18` deleted `kt_source_set` instead of deprecating it, `212eac0a`
  removed the diagnostics of never-released macro shapes, and `81e7457e` collapsed the CHANGELOG to two entries.
- Prefer fixing the earlier decision over adding a workaround on top of it. Then update everything that carries the
  design: rules, tests, `docs/kmp.md`, the generated `docs/kotlin.md`, examples and the CHANGELOG entry.

**Upstream code stays as upstream left it, unless native/KMP needs it.**
- Keep the delta small and justified.
- Leave the default behaviour of JVM/Android-only builds unchanged: the same actions, outputs and configurations. A new
  behaviour is opt-in through an existing switch or an `experimental_*` setting. Precedents: `69f76b99` gated the ABI jars
  behind `experimental_use_abi_jars`, and `39f8e07c` kept the configuration hashes of JVM consumers equal.
- Do not fix unrelated upstream issues on this branch, such as the buildifier warnings in upstream files. Mention them
  instead.

**Respect the current design.**
- Do not bring back anything listed under "Superseded designs" in the map.
- Reversing an item of "Decisions kept on purpose" is a design change: raise it with the user first.

**Invariants of the native and KMP actions.**
- Hermetic: actions need no network (konan runs with `airplaneMode=true`). Repositories fetch everything, and what
  rules_kotlin pins carries a sha256.
- Sandboxed, and path-mapping safe: paths come from `File`s, `__EXECROOT__` stands for the execroot, and the actions
  declare `supports-path-mapping`.
- Reproducible: `examples/native/repro_check.sh` must keep passing.
- Exec hosts and konan targets come from the tables in `kotlin/internal/native/targets.bzl`, never hardcoded.
- Bazel 7, 8 and 9 keep working, and so does Windows. It has no Kotlin/Native exec host, so native targets and tests are
  incompatible there, never failing.

**Fail at analysis with an actionable message.** When konanc, KSP or the macro cannot take an input, fail at analysis
with a message that names the fix, instead of letting the tool crash or silently produce an empty output (`39f8e07c`).

**Package and wire every addition.**
- New `.bzl` files or scripts go into their package's `bzl_library` and `BUILD.release.bazel`/`release_archive`.
- New repositories and toolchains go into `MODULE.release.bazel` as well as `MODULE.bazel`.
- New example packages go into `--deleted_packages` in `.bazelrc`. A Kotlin/Native or KMP example is excluded on Windows
  and runs in the macOS Kotlin/Native task of `.bazelci/tests.yml`. An example that needs a newer Bazel gets an
  `exclude/<version>` file, like the `exclude/7.x` of `examples/kmp`.

**Docs follow the code in the same change.**
- User-facing behaviour goes into `docs/kmp.md`, `docs/kmp_dependencies.md` or `docs/upgrading_kotlin.md`.
- After a change to a rule or attribute docstring, regenerate `docs/kotlin.md` with `bazel run //docs:write_docs`.
- Never hand-edit the regions that `scripts/upgrade_kotlin.sh` generates.
- `README.md`, `examples/README.md` and `examples/kmp_app/README.md` stay summaries that link to `docs/kmp.md`.
- The branch has two CHANGELOG entries. Amend them rather than adding one per iteration.
- Comments give reasons only (`c6263b2b`).

**Tests live where the branch keeps them.**
- Analysis tests go in `src/test/starlark/internal/{native,kmp,jvm}`, with the unit tests of the pure Starlark logic
  (`derive`, `hierarchy`, `declaration`) next to them. Those of `kmp_maven_impl` and the native repositories are in
  `src/test/starlark`.
- Kotlin tests cover the launcher and the upgrade tool.
- `src/test/integration` holds real compilations and setting matrices.
- The examples are user samples, not test matrices.
- Validate as described in "How the branch validates a change" in the map.

## Keeping this skill current

- The ledger in `references/branch-map.md` must cover every commit of the range. When `scripts/scope.sh` marks a commit
  with `*`, or after you land one, add it to the ledger. Then update the affected sections (public surface, upstream
  files, superseded designs, kept decisions, open ends) and the `Snapshot:` line.
- A squash, a fold or a rebase changes SHAs. `scope.sh` names the commits the map mentions that are no longer in the
  history of HEAD: replace each of them, in the ledger and wherever else the map or this skill names it.
- Commit messages can be stale. For example, `e0f1b4c7` calls the resolver release unpublished, although it pins it.
  Check a fact against the code before relying on it.
- This skill is local to the shared checkout. It is untracked, excluded through `.git/info/exclude`, and not part of the
  branch. Edit it at its path in the shared checkout, also while working in a lease. Never commit it, and never copy it
  into a worktree.
