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
| `manifest`      | The manifest, a file of a package of the root module. The pin target writes it.                                                                                                                              |
| `fetch_sources` | Whether to download the sources jars, as the `srcjar` of the JVM and Android imports; `False` by default.                                                                                                    |

Then depend on the alias of a library, `@<name>//:<group>_<artifact>` with every character but
letters and digits replaced by `_`, from any Kotlin rule, or from the common source set of a
multiplatform library:

```starlark
kt_multiplatform_library(
    name = "shared",
    common_deps = ["@kmp_maven//:org_jetbrains_kotlinx_kotlinx_coroutines_core"],
    common_srcs = ["common/Greeting.kt"],
    jvm = dict(srcs = ["jvm/Platform.jvm.kt"]),
    native = {"linux": dict(srcs = ["linux/Platform.linux.kt"], targets = ["linux_x64"])},
)
```

The alias is the JVM variant for `shared_jvm`, a `kt_jvm_test` or any other JVM target, the Android
variant for an Android target, and the klib of the konan target for `shared_native` or any other
Kotlin/Native target: see [the generated targets](#the-generated-targets).

## Pinning the manifest

After adding an install, or changing its artifacts, repositories, platforms or substitutions, pin
its manifest and commit it:

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

Per library of the manifest, with `<lib>` its name, e.g. `org_jetbrains_kotlinx_kotlinx_coroutines_core`:

| Target                      | Content                                                                                                                                                                                  |
|-----------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `<lib>`                     | The alias of the library: `<lib>_native` for the Kotlin/Native rules, `<lib>_android` on `@platforms//os:android`, `<lib>_jvm` otherwise; `<lib>_jvm` alone for a JVM library.           |
| `<lib>_native`              | The alias of the klibs of the library: `<lib>_<t>` on `@rules_kotlin//kotlin/native/platforms:native_<t>`.                                                                                |
| `<lib>_<t>`                 | A `kt_klib_import` of the klib of konan target `<t>`, which exports the libraries the library exposes, and depends on its cinterop klibs and its other dependencies of `<t>`.             |
| `<lib>_<t>_cinterop_<n>`    | A `kt_klib_import` of the cinterop klib at position `<n>` (from 0) of the library for `<t>`, which binds a C library it uses.                                                              |
| `<lib>_android`             | An `aar_import` of the Android library, or a `kt_jvm_import` of its jar, with its dependencies of Android.                                                                               |
| `<lib>_jvm`                 | A `kt_jvm_import` of the JVM jar of the library, with its dependencies of the JVM.                                                                                                       |

The alias fails with the library, the platforms it was resolved for and the install when it has no
variant for its consumer, e.g. a Kotlin/Native target of a konan target missing from `platforms`,
or a JVM target of a library without JVM variant. `bazel query @kmp_maven//:all` lists the targets.

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
