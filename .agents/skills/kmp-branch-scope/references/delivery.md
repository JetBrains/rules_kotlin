# Delivering a change: one commit and its message

A change is what one task asks for: a feature, a fix, a rework, a docs pass. It reaches `kmp` as **one commit**, however
many steps its plan had, and the message of that commit is the record of the change.

## Why one commit

- **Every commit of the branch passes on its own.** A step of a plan often does not. In `262e0f73` the step that made a
  source in two lists an error broke `examples/kmp`, until the step that moved the example to an alias.
- **The branch is read commit by commit.** `scope.sh log <path>` prints the messages that shaped a file, and the ledger
  of `branch-map.md` has one entry per commit. A change spread over three commits is three places to read, and the
  earlier ones describe states the tree no longer has.
- **The message is the review.** Nothing else records why the change looks the way it does: plans and this skill are
  local files.

## What the commit holds

- Everything that carries the change: rules, tests, `docs/kmp.md` and the other docs, the regenerated `docs/kotlin.md`,
  examples, and the amended CHANGELOG entry.
- Nothing else. Nothing under `.junie/` (plans and this skill are local), no scratch files, no unrelated cleanup.
- A tree that was validated as a whole (see "How the branch validates a change" in the map), after the last edit.

## How to get there

1. Run `brd workspace` before the first edit. It says where to work and how to land. At the snapshot of the map: in a
   lease of your own, landing with `brd lease pick`, subjects without a `(branch)` prefix, and no push.
2. Commit once, when the whole change is done and validated: `git commit -F <message file>` in your worktree, then land
   it. Keep the message file outside the worktree, e.g. in a temporary directory.
3. Do not land the steps of a plan one by one. If you want checkpoints while you work, keep them in your worktree and
   make one commit of them before you land: `git reset --soft <the commit your worktree started from>`, then the
   commit of step 2. In a lease that commit is `git merge-base HEAD kmp`. This rewrites only commits that never left
   your worktree.
4. Run `scope.sh delivery` before you land, and again in the shared checkout after. It lists the commits that
   `origin/kmp` lacks, as of the last fetch, with the parts of each message. `!` marks what differs from this page, and
   the last line says when there is more than one commit. Fix what it marks on your commit. Commits from before this
   page keep their form.
5. Update the ledger of the map with the SHA the commit has on `kmp`, which can differ from the one in your worktree.
6. Do not push unless the user asks or `brd workspace` says `pull_request.on`.

**When several commits of one task are on `kmp` already.** The shared branch has one owner, so say so and squash them
once the user agrees: `brd squash <oldest> <newer>... --message-file <file>` in the shared checkout, with `--dry-run`
first. It keeps the tree of HEAD and prints the token that `brd undo` takes. `git diff --quiet <old tip> <new tip>`
shows that the tree is the same, so the evidence still holds without another run. Then update the map: `scope.sh`
names the SHAs of the map that are gone. `262e0f73` came about this way, from three commits.

**A follow-up on a change that is delivered.** A correction of a commit that is not on `origin/kmp` yet can be offered
as a part of that commit, with its message brought up to date. Fold it only when the user agrees. Otherwise, and always
for a commit that is on `origin/kmp`, it is a commit of its own that names the one it revises.

## The message

```
<What the rules do now, as one sentence>

<Lead: what a user of the rules gets, in the words of the public surface. Which commits of the range
this revises, by short SHA, and what was there before.>

<One paragraph per decision: what it is and why. Where an alternative was weighed: "Chose X, not Y:
<reason>". Where the change departs from its model (Gradle, the Kotlin Toolchain), what differs and why.>

<What stays as it was, where a reader would wonder: the default behaviour, a target that does not use
the new attribute.>

<The packaging, docs, examples and CHANGELOG that follow the code.>

Tests:
- `<test file>`: <the cases it covers now>.

Evidence:
    <command>                      <result>

Left out:
- <what is not done or not validated, and why or where it goes>.

<trailers>
```

**Subject.** The behaviour change as a sentence, in the imperative: "Gate KMP JVM and Android ABI jars behind
experimental_use_abi_jars". No prefix, no issue key, no final period. Be specific rather than short: most subjects of
the range have 50 to 110 characters. Name the rule or the behaviour, never the activity ("Refactor", "Address review",
"Step 3").

**Body.** Whole sentences, wrapped at 100 columns. Code names go in backticks, and commits of the range are named by
their 8-character SHA.
- Write it from the final diff, for a reader who has only the diff and the message. They have not seen the plan or the
  conversation.
- Give the reason of each decision, not a list of the files changed. The diff has the files.
- Say what a decision costs and what it deliberately leaves alone: "A library without aliases gets the fragments, their
  order and their `refines` it had."
- For a message that replaces several, e.g. after a squash, write one message for the result. Do not join the old ones.
  Leave out what one step did and a later one undid, the order of the work, and the SHAs of commits that no longer
  exist.

**`Tests:`** One item per test file that was added or changed, with the cases it covers now. No counts here. Leave the
section out when the commit touches no test.

**`Evidence:`** The commands that ran on the tree being committed and what they showed: the number of tests that pass,
and the host and the Bazel version when they matter. Every commit has it.
- Only runs on the final tree count. Leave out the result of an earlier state.
- State a result you saw, never one you expect. A check that was not run goes under `Left out:`.
- For a change that no test can show, say how it was checked instead, as `81e7457e` does for the docs.

**`Left out:`** What the change does not do and a reader might expect, and what was not validated, each with the reason
or the place it goes: a later step, an exec host that was not at hand, a warning that was there before. Leave the
section out when there is nothing. Never fill it to have one.

**Other sections.** A commit that is a survey or a cleanup may name its lists after what they hold, like `Changed:` and
`Kept:` in `212eac0a` or `Cut:` in `81e7457e`. It still says what was verified and what was not.

**Trailers.** Last, after a blank line, and only those the rules of your agent require, e.g. `Co-authored-by:`.

**Not in the message.** The route (plan steps, attempts, what the user said), praise of the change, and references to
local files such as plans and this skill.

Models in the range, to read with `git log -1 --format=%B <sha>`:
- `262e0f73`: a feature with several design decisions, the work of a plan of four steps.
- `074283b0`: the paragraphs on the alternatives it rejected ("Chose ..., not ..."). Its `Tests:` lists runs, which
  belong under `Evidence:`.
- `69f76b99`: a small change of behaviour in two paragraphs, which are not wrapped.

The older commits of the range differ in form: some wrap at 72 columns, some do not wrap, and `New tests:` and
`Tested:` became `Tests:` and `Evidence:`. Follow the form above, and do not reword them.
