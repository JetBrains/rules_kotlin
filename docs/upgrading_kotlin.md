# Upgrading the Kotlin release

rules_kotlin pins a Kotlin release for the JVM compiler and the Build Tools API, and a Kotlin/Native
release, which may be a dev build of the next Kotlin release (2.5.20-dev-5696 today).
[`scripts/upgrade_kotlin.sh`](../scripts/upgrade_kotlin.sh) moves the pins of a release train, or
the Kotlin/Native ones alone, from the published release metadata, and checks that an older release
still works.

## Upgrading

```shell
scripts/upgrade_kotlin.sh upgrade <new> --keep <old>
```

`--keep` names an older release that stays pinned for Kotlin/Native and documented in
[kmp.md](kmp.md); it can be given more than once. Without it the current release is kept. The
per-release Kotlin/Native tables then hold exactly the new release and the kept ones.

Kotlin/Native moves with the release train, unless rules_kotlin pins a newer Kotlin/Native, such as
a dev build of the next release: its pins then stay as they are, and the tool says so. Releases order
by version, and within a version a dev build before a Beta, a Beta before a release candidate and a
release candidate before the release, so `upgrade 2.5.20-Beta1` moves Kotlin/Native from
2.5.20-dev-5696 while `upgrade 2.4.22` leaves it. The new release must then have a Kotlin/Native
Build Tools API (see [Upgrading Kotlin/Native alone](#upgrading-kotlinnative-alone)).

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
| `maven-<version>-sha256.txt` of the GitHub release                                             | The Build Tools API and its implementation jars, and the Kotlin/Native Build Tools API jars of 2.5.20 and newer releases |
| The Kotlin dev Maven repository, `redirector.kotlinlang.org/maven/dev`: the `.sha256` file next to each artifact | A dev build, which has no GitHub release: `kotlin-native-prebuilt-<version>-<host>.tar.gz` of each exec host and the Kotlin/Native Build Tools API jars |
| `konan/konan.properties` of each prebuilt distribution                                         | The LLVM of each exec host, checked against `KOTLIN_NATIVE_DEPS` |
| The `.sha256` files of `download.jetbrains.com/kotlin/native/resources/llvm/`                  | The LLVM archives                                            |

| File                                                       | `upgrade` rewrites                                                                            | `upgrade-native` rewrites |
|------------------------------------------------------------|-----------------------------------------------------------------------------------------------|---------------------------|
| `src/main/starlark/core/repositories/versions.bzl`         | `_KOTLIN_CURRENT_RELEASE` and the checksums of the compiler, the Build Tools API and its implementation | Nothing |
| `src/main/starlark/core/repositories/native_compiler.bzl`  | Unless Kotlin/Native is newer than the release: `KOTLIN_NATIVE_VERSION`, the `KOTLIN_NATIVE_PREBUILT`, `KOTLIN_NATIVE_LLVM` and `KOTLIN_NATIVE_BTAPI` rows, and the LLVM archives of `KOTLIN_NATIVE_ARCHIVES` | The same |
| `src/test/starlark/native_konan_properties.bzl`            | Unless Kotlin/Native is newer than the release: the `konan.properties` excerpts of each kept release, for the tests | The same |
| `kotlin/internal/toolchains.bzl`                           | On a new minor release, the `api_version`/`language_version` value and default                | Nothing |
| `src/test/starlark/internal/jvm/kotlinc_options_test.bzl`  | The expected default `api_version`/`language_version`                                         | Nothing |
| `examples/*/MODULE.bazel`                                  | Every `org.jetbrains.kotlin` Maven artifact, such as the Compose compiler plugin and kotlin-metadata-jvm, whatever its version; the tool fails if no example pins one | Nothing |
| `docs/kmp.md`                                              | The generated "Staying on Kotlin ..." sections of the kept releases; when Kotlin/Native moves too, the "Staying on Kotlin/Native ..." ones go | The generated "Staying on Kotlin/Native ..." sections of the kept releases |

The tool never rewrites, and leaves to a separate manual change:

- KSP, whose release is not tied to the Kotlin one: edit `versions.bzl` by hand.
- `KOTLIN_NATIVE_DEPS`: the tool only checks it against the `konan.properties` of each release and
  fails if a dependency changed.
- The `capabilities_*.bzl` files and the `api_version`/`language_version` values of older minor
  releases: it never deletes them.
- `CHANGELOG.md`, and the release mentioned in the README, in [kmp_dependencies.md](kmp_dependencies.md)
  and in the requirements, the `version` tag and the Kotlin/Native Build Tools API section of
  [kmp.md](kmp.md).

The tool downloads each prebuilt Kotlin/Native distribution, about 300 MB, to read its
`konan.properties`. It caches the file by the sha256 of the distribution in
`$RULES_KOTLIN_UPGRADE_CACHE`, or `rules_kotlin/upgrade_kotlin` in `$XDG_CACHE_HOME` or
`~/.cache`. A cache that cannot be written only costs the download next time; an unreadable
entry fails the run with its path. Set `GITHUB_TOKEN` if the GitHub API rate limit is hit; a dev
build reads no GitHub API.

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

## Upgrading Kotlin/Native alone

```shell
scripts/upgrade_kotlin.sh upgrade-native <new> --keep <old>
```

`<new>` is a Kotlin/Native release or dev build, e.g. `2.5.20-dev-5696`, which becomes the default of
the `kotlin_native` module extension. It must have a Kotlin/Native Build Tools API, which the launcher
of the Kotlin/Native actions is compiled against: the tool rejects a release older than
2.5.20-dev-4986 before it downloads anything. `--keep` names an older release that stays pinned and
documented in the "Staying on Kotlin/Native ..." sections of [kmp.md](kmp.md); it can be given more
than once. A kept release may be older than 2.5.20-dev-4986: its klibs compile with the konanc
command line. Without `--keep` the release of the JVM compiler is kept. The JVM compiler, its Build
Tools API and the Maven pins of the examples stay as they are.

The script runs the upgrade tool,
`bazel run //src/main/kotlin/io/bazel/kotlin/upgrade:upgrade_kotlin -- --native-version <new> [--keep <old>]...`,
which rewrites the Kotlin/Native pins only (see [What the tool rewrites](#what-the-tool-rewrites)),
then refreshes the local lockfiles, as step 5 of `upgrade` does. Running it again for the same
release changes nothing. Run the checks of [After the upgrade](#after-the-upgrade), and the
Kotlin/Native examples with the Build Tools API off too:

```shell
bazel test //... --@rules_kotlin//kotlin/settings:experimental_native_build_tools_api=false
```

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
checkout pins for it. It selects the release for Kotlin/Native too: a release older than
2.5.20-dev-4986, such as 2.4.21, has no Kotlin/Native Build Tools API, so its check also covers the
klib compilations of the konanc command line.
