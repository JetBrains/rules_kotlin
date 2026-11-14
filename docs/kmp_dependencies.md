# Kotlin Multiplatform dependencies

Experimental. The `kmp_maven` module extension is the Bazel counterpart of the dependencies of the
`commonMain` source set of a Kotlin Gradle build: Maven libraries that the common code of a
[`kt_multiplatform_library`](../kotlin/kmp.bzl) uses, and that each platform compiles against in
its own variant, the klib of a konan target for the Kotlin/Native rules and the jar or aar for the
JVM and Android rules. [`examples/kmp`](../examples/kmp) uses it for `kotlinx-coroutines-core`.

The libraries are resolved by [bazel-kmp-resolver](https://github.com/JetBrains/bazel-kmp-resolver)
into a manifest committed in the workspace, which pins every artifact by URL and integrity: a build
needs neither the resolver nor Maven metadata, and downloads only the artifacts of the platforms it
builds for.

## Declaring the dependencies

In the `MODULE.bazel` of the root module:

```starlark
kmp_maven = use_extension("@rules_kotlin//src/main/starlark/core/repositories:kmp_maven.bzl", "kmp_maven")
kmp_maven.install(
    name = "kmp_maven",
    artifacts = ["org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2"],
    manifest = "//:kmp_manifest.json",
)
use_repo(kmp_maven, "kmp_maven")
```

| Attribute       | Content                                                                                                                                                                                                      |
|-----------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `name`          | The hub repository of the libraries, to `use_repo`. Each install has its own name and manifest.                                                                                                              |
| `artifacts`     | The Maven coordinates, `group:artifact:version`.                                                                                                                                                             |
| `repositories`  | The Maven repositories, in the order the artifacts are looked up in; `https://repo1.maven.org/maven2` by default. Add `https://dl.google.com/dl/android/maven2` for AndroidX libraries.                        |
| `platforms`     | The platforms to resolve the artifacts for: `jvm`, `android` and the konan targets of `@rules_kotlin//kotlin/native/platforms` (`ios_arm64`, `ios_simulator_arm64`, `linux_arm64`, `linux_x64`, `macos_arm64`); all of them by default. |
| `substitutions` | Versions forced in the resolution, `group:artifact=group:artifact:version`.                                                                                                                                  |
| `extra_dependencies` | Dependencies the published metadata of a library omits, `{"group:artifact": ["group:artifact", ...]}`. Each is a dep of every variant of the library, for its platform, as the dependencies of the metadata are, and must be a library of the manifest (an artifact of the install or a dependency of one). The dexing of an `android_binary` desugars each library against its own dependencies and fails on a type they lack, e.g. a Compose type used by a Markdown renderer that does not declare Compose. |
| `excluded_artifacts` | Libraries of the manifest the hub leaves out, `group:artifact` each, as the `exclude` of a Gradle configuration: the library has no targets and the variants of the other libraries have no dep on it. E.g. `net.java.dev.jna:jna-jpms`, which the natives of vlcj depend on and which carries the packages of the `jna` other libraries depend on: shipping both leaves the winner to the classpath order. Not an input of the resolver, like `extra_dependencies`; the library must be in the manifest. |
| `ignore_published_checksums` | Libraries whose artifacts do not match the checksums their repository publishes, `group:artifact:version` of the exact library (the platform-specific variant of a KMP library, e.g. `me.tatarka.inject:kotlin-inject-runtime-iosarm64:0.9.0`, not its umbrella). The pin ignores the mismatch of these libraries only, and records the sha256 of the content it downloads as the integrity of their artifacts, which Bazel verifies every download against; the manifest lists them as `askedIgnoredPublishedChecksums`. Every other library keeps failing on a mismatch. |
| `manifest`      | The manifest, a file of a package of the root module. The pin target writes it.                                                                                                                              |
| `fetch_sources` | Whether to download the sources jars, as the `srcjar` of the JVM and Android imports; `False` by default.                                                                                                    |

Then depend on the alias of a library, `@<name>//:<group>_<artifact>` with every character but
letters and digits replaced by `_`, from any Kotlin rule. A multiplatform library lists it in the
`deps` of every platform whose sources use it: a fragment has no deps of its own, and each platform
compiles the sources it shares against its own deps, in which the alias is the variant of the
platform:

```starlark
COROUTINES = "@kmp_maven//:org_jetbrains_kotlinx_kotlinx_coroutines_core"

kt_multiplatform_library(
    name = "shared",
    jvm = dict(
        srcs = ["common/Greeting.kt", "jvm/Platform.jvm.kt"],
        deps = [COROUTINES],
    ),
    native = {"linux": dict(
        srcs = ["common/Greeting.kt", "linux/Platform.linux.kt"],
        targets = ["linux_x64"],
        deps = [COROUTINES],
    )},
)
```

The alias is the JVM variant for `shared_jvm`, a `kt_jvm_test` or any other JVM target, the Android
variant for an Android target, and the klib of the konan target for `shared_native` or any other
Kotlin/Native target: see [the generated targets](#the-generated-targets).

## Pinning the manifest

After adding an install, or changing its artifacts, repositories, platforms or substitutions, pin
its manifest and commit it. `extra_dependencies` and `excluded_artifacts` are no inputs of the
resolver: changing them does not make the manifest stale, and the named libraries must already be
in it:

```shell
bazel run @kmp_maven//pin
```

The pin target runs `bazel-kmp-resolver generate-bazel-manifest` with the inputs of the install and
writes the manifest at its path in the workspace; the resolver caches what it downloads under
`${XDG_CACHE_HOME:-~/.cache}/rules_kotlin/bazel-kmp-resolver`. More options of
`generate-bazel-manifest` follow `--`, e.g. `bazel run @kmp_maven//pin -- --help`.

While the manifest is missing, empty or stale, any target of the hub fails with the command to run,
e.g.:

```
@kmp_maven: the manifest kmp_manifest.json is stale: its askedCoordinates is ["org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.1"], but kmp_maven.install(name = "kmp_maven") declares ["org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2"]; run 'bazel run @kmp_maven//pin' and commit it
```

A manifest is stale when one of the inputs recorded in its header (`askedPlatforms`,
`askedCoordinates`, `askedRepositories`, `askedSubstitutions`, normalized as the resolver does)
differs from those of the install, or when its `schemaVersion` is not 2, the version rules_kotlin
reads. An empty file is a valid first manifest: `touch kmp_manifest.json`, then pin it.

### The resolver binary

Only the pin target needs the resolver, which it takes from the repository `bazel_kmp_resolver`:
the release asset of the host (`bazel-kmp-resolver-linux-x64`, `-linux-arm64`, `-macos-x64`,
`-macos-arm64` or `-windows-x64.exe`) of the release rules_kotlin pins,
[0.4.0](https://github.com/avan1235/bazel-kmp-resolver/releases/tag/0.4.0), downloaded and checked
against its sha256. Nothing needs to be set. Another release is pinned in the root module with the
sha256 of its assets:

```starlark
kmp_maven.resolver(
    version = "<version>",
    sha256 = {
        "linux-x64": "...",
        "macos-arm64": "...",
    },
)
```

The checksums of the tag override those rules_kotlin pins for the same version. A host without an
asset or a checksum cannot pin, and the pin target fails with what is missing; builds never need
the resolver.

### Downloads

A build fetches the repository of a Maven module, `<name>__<group>_<artifact>_<version>`, the first
time it builds a target that uses it, downloading its files from their URLs, checked against their
`integrity`, with the credentials of `~/.netrc` for private repositories. A Linux build of
`examples/kmp` downloads the Linux klibs and the JVM jars, and no Apple klib.

## The generated targets

Per library of the manifest, with `<lib>` its name, the group:artifact with every character but
letters and digits replaced by `_`, e.g. `org_jetbrains_kotlinx_kotlinx_coroutines_core`:

| Target                      | Content                                                                                                                                                                                  |
|-----------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `<lib>`                     | The alias of the library: `<lib>.native` for the Kotlin/Native rules, `<lib>.android` on `@platforms//os:android`, `<lib>.jvm` otherwise; `<lib>.jvm` alone for a JVM library.           |
| `<lib>.native`              | The alias of the klibs of the library: `<lib>.<t>` on `@rules_kotlin//kotlin/native/platforms:native_<t>`.                                                                                |
| `<lib>.<t>`                 | A `kt_klib_import` of the klib of konan target `<t>`, which exports the libraries the library exposes, and depends on its cinterop klibs and its other dependencies of `<t>`.             |
| `<lib>.<t>.cinterop_<n>`    | A `kt_klib_import` of the cinterop klib at position `<n>` (from 0) of the library for `<t>`, which binds a C library it uses.                                                              |
| `<lib>.android`             | An `aar_import` of the Android library, or a `kt_jvm_import` of its jar, with its dependencies of Android; an `android_library` exporting its dependencies of Android when the variant has no artifact (see below). |
| `<lib>.jvm`                 | A `kt_jvm_import` of the JVM jar of the library, with its dependencies of the JVM; a `kt_jvm_library` exporting its dependencies of the JVM when the variant has no artifact (see below). |

The targets of the variants are `<lib>.<platform>`, with a `.` the name of a library never
contains, so that a library whose artifact ends in `-android` or `-jvm` keeps its own alias: the
platform artifact of an AndroidX multiplatform library is one when a POM-only library depends on
it, e.g. `androidx.datastore:datastore-preferences-android`
(`androidx_datastore_datastore_preferences_android`) next to `androidx.datastore:datastore-preferences`
(whose Android variant is `androidx_datastore_datastore_preferences.android`).

The alias fails with the library, the platforms it was resolved for and the install when it has no
variant for its consumer, e.g. a Kotlin/Native target of a konan target missing from `platforms`,
or a JVM target of a library without JVM variant. `bazel query @kmp_maven//:all` lists the targets.

A library can publish a variant without artifact, which only declares dependencies: the Android
variants of the JetBrains Compose libraries (`org.jetbrains.compose.runtime:runtime`, …) redirect to
the AndroidX Compose ones (`androidx.compose.runtime:runtime`, …), and a POM-only library aggregates
others. The manifest records such a variant as a `redirect`, and its target is an `android_library`
or a `kt_jvm_library` without sources that exports the libraries it stands for, so that a consumer
of `@kmp_maven//:org_jetbrains_compose_runtime_runtime` on Android gets the AndroidX AARs, and the
JVM jar of the JetBrains library otherwise. An `android_library` has no runtime-only dependencies,
so the Android target exports every dependency of the variant; the `kt_jvm_library` keeps the
runtime-only ones in its `runtime_deps`. It is a `kt_jvm_library` without sources, which forwards
`JavaInfo` and `KtJvmInfo` without compiling anything. The `exports` of an `aar_import` can only be
imports (`aar_import`, `java_import`, `kt_jvm_import`), so an `aar_import` exporting a redirect
exports the imports the redirect stands for instead (following redirects to redirects), e.g. the
Android target of Coil's `coil-compose-core` exports `androidx_compose_foundation_foundation.android`
rather than `org_jetbrains_compose_foundation_foundation.android`; its `deps` keep the redirect.

## The Kotlin platform type

`--@rules_kotlin//kotlin/settings:kotlin_platform_type`, `jvm` or `native`, is the Bazel form of
the Gradle attribute `org.jetbrains.kotlin.platform.type`. It is `jvm` by default, which the JVM and
Android rules leave as it is, and the Kotlin/Native rules (`kt_native_library`, `kt_native_binary`,
`kt_native_test`, `kt_native_framework`, `kt_klib_import`) set it to `native` for themselves and
their deps with a rule transition. A `select()` tells a Kotlin/Native consumer from a JVM one with
the config_settings of `@rules_kotlin//kotlin/native/platforms`:

| config_setting | Matches                                                                                                    |
|----------------|------------------------------------------------------------------------------------------------------------|
| `native`       | The Kotlin/Native rules and their deps, whatever their konan target.                                       |
| `native_<t>`   | The Kotlin/Native rules building for konan target `<t>`, and their deps.                                   |
| `is_<t>`       | Any target built for the platform of `<t>`: the OS and CPU of a host of `<t>` included, JVM targets too.   |

A dependency that differs per platform, written by hand, selects its klibs on `native_<t>` and its
JVM library by default, as the aliases of `kmp_maven` and `kt_multiplatform_library` do:

```starlark
alias(
    name = "sqlite",
    actual = select({
        "@rules_kotlin//kotlin/native/platforms:native_linux_x64": ":sqlite_linux_x64",
        "@rules_kotlin//kotlin/native/platforms:native_macos_arm64": ":sqlite_macos_arm64",
        "@platforms//os:android": ":sqlite_android",
        "//conditions:default": ":sqlite_jvm",
    }),
)
```

`is_<t>` is no such key: a Linux x86_64 or macOS arm64 host platform matches `is_linux_x64` or
`is_macos_arm64`, so a JVM target built for the host would get the klib.

## Importing a klib by hand

`kt_klib_import` (`@rules_kotlin//kotlin:native.bzl`) makes a prebuilt klib of a konan target, e.g.
one pinned with `http_file`, a dependency of the Kotlin/Native rules, which compile against it and
link it like the klib of a `kt_native_library`:

```starlark
load("@rules_kotlin//kotlin:native.bzl", "kt_klib_import")

kt_klib_import(
    name = "foo_linux_x64",
    klib = "@foo_linux_x64_klib//file",  # an http_file with downloaded_file_path = "foo-linuxx64-1.0.klib"
    konan_target = "linux_x64",
    deps = [":foo_linux_x64_cinterop"],  # klibs it depends on, linked with it
    exports = [":bar_linux_x64"],  # klibs its consumers also compile against
)
```

Its deps and exports are klibs of the same konan target, and so are its consumers: a mismatch fails
the analysis, as for `kt_native_library`.

## Limitations

- Only the root module declares installs, and each install has one manifest. The resolution has no
  exclusions and no conflict resolution between installs.
- `wasmjs` is not supported, as rules_kotlin has no Kotlin/Wasm rules: its variants and NPM packages
  are left out of the hub.
- The install declares no credentials for the resolver: pass its own options for private Maven
  repositories to the pin target, e.g.
  `bazel run @kmp_maven//pin -- --credential-helper=/path/to/helper` or
  `--repository-credentials-file=...`. Builds download with the credentials of `~/.netrc`.
- The platform type follows the rule transition of the Kotlin/Native rules: the `data` of a
  Kotlin/Native target and its exec tools, e.g. its compiler plugins, are built with `native` too,
  and a rule that only changes the platform, like `platform_transition_filegroup`, keeps `jvm`:
  transition a Kotlin/Native target, e.g. `//shared:shared_native`, rather than an alias.
- The JVM variants depend on the `kotlin-stdlib` jar of the manifest (2.1.0 for
  `kotlinx-coroutines-core:1.10.2`) next to the standard library of the Kotlin toolchain, as with
  `rules_jvm_external`; a substitution aligns it, e.g.
  `org.jetbrains.kotlin:kotlin-stdlib=org.jetbrains.kotlin:kotlin-stdlib:2.4.21`.
- The klibs of Maven libraries are built by the Kotlin release of each library, which the Kotlin/Native
  compiler of the toolchain must be able to read.
- A pin fails with `Hashes do not match` on a library published with checksums its files do not
  match (Gradle, verifying nothing, resolves it anyway). Check the file against its published
  checksum (`curl -s <url> | shasum -a 256` vs `<url>.sha256`) and, if the publisher is at fault,
  list that exact library in `ignore_published_checksums`: its mismatch alone is ignored, and the
  manifest pins the sha256 of the downloaded content.
