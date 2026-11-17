# Upgrading the Kotlin release

rules_kotlin pins one Kotlin release for the JVM compiler, the Build Tools API and Kotlin/Native.
[`scripts/upgrade_kotlin.sh`](../scripts/upgrade_kotlin.sh) moves every pin to a new release from
the published release metadata, and checks that an older release still works.

## Upgrading

```shell
scripts/upgrade_kotlin.sh upgrade <new> --keep <old>
```

`--keep` names an older release that stays pinned for Kotlin/Native and documented in
[kmp.md](kmp.md); it can be given more than once. Without it the current release is kept. The
per-release Kotlin/Native tables then hold exactly the new release and the kept ones.

The script runs, in order:

1. The upgrade tool, `bazel run //src/main/kotlin/io/bazel/kotlin/upgrade:upgrade_kotlin -- --version <new> [--keep <old>]...`.
   It rewrites the pins described below, then prints the Maven lock files that pin
   `org.jetbrains.kotlin` artifacts of the examples, also when the pins were already up to date.
2. `bazel run //src/main/kotlin/io/bazel/kotlin/generate:kotlin_release_options`, which writes the
   kotlinc capabilities of the new compiler (`capabilities_<major>.<minor>.bzl` and `templates.bzl`),
   then buildifier formats them. The capabilities of the older minor releases stay as they are; the
   `kt_kotlinc_options` attributes whose flags the new compiler dropped disappear from
   [kotlin.md](kotlin.md), and exist only with an older compiler.
3. `REPIN=1 bazel run @<repository>//:pin` in each module the tool printed, such as
   `examples/jetpack_compose` for the Compose compiler plugin and `examples/dagger` for
   kotlin-metadata-jvm, so that their `maven_install.json` follows the rewritten artifacts.
4. `bazel run //docs:write_docs`, for [kotlin.md](kotlin.md).
5. `bazel mod deps --lockfile_mode=update` in the root, `examples/jetpack_compose`, `examples/kmp`,
   `examples/kmp_app`, `examples/native` and the modules repinned in step 3, for those that have a
   local `MODULE.bazel.lock`. The lockfiles are not committed; this only keeps the local ones in
   step with the new pins.

Running it again for the same release changes nothing.

### What the tool rewrites

The tool first fetches and validates the metadata of every release involved, then writes. Any
missing asset or mismatch fails with a message and leaves the tree untouched. It stages the new
content and a backup of every file next to it, then replaces the files; if a replacement fails, it
restores the files already replaced and removes the staged ones. `--dry-run` only lists the files
it would change.

| Source                                                                                         | Used for                                                     |
|------------------------------------------------------------------------------------------------|--------------------------------------------------------------|
| The GitHub release `v<version>`: asset digests and `.sha256` files                             | `kotlin-compiler-<version>.zip`, `kotlin-native-prebuilt-<host>-<version>.tar.gz` of each exec host |
| `maven-<version>-sha256.txt` of the GitHub release                                             | The Build Tools API and its implementation jars              |
| `konan/konan.properties` of each prebuilt distribution                                         | The LLVM of each exec host, checked against `KOTLIN_NATIVE_DEPS` |
| The `.sha256` files of `download.jetbrains.com/kotlin/native/resources/llvm/`                  | The LLVM archives                                            |

| File                                                       | Rewritten                                                                                     |
|------------------------------------------------------------|-----------------------------------------------------------------------------------------------|
| `src/main/starlark/core/repositories/versions.bzl`         | `_KOTLIN_CURRENT_RELEASE` and the checksums of the compiler, the Build Tools API and its implementation |
| `src/main/starlark/core/repositories/native_compiler.bzl`  | The `KOTLIN_NATIVE_PREBUILT` and `KOTLIN_NATIVE_LLVM` rows, and the LLVM archives of `KOTLIN_NATIVE_ARCHIVES` |
| `src/test/starlark/native_konan_properties.bzl`            | The `konan.properties` excerpts of each kept release, for the tests                          |
| `kotlin/internal/toolchains.bzl`                           | On a new minor release, the `api_version`/`language_version` value and default                |
| `src/test/starlark/internal/jvm/kotlinc_options_test.bzl`  | The expected default `api_version`/`language_version`                                         |
| `examples/*/MODULE.bazel`                                  | Every `org.jetbrains.kotlin` Maven artifact, such as the Compose compiler plugin and kotlin-metadata-jvm, whatever its version; the tool fails if no example pins one |
| `docs/kmp.md`                                              | The generated "Staying on Kotlin ..." sections of the kept releases                           |

The tool never rewrites, and leaves to a separate manual change:

- KSP, whose release is not tied to the Kotlin one: edit `versions.bzl` by hand.
- `KOTLIN_NATIVE_DEPS`: the tool only checks it against the `konan.properties` of each release and
  fails if a dependency changed.
- The `capabilities_*.bzl` files and the `api_version`/`language_version` values of older minor
  releases: it never deletes them.
- `CHANGELOG.md`, and the release mentioned in the README, in [kmp_dependencies.md](kmp_dependencies.md)
  and in the requirements and the `version` tag of [kmp.md](kmp.md).

The tool downloads each prebuilt Kotlin/Native distribution, about 300 MB, to read its
`konan.properties`. It caches the file by the sha256 of the distribution in
`$RULES_KOTLIN_UPGRADE_CACHE`, or `rules_kotlin/upgrade_kotlin` in `$XDG_CACHE_HOME` or
`~/.cache`. A cache that cannot be written only costs the download next time; an unreadable
entry fails the run with its path. Set `GITHUB_TOKEN` if the GitHub API rate limit is hit.

### After the upgrade

Review `git diff`, in particular that the capabilities of older releases did not change, then run
the checks:

```shell
bazel test //src/...
bazel test //examples:all
bazel run //:buildifier.check
bazel test //docs:write_docs_test
scripts/upgrade_kotlin.sh check-compat <old>
```

If the new compiler changes a flag the rules use, gate it on the compiler version so that the kept
releases keep working.

### Language versions

A new minor release becomes the default `api_version`/`language_version` of the toolchain, and a
new compiler deprecates the oldest language versions, then rejects them with `language version
<version> is no longer supported`: Kotlin 2.4.21 deprecates 2.0 and 2.1. The toolchain keeps
accepting those values, for older compilers, so mention the ones the new compiler deprecates or
rejects in `CHANGELOG.md` and in the toolchain comments of the README.

An older compiler treats the new default as experimental and marks its classes pre-release. A
toolchain that sets no `api_version` or `language_version` therefore compiles at the major and
minor version of the `kotlinc_version` in use, `KOTLINC_VERSION` of
`@com_github_jetbrains_kotlin//:version.bzl`, as long as that release is not newer than the pinned
one; so do the tools rules_kotlin builds from source (the CLI toolchain). The overrides of a kept
release need no toolchain of their own.

## Checking an older release

```shell
scripts/upgrade_kotlin.sh check-compat <old>
```

The script copies [`examples/kmp`](../examples/kmp) to a temporary directory, points it at this
checkout, appends the root module overrides of the release to its `MODULE.bazel` and runs
`bazel test //...` there. It fails if the tests fail, or if kotlinc warns that a language version
is experimental, which would mean the build did not compile at the language version of the
release. The copy and its Bazel output base are deleted afterwards.

The overrides are the snippet documented in [kmp.md](kmp.md); the tool prints it with:

```shell
bazel run //src/main/kotlin/io/bazel/kotlin/upgrade:upgrade_kotlin -- --emit-overrides <old>
```

It holds the published checksums of the release, and fails if they differ from the ones this
checkout pins for it.
