# Kotlin/Native and Kotlin Multiplatform

Experimental. rules_kotlin compiles Kotlin/Native code into klibs and links them into executables,
test runners and static Apple frameworks, and it declares Kotlin Multiplatform (KMP) modules whose
common code compiles for the JVM, Android and Kotlin/Native, as the Kotlin Gradle plugin does. The
rules, their attributes and their module extensions may change in any release.

This guide covers the setup, the platforms, the rules, the mapping from a Gradle KMP project and the
integration with Android and iOS apps. The attributes of each rule are in the
[API reference](kotlin.md), and the Maven dependencies of multiplatform code in
[Kotlin Multiplatform dependencies](kmp_dependencies.md).

## Status and prerequisites

- **Exec hosts**: Linux x86_64 and macOS arm64, the hosts of the Kotlin/Native distributions. There
  is no Windows, Linux arm64 or macOS x86_64 exec host; the JVM and Android builds of those hosts are
  unaffected.
- **Konan targets**: `linux_x64` and `linux_arm64` on both hosts; `macos_arm64`, `ios_arm64` and
  `ios_simulator_arm64` on macOS only.
- **Xcode**: the Apple targets need a macOS host with Xcode, whose SDK konanc finds with `xcrun`:
  Xcode 15.4 or newer for Kotlin/Native 2.5.20-dev-5696 (`minimalXcodeVersion` of its
  `konan.properties`).
- **Compiler**: Kotlin/Native 2.5.20-dev-5696, a dev build of the next Kotlin release, which compiles
  klibs through the Kotlin Build Tools API (see
  [The Kotlin/Native Build Tools API](#the-kotlinnative-build-tools-api)). It is pinned apart from the
  Kotlin compiler of the JVM toolchain, 2.4.21, as klibs are coupled to the Kotlin/Native compiler
  that produced them; `kotlin_native.version(version = "2.4.21")` stays on the release.
- **Bazel**: the rules build with Bazel 7 and newer (`examples/native` runs with 7.x, 8.x and 9.3.1).
  `examples/kmp` and `examples/kmp_app` need Bazel 8.4.2 or newer, as they get the Android SDK (and
  `examples/kmp_app` the Android NDK) from `hermetic_android_toolchains`; `examples/kmp_app` also
  builds its iOS app with rules_apple 5.x, which dropped Bazel 7.
- **Android**: an Android app, `android_binary`, needs the Android SDK and, even without native code,
  the Android NDK, whose C++ toolchain it resolves for the Android platform.
  `hermetic_android_toolchains` downloads both once `.bazelrc` accepts their licenses: see
  [The Android app](#the-android-app).
- **Network**: no action needs it. The Kotlin/Native distribution, its link dependencies and its Build
  Tools API, like the Android SDK and NDK, are Bazel repositories, fetched before any action runs, and
  the examples build with `--sandbox_default_allow_network=false`.

## The `kotlin_native` module extension

rules_kotlin registers a Kotlin/Native toolchain per exec host and konan target. Their repositories
come from the `kotlin_native` module extension, two per exec host and one for the release:

- `com_github_jetbrains_kotlin_native_<host>`: the prebuilt distribution,
  `kotlin-native-prebuilt-<host>-<version>` from the GitHub releases of JetBrains/kotlin, or from the
  Kotlin dev Maven repository (`redirector.kotlinlang.org/maven/dev`) for a dev build such as
  2.5.20-dev-5696. It compiles klibs for every konan target of the host, with the standard library
  and the platform libraries of the target, e.g. `platform.posix` or `platform.UIKit`.
- `com_github_jetbrains_kotlin_native_deps_<host>`: the link dependencies of the targets of
  `kotlin_native.targets(...)`, from `download.jetbrains.com`: the LLVM and libffi of the host, lldb
  for the host's own target, the GCC cross-toolchain of a Linux target and, on a Linux host, the qemu
  emulator of `linux_arm64`. The iOS targets add none, as Xcode provides their toolchain and SDK.
- `com_github_jetbrains_kotlin_native_btapi`: the jars of the Kotlin/Native Build Tools API
  implementation of the release, from Maven Central, or from the Kotlin dev Maven repository for a dev
  build; empty for a release without one (see
  [The Kotlin/Native Build Tools API](#the-kotlinnative-build-tools-api)).

A build fetches them when it builds a Kotlin/Native target, for its exec host only: JVM-only builds
download nothing.

The root module configures the extension with two tags, which other modules cannot declare:

```starlark
kotlin_native = use_extension("@rules_kotlin//src/main/starlark/core/repositories:native.bzl", "kotlin_native")
kotlin_native.targets(targets = ["ios_arm64", "ios_simulator_arm64"])
```

| Tag       | Attributes                                                                          | Effect                                                                                                                                                                                                                                                                       |
|-----------|-------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `targets` | `targets`: konan targets.                                                           | The targets to stage link dependencies for; all of them without the tag. klibs compile for every target regardless, but `kt_native_binary`, `kt_native_test` and `kt_native_framework` link only for these: another target fails with `add '<t>' to kotlin_native.targets(...) in the root MODULE.bazel`. |
| `version` | `version`, and `sha256`: the checksum of the archive per exec host, `linux-x86_64` and `macos-aarch64`; `btapi_sha256`: the checksums of the Build Tools API implementation (see [The Kotlin/Native Build Tools API](#the-kotlinnative-build-tools-api)). | Another Kotlin/Native release than 2.5.20-dev-5696: a release, from GitHub, or a dev build, from the Kotlin dev Maven repository. An archive without checksum downloads unverified. The link dependencies are staged with the LLVM of the release: rules_kotlin pins the LLVM of the releases it pins (LLVM 21 for 2.5.20-dev-5696 and 2.4.21), and checks the bundle against the `konan.properties` of the release when it is fetched. A release without a pinned LLVM, or one that needs other dependencies, fails with the differences, naming the archives to add to `KOTLIN_NATIVE_LLVM` and `KOTLIN_NATIVE_ARCHIVES` of `src/main/starlark/core/repositories/native_compiler.bzl`; with `kotlin_native.targets(targets = [])` its klibs still compile. |

List the targets the build links for: the link dependencies are large archives. The iOS targets of
`examples/kmp_app` add nothing to the LLVM and libffi of a macOS host, while `examples/native`, which
links for every target, lists all five.

<!-- BEGIN generated by scripts/upgrade_kotlin.sh: older releases -->
<!-- END generated by scripts/upgrade_kotlin.sh: older releases -->

<!-- BEGIN generated by scripts/upgrade_kotlin.sh: older Kotlin/Native releases -->
### Staying on Kotlin/Native 2.4.21

rules_kotlin defaults to Kotlin/Native 2.5.20-dev-5696. A root module that stays on Kotlin/Native
2.4.21 selects it in its `MODULE.bazel`; rules_kotlin pins the distributions and the LLVM of
2.4.21, so the tag needs no checksums.

```starlark
kotlin_native = use_extension("@rules_kotlin//src/main/starlark/core/repositories:native.bzl", "kotlin_native")
kotlin_native.version(version = "2.4.21")
```

It has no Kotlin/Native Build Tools API: its klibs compile with the konanc command
line, whatever `experimental_native_build_tools_api` says.
<!-- END generated by scripts/upgrade_kotlin.sh: older Kotlin/Native releases -->

## The Kotlin/Native Build Tools API

A Kotlin/Native klib compilation, that of a `kt_native_library`, of the native libraries of a
`kt_multiplatform_library` and of the private klib of `kt_native_binary`, `kt_native_test` and
`kt_native_framework`, runs a `NativeKlibCompilationOperation` of the
[Kotlin Build Tools API](https://youtrack.jetbrains.com/issue/KT-78202) in-process in its action,
instead of the konanc command line. It gets the same flags and writes the same klib and header klib,
its diagnostics name the sources relative to the execroot, and the action keeps the mnemonic
`KotlinNativeKlibCompile` and its exit codes. A link, which produces a program or a framework, runs
the konanc command line: the Build Tools API has no link operation.

The build setting `experimental_native_build_tools_api`, on by default, chooses the entry point of
klib compilations without changing the release:

```shell
bazel build //... --@rules_kotlin//kotlin/settings:experimental_native_build_tools_api=false
```

The action loads `kotlin-build-tools-impl`, `kotlin-build-tools-cri-impl` and `kotlin-daemon-client`
of the release, which are inputs of the action, with the compiler jar of the distribution; the
launcher of the action bundles the API. rules_kotlin pins those jars per release, in
`KOTLIN_NATIVE_BTAPI` of `src/main/starlark/core/repositories/native_compiler.bzl`. A release without
them compiles klibs with the konanc command line, whatever the build setting says: a release older
than 2.5.20-dev-4986, such as 2.4.21, has no Kotlin/Native Build Tools API, and the tag of a release
rules_kotlin does not pin gives their checksums with `btapi_sha256`, all three or none, from the
`.sha256` file next to each jar in Maven:

```starlark
kotlin_native = use_extension("@rules_kotlin//src/main/starlark/core/repositories:native.bzl", "kotlin_native")
kotlin_native.version(
    btapi_sha256 = {
        "kotlin-build-tools-cri-impl": "<sha256>",
        "kotlin-build-tools-impl": "<sha256>",
        "kotlin-daemon-client": "<sha256>",
    },
    sha256 = {
        "linux-x86_64": "<sha256>",
        "macos-aarch64": "<sha256>",
    },
    version = "<version>",
)
```

- The operation is experimental upstream. It runs in-process only, without the Kotlin daemon,
  incremental compilation or a persistent worker, and the compiler gets its flags as command-line
  arguments.
- A compiler plugin of a Kotlin/Native compilation runs in the Kotlin/Native compiler of the release,
  whatever the JVM toolchain: its `kt_compiler_plugin` needs the plugin artifact of that release,
  e.g. of its dev build, on both entry points.
- KSP of a native target (see [KSP for a multiplatform library](#ksp-for-a-multiplatform-library))
  is a separate action: `examples/kmp` runs it with Kotlin/Native 2.5.20-dev-5696.

## Konan targets and platforms

The konan target is not an attribute of the compiling and linking rules (a `kt_klib_import` names
the one of its klib): Bazel's toolchain resolution picks the toolchain of the build's target
platform. The host platform builds for the konan target of the host, `linux_x64` or `macos_arm64`,
and `@rules_kotlin//kotlin/native/platforms` has a platform per target:

| Konan target          | Constraints of the platform                                                  | Exec hosts                |
|-----------------------|------------------------------------------------------------------------------|---------------------------|
| `linux_x64`           | `@platforms//os:linux`, `@platforms//cpu:x86_64`                             | Linux x86_64, macOS arm64 |
| `linux_arm64`         | `@platforms//os:linux`, `@platforms//cpu:aarch64`                            | Linux x86_64, macOS arm64 |
| `macos_arm64`         | `@platforms//os:macos`, `@platforms//cpu:aarch64`                            | macOS arm64               |
| `ios_arm64`           | `@platforms//os:ios`, `@platforms//cpu:aarch64`, apple_support's `device`    | macOS arm64               |
| `ios_simulator_arm64` | `@platforms//os:ios`, `@platforms//cpu:aarch64`, apple_support's `simulator` | macOS arm64               |

```shell
bazel build //:greeter --platforms=@rules_kotlin//kotlin/native/platforms:linux_arm64
```

One target builds for another platform below a `platform_transition_filegroup` of bazel_lib, as
`examples/native` builds a klib for each konan target. Any platform with the constraints of a target
selects its toolchain, e.g. the iOS platforms of apple_support that `ios_application` builds for
(see [The iOS app](#the-ios-app)).

Builds for different `--platforms` share the output directory of the host's `--cpu`, so they
overwrite each other's outputs. A `platform_mappings` file at the root of the workspace that maps each
platform to a `--cpu` gives each target its own, as in `examples/native` and `examples/kmp`:

```
platforms:
  @rules_kotlin//kotlin/native/platforms:ios_arm64
    --cpu=ios_arm64
  @rules_kotlin//kotlin/native/platforms:ios_simulator_arm64
    --cpu=ios_sim_arm64
  @rules_kotlin//kotlin/native/platforms:linux_arm64
    --cpu=aarch64
  @rules_kotlin//kotlin/native/platforms:linux_x64
    --cpu=k8
  @rules_kotlin//kotlin/native/platforms:macos_arm64
    --cpu=darwin_arm64
```

The package also has the config_settings to `select()` on: `is_<t>` (the platform of `<t>`),
`native_<t>` (a Kotlin/Native rule building for `<t>`, and its deps) and `native` (any Kotlin/Native
rule): see [The Kotlin platform type](kmp_dependencies.md#the-kotlin-platform-type).

## The rules

`@rules_kotlin//kotlin:native.bzl` has the Kotlin/Native rules. They build for the konan target of
the build's platform, with the Kotlin platform type `native`, and their deps are klibs of that target:
`kt_native_library` and `kt_klib_import` targets, or aliases that select them.

| Rule                                                   | Output             | Purpose                                                                                                                                                                                                 |
|--------------------------------------------------------|--------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`kt_native_library`](kotlin.md#kt_native_library)     | `<name>.klib`      | Compiles Kotlin sources into a klib. Its `exports` are klibs its dependents compile against too.                                                                                                        |
| [`kt_native_binary`](kotlin.md#kt_native_binary)       | `<name>.kexe`      | Links an executable, which `bazel run` runs on a host of its target. Its `main` is in the `srcs` or in a dep.                                                                                            |
| [`kt_native_test`](kotlin.md#kt_native_test)           | `<name>.kexe`      | Links the `kotlin.test` tests of its sources into a test runner, which `bazel test` runs, for the konan target of the exec host. Its `associates` are libraries whose internal declarations it sees; runner options, e.g. `--ktest_filter=<pattern>`, go in `args` or `--test_arg`. |
| [`kt_native_framework`](kotlin.md#kt_native_framework) | `<name>.framework` | Links a static Apple framework, named after the target like the prefix of its Objective-C names, whose header declares the API of its `srcs` and `exports` (and of their exports, unless `transitive_exports = False`). `bundle_id` is its `CFBundleIdentifier`. |
| [`kt_klib_import`](kotlin.md#kt_klib_import)           | the `klib`         | A prebuilt klib of one `konan_target`, e.g. of a Maven library, as a dep.                                                                                                                               |

The linking rules compile their sources, if any, into a private klib, `_kt_native/<name>.klib`, and
link it with the klibs of their deps, as the Kotlin Gradle plugin does: `opts` are options of the
compilation and `link_opts` options of the link, e.g. `-opt`. `kt_native_library` and the linking
rules also take Kotlin compiler `plugins` (`kt_compiler_plugin`), and `kt_native_library` compiles
the sources a `kt_multiplatform_library` shares (see [`kt_multiplatform_library`](#kt_multiplatform_library)).
[`KtKlibInfo`](kotlin.md#KtKlibInfo) is the provider of a klib.

```starlark
load("@rules_kotlin//kotlin:native.bzl", "kt_native_binary", "kt_native_library", "kt_native_test")

kt_native_library(
    name = "greeter",
    srcs = ["Greeter.kt"],
)

kt_native_binary(
    name = "hello",
    srcs = ["Hello.kt"],
    deps = [":greeter"],
)

kt_native_test(
    name = "greeter_test",
    srcs = ["GreeterTest.kt"],
    associates = [":greeter"],
)
```

### Frameworks and the `framework_files` output group

`kt_native_framework` links a static framework (`-Xstatic-framework`) for an Apple konan target, and
fails for another one: its `target_compatible_with`, e.g. `["@platforms//os:ios"]`, skips it there.
Its default output is the `<name>.framework` directory. The output group `framework_files` holds the
four files of the framework, copied out of the directory into `_kt_native/<name>.framework/` when a
build requests them:

| File                       | Content                                                                                    |
|----------------------------|--------------------------------------------------------------------------------------------|
| `<name>`                   | The static library.                                                                        |
| `Headers/<name>.h`         | The umbrella header: the Objective-C API of the `srcs` and of the exported klibs.          |
| `Modules/module.modulemap` | The module map, through which Swift imports the module `<name>`.                           |
| `Info.plist`               | The property list of the bundle; for `macos_arm64`, the `Resources/Info.plist` of its versioned layout. |

rules_apple's `apple_static_framework_import` imports a framework from its files, not from a
directory, so a `filegroup` of the output group bridges the two:

```starlark
filegroup(
    name = "Shared_files",
    srcs = [":Shared"],
    output_group = "framework_files",
)
```

The link always gets the whole closure of the `deps` and `exports`; what the header declares is the
API of the `exports` (`-Xexport-library`). By default it includes their own exports too, as Bazel's
`exports` are transitive; `transitive_exports = False` restricts it to the listed klibs, as a
framework of the Kotlin Gradle plugin exports only the libraries its `export()` names (its
`transitiveExport` is off by default). A module whose `api` dependencies are Compose or Ktor keeps
them out of its Objective-C header that way: `kt_native_framework(name = "shared", exports =
["//app/shared"], transitive_exports = False)` declares the API of `app/shared` alone.

[The iOS app](#the-ios-app) shows the rest.

## `kt_multiplatform_library`

`@rules_kotlin//kotlin:kmp.bzl` has the multiplatform rules:
[`kt_multiplatform_library`](kotlin.md#kt_multiplatform_library), and the rules of
[KSP for a multiplatform library](#ksp-for-a-multiplatform-library).

`kt_multiplatform_library` declares a Kotlin Multiplatform module as the Kotlin Gradle plugin builds
one: a library per platform, which compiles the sources it shares with other platforms and its own
in one compilation, as the K2 fragments of a multiplatform module (`-Xmulti-platform`), so that the
`expect` declarations of the shared code and the `actual` ones of the platform are in one module,
and an alias that selects the library of its consumer. It is declared along the default hierarchy
of Kotlin Multiplatform, as a module of the Kotlin Toolchain is: `platforms` lists the platforms of
the module, the `srcs`, `deps`, `exports` and `plugins` of the macro are those of every platform,
and a group or a platform of the hierarchy has lists of its own, e.g. `srcs_ios`, as in
`examples/kmp_app`:

```starlark
load("@rules_kotlin//kotlin:kmp.bzl", "kt_multiplatform_library")

COMMON = glob(["src/commonMain/kotlin/**/*.kt"])

COROUTINES = "@kmp_maven//:org_jetbrains_kotlinx_kotlinx_coroutines_core"

kt_multiplatform_library(
    name = "shared",
    srcs = COMMON,
    android = dict(
        custom_package = "org.example.kmpapp",
        manifest = "src/androidMain/AndroidManifest.xml",
    ),
    platforms = [
        "jvm",
        "android",
        "ios_arm64",
        "ios_simulator_arm64",
    ],
    srcs_android = glob(["src/androidMain/kotlin/**/*.kt"]),
    srcs_ios = glob(["src/iosMain/kotlin/**/*.kt"]),
    srcs_jvm = glob(["src/jvmMain/kotlin/**/*.kt"]),
    visibility = ["//visibility:public"],
    deps = [COROUTINES],
)
```

### The hierarchy

The groups and platforms of the macro are those of the default hierarchy of Kotlin Multiplatform:

```
common
 ├─ jvm
 ├─ android
 ╰─ native
     ├─ linux
     │   ├─ linux_x64
     │   ╰─ linux_arm64
     ╰─ apple
         ├─ macos
         │   ╰─ macos_arm64
         ╰─ ios
             ├─ ios_arm64
             ├─ ios_simulator_arm64
             ╰─ ios_x64
```

Its inner nodes are groups and its leaves are platforms. `platforms`, which the macro requires,
lists the platforms the library builds for, in any order: `jvm`, `android`, and the konan targets
`ios_arm64`, `ios_simulator_arm64`, `macos_arm64`, `linux_x64` and `linux_arm64`. As in the
`product.platforms` of the Kotlin Toolchain, a group is not a platform. `ios_x64` has its place in the
tree, but no Kotlin/Native toolchain yet. The macro declares `<name>_jvm` when `platforms` lists
`jvm`, `<name>_android` when it lists `android`, and `<name>_native` when it lists konan targets.

The lists of a group or a platform are `<attr>_<qualifier>`: `<attr>` is `srcs`, `deps`, `exports` or
`plugins`, and `<qualifier>` the name of a group or a platform below `common`, e.g. `srcs_native`,
`deps_apple`, `plugins_ios`, `exports_linux`, `srcs_ios_arm64` or `deps_jvm`. The `srcs`, `deps`,
`exports` and `plugins` of the macro are the lists of `common`. Each is a plain list of labels, and an
empty one is the same as none, so a wrapper macro can pass a `glob()` for every group. The `deps`,
`exports` and `plugins` of `jvm` and `android`, whose libraries build a single platform, may also be,
or end with, a `select()`. Each platform receives, per attribute, the lists of its lineage, from
`common` down to itself:

| Platform    | `deps` of its library                                         |
|-------------|---------------------------------------------------------------|
| `jvm`       | `deps + deps_jvm`                                             |
| `android`   | `deps + deps_android`                                         |
| `ios_arm64` | `deps + deps_native + deps_apple + deps_ios + deps_ios_arm64` |
| `linux_x64` | `deps + deps_native + deps_linux + deps_linux_x64`            |

`exports` and `plugins` propagate the same way, and the `srcs` make the fragments (see
[Fragments](#fragments)). A dep resolves for every platform that receives it: in the lists of
`common` and of the groups, an alias that selects the variant of the platform, such as those of
`kmp_maven`, or another `kt_multiplatform_library`; in those of `jvm` and `android`, JVM libraries;
in those below `native`, klibs of the konan target or aliases that select them. A JVM library alone
fails the native library, which takes klibs only. `plugins` are `kt_compiler_plugin` targets, the
only kind of plugin `kt_native_library` takes; KSP runs as a separate action instead: see
[KSP for a multiplatform library](#ksp-for-a-multiplatform-library).

`jvm`, `android` and `native` are dicts of the other attributes of `<name>_jvm`, `<name>_android` and
`<name>_native`, e.g. `resources`, `manifest`, `custom_package`, `opts` or `module_name`: the macro
sets their `srcs`, `deps`, `exports`, `plugins` and `kmp_fragments` itself. `native` applies to every
konan target of the library, and a value that differs per target is a `select()`, on
`@rules_kotlin//kotlin/native/platforms:is_<konan target>` or on `@platforms` constraints:

```starlark
native = dict(opts = select({
    "@rules_kotlin//kotlin/native/platforms:is_linux_arm64": ["-opt-in=kotlin.ExperimentalStdlibApi"],
    "//conditions:default": [],
})),
```

A `target_compatible_with` in `native`, or passed to the macro, narrows the compatibility of the
native library with its konan targets rather than replacing it. The macro takes no `runtime_deps`,
`data` or `opts` itself: they go in the dict of the library that has them. Its other keyword
arguments, e.g. `features`, go to every target it declares.

The declaration maps that of a module of the Kotlin Toolchain:

| Kotlin Toolchain                              | `kt_multiplatform_library`                           |
|-----------------------------------------------|------------------------------------------------------|
| `product.platforms: [jvm, android, iosArm64]` | `platforms = ["jvm", "android", "ios_arm64"]`        |
| `src/`, `dependencies:`                       | `srcs`, `deps`, `exports`, `plugins`                 |
| `src@ios/`, `dependencies@ios:`               | `srcs_ios`, `deps_ios`, `exports_ios`, `plugins_ios` |
| `settings@android:`                           | `android = dict(...)`, likewise `jvm` and `native`   |
| Lists appended from common to specific        | The same, per attribute                              |
| `aliases:`                                    | Not provided                                         |

A Bazel keyword cannot hold `@`, so the qualifier follows `_`: `srcs@ios` is `srcs_ios`.

### Checks

The macro checks the declaration when it is called, before any `select()` is resolved, comparing
labels as it compares the `srcs` (`a.kt`, `:a.kt` and `//shared:a.kt` are one label). It fails with
`kt_multiplatform_library <name>: <message>`, whose names come from the hierarchy:

| Declaration                                         | Message                                                                                                                                                       |
|-----------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------|
| No `platforms`, or an empty list                    | `it declares no platforms: list them in platforms, e.g. ["jvm", "android", "ios_arm64"]`                                                                      |
| A group in `platforms`                              | `platforms lists the group 'ios': list the platforms to build for instead, among ios_arm64, ios_simulator_arm64`                                              |
| An unknown name in `platforms`                      | `platforms lists the unknown platform 'ios_arm'; the supported ones are android, ios_arm64, ...`, with a hint for a label                                      |
| A platform no library builds yet                    | `platform 'ios_x64' is not supported yet: rules_kotlin has no Kotlin/Native toolchain for it`                                                                 |
| A platform listed twice                             | `platforms lists 'jvm' twice`                                                                                                                                 |
| An unknown qualifier                                | `srcs_iso: 'iso' is neither a group nor a platform; the groups are apple, ios, linux, macos, native and the platforms android, ...`                          |
| `common` as a qualifier                             | `srcs_common: the sources of every platform are the srcs of the macro`                                                                                        |
| Another attribute with a qualifier                  | `opts_ios: only srcs, deps, exports and plugins take a group or a platform`                                                                                   |
| Entries of a group none of whose platforms is listed | `srcs_ios lists sources, but platforms lists no ios platform: add ios_arm64 or ios_simulator_arm64, or remove srcs_ios`                                     |
| Entries of a platform that is not listed            | `deps_linux_x64 lists deps, but platforms does not list linux_x64`                                                                                            |
| A `select()` where a plain list is required         | `srcs_ios must be a list of labels, not a select: ...`                                                                                                        |
| A label twice in one list                           | `srcs_ios lists a.kt twice`                                                                                                                                   |
| A label that a list above already lists             | `deps_ios lists :lib, which deps_apple already lists`, or `which the deps of the macro already list`                                                          |
| Settings of a library that is not declared          | `android sets attributes of the Android library, but platforms does not list android`                                                                         |
| An attribute the macro sets, in a settings dict     | `jvm sets srcs: pass srcs_jvm to the macro`; `native sets kmp_fragments, which the macro derives from the sources`                                            |
| A dict of attributes for another node               | `ios: only jvm, android and native take a dict of attributes of their library`                                                                                |

The macro cannot read the labels of a `select()` in the `deps`, `exports` or `plugins` of `jvm` or
`android`, which comes after the lists above it: Bazel reports a label repeated there instead, as
`Label '<label>' is duplicated in the 'deps' attribute of rule '<name>_jvm'`.

### Fragments

The macro derives the fragments of the compilations from the owners of each source: the groups and
platforms whose srcs list it.

- The sources of a group form one fragment named after it: `common` for the `srcs` of the macro,
  `ios` for `srcs_ios`. Its platforms are the listed platforms at or below the group: above, every
  platform compiles `common`, and both iOS targets compile `ios`.
- A fragment refines the fragments directly above it, as a Gradle source set depends on another:
  `ios` refines `common`, or `apple` when `srcs_apple` lists sources. Groups of the same platforms
  stay apart: in a library of iOS targets only, `common`, `native`, `apple` and `ios` are four
  fragments, so an `expect` declaration in one and its `actual` in a lower one compile.
- The sources of a platform stay in the library of that platform as its leaf fragment, named after
  the platform, `jvm`, `android` or the konan target, which refines the fragments directly above the
  platform. A leaf may be empty: `ios_arm64` and `ios_simulator_arm64` are, as both targets compile
  the fragment `ios`.

The library of a platform compiles every fragment of its platform, most shared first, each after
those it refines, then its leaf, in one compilation (`-Xfragments`, `-Xfragment-sources` and
`-Xfragment-refines`): with sources in each of those groups, the native library built for the iOS
simulator gets `-Xfragments=common,native,apple,ios,ios_simulator_arm64`. A fragment has no deps:
each platform compiles all its fragments against the deps of its lineage, which resolve in its
configuration, JVM libraries for the JVM and Android and klibs of the konan target for
Kotlin/Native. So the deps of the sources of a group are in the deps of that group or above, and
those of the common code once in the `deps` of the macro, which every platform resolves: an alias
that selects the variant of the platform, like those of `kmp_maven`, is one label for all of them.

A source set of the Gradle build outside the default hierarchy is a list that the groups and
platforms compiling it all list, none above another: its sources form a fragment named after them,
sorted and joined with `-`, as `examples/kmp` does with Gradle's `nonAndroidMain`:

```starlark
COMMON = glob(["common/**/*.kt"])

NON_ANDROID = glob(["non_android/**/*.kt"])  # Gradle's nonAndroidMain: every platform but Android

kt_multiplatform_library(
    name = "shared",
    srcs = COMMON,
    android = dict(...),
    platforms = ["jvm", "android", "ios_arm64", "macos_arm64"],
    srcs_android = glob(["android/**/*.kt"]),
    srcs_apple = glob(["apple/**/*.kt"]),
    srcs_jvm = NON_ANDROID + glob(["jvm/**/*.kt"]),
    srcs_native = NON_ANDROID,
    deps = DEPS,
)
```

| Sources                           | Fragment                                    | Refines      |
|-----------------------------------|---------------------------------------------|--------------|
| `COMMON`, the `srcs` of the macro | `common`                                    |              |
| `NON_ANDROID`                     | `jvm-native`                                | `common`     |
| `apple/`                          | `apple`                                     | `jvm-native` |
| `jvm/`                            | `jvm`, the leaf of the JVM                  | `jvm-native` |
| `android/`                        | `android`, the leaf of Android              | `common`     |
| None                              | `ios_arm64` and `macos_arm64`, empty leaves | `apple`      |

`examples/kmp` also lists `linux_arm64` and `linux_x64`, whose `srcs_linux` are the fragment `linux`,
which refines `jvm-native` too.

`bazel run //<pkg>:<name>.fragments` prints the derived fragment graph — each `fragment` and
platform `leaf`, the fragments it `refines`, the `platforms` compiling a fragment, and its own
`srcs` — without compiling or fetching platform toolchains.

### The declared targets

| Target                       | Rule                                | Content                                                                                                                                                                                                                                                        |
|------------------------------|-------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `shared_fragment_<fragment>` | `kt_kmp_fragment` (internal)        | A private target per fragment, e.g. `shared_fragment_ios`: its sources and the fragments it refines. It compiles nothing by itself.                                                                                                                           |
| `shared_jvm`                 | `kt_jvm_library`                    | When `platforms` lists `jvm`: the attributes of `jvm` and the lists of its lineage; it compiles the fragments of the JVM and its leaf.                                                                                                                         |
| `shared_android`             | `kt_android_library`                | When `platforms` lists `android`: the attributes of `android` and the lists of its lineage; it compiles the fragments of Android and its leaf.                                                                                                                 |
| `shared_native`              | `kt_native_library`                 | When `platforms` lists konan targets: for the konan target of the build's platform, the fragments of that target and its leaf, against the lists of its lineage, with the attributes of `native`. It is incompatible with the other platforms.                |
| `shared_srcs`                | `filegroup`                         | The sources of every platform.                                                                                                                                                                                                                                 |
| `shared.fragments`           | `kt_kmp_fragments_graph` (internal) | An executable target (`bazel run //<pkg>:shared.fragments`) that prints the derived fragments, their `refines` edges, their platforms and their sources.                                                                                                       |
| `shared`                     | `alias`                             | `shared_native` for a Kotlin/Native consumer, `shared_android` on `@platforms//os:android`, and otherwise `shared_jvm` (or, without `jvm`, `shared_android`, then `shared_native`).                                      |

A consumer depends on the alias or on the library of a platform. The libraries get their fragments
through an internal attribute, `kmp_fragments`, which only the macro sets.

The alias tells a Kotlin/Native consumer from a JVM one by the Kotlin platform type,
`@rules_kotlin//kotlin/settings:kotlin_platform_type`: `jvm` by default, and `native` for the
Kotlin/Native rules and their deps, which set it with a rule transition. So on a Linux x86_64 or
macOS arm64 host, whose platform is also the one of a konan target, a `kt_jvm_test` gets `shared_jvm`
and a `kt_native_framework` gets `shared_native`. The aliases of `@kmp_maven` select the same way,
and so does a dependency written by hand: see
[The Kotlin platform type](kmp_dependencies.md#the-kotlin-platform-type).

A library compiles the sources of its fragments into its own jar or klib, so the aspects of other
rule sets, which follow `deps`, `exports` and `runtime_deps`, e.g. the dexing aspect of
`android_binary` and the mobile-install of rules_android, handle it as any other library.

### Tests, binaries and frameworks

`kt_jvm_test`, `kt_android_local_test`, `kt_jvm_binary`, `kt_native_binary`, `kt_native_test` and
`kt_native_framework` compile only their own `srcs`. They get the shared code from the library of
their platform, as the test compilation of a Gradle module compiles against its main one: a test of
the common code depends on `//shared`, which is `shared_jvm` for a `kt_jvm_test` and `shared_native`
for a `kt_native_test`, and a framework exports it (see [The iOS app](#the-ios-app)). As in
`examples/kmp`:

```starlark
kt_jvm_test(
    name = "greeting_jvm_test",
    srcs = ["GreetingJvmTest.kt"],
    test_class = "examples.kmp.tests.GreetingJvmTest",
    deps = ["//shared", "@rules_kotlin//kotlin/compiler:kotlin-test", ...],
)

kt_native_test(
    name = "greeting_native_test",
    srcs = ["GreetingNativeTest.kt"],
    deps = ["//shared"],
)
```

### KSP for a multiplatform library

The libraries of a `kt_multiplatform_library` cannot run the KSP compiler plugin (`kt_ksp_plugin` in
`plugins`, see the limitations), and Kotlin/Native has no such plugin. To process the common sources
and those of a platform together, as the Kotlin Gradle plugin does for a multiplatform module
(`KSPJvmMain` of `ksp2` for the JVM and Android, `KSPNativeMain` for a konan target), a **separate
action** runs the KSP command-line tool of the KSP release the rules pin and declares the Kotlin
files it generates:

```starlark
load("@rules_kotlin//kotlin:core.bzl", "kt_ksp_plugin")
load("@rules_kotlin//kotlin:kmp.bzl", "kt_jvm_ksp_sources", "kt_multiplatform_library", "kt_native_ksp_sources")

kt_ksp_plugin(
    name = "kotlin_inject_ksp",
    processor_class = "me.tatarka.inject.compiler.ksp.InjectProcessorProvider",
    deps = ["@maven//:me_tatarka_inject_kotlin_inject_compiler_ksp"],
)

kt_jvm_ksp_sources(  # android = True for an Android target: its SDK jar is a library of KSP
    name = "shared_ksp_jvm",
    srcs = COMMON_SRCS + ["jvm/JvmComponent.kt"],       # what the platform library compiles
    common_srcs = COMMON_SRCS,                          # the common ones, for `expect`/`actual`
    deps = ["@kmp_maven//:me_tatarka_inject_kotlin_inject_runtime_kmp"],
    generated = ["com/example/InjectJvmComponent.kt"],  # the plain files the processor writes
    processors = [":kotlin_inject_ksp"],
)

kt_native_ksp_sources(
    name = "shared_ksp_apple",
    srcs = COMMON_SRCS + ["apple/AppleComponent.kt"],
    common_srcs = COMMON_SRCS,
    deps = ["@kmp_maven//:me_tatarka_inject_kotlin_inject_runtime_kmp"],
    generated = ["com/example/InjectAppleComponent.kt"],
    processors = [":kotlin_inject_ksp"],
)

kt_multiplatform_library(
    name = "shared",
    srcs = COMMON_SRCS,
    platforms = ["jvm", "ios_arm64", "ios_simulator_arm64", "macos_arm64"],
    srcs_apple = ["apple/AppleComponent.kt", ":shared_ksp_apple"],
    srcs_jvm = ["jvm/JvmComponent.kt", ":shared_ksp_jvm"],
    deps = ["@kmp_maven//:me_tatarka_inject_kotlin_inject_runtime_kmp"],
)
```

The `srcs` of a KSP target are not those of the macro: a KSP target takes every source its platform
compiles in `srcs`, the common ones included, and lists the common ones again in its `common_srcs`,
which KSP processes after the others (see below), while the library of the platform compiles the
`srcs` of the macro and those of its groups through its lineage.

- The generated files are listed in `generated`, relative to the output root of KSP (the directory of the
  package and the file name), and are outputs of the target under a directory of its name. Only the list
  of the platform or the group that compiles them names the target. In `srcs_jvm`, they are in the leaf
  of the JVM, compiled with its own sources and the shared ones: they use the `@Inject` classes of the
  common code. In `srcs_apple`, they are in the fragment `apple`, and the target runs for each Apple
  konan target. No `.srcjar` and no directory is an output: the libraries of a
  `kt_multiplatform_library` reject srcjars, and a Kotlin/Native fragment needs concrete source paths.
- The action fails on a file the processors write that is not declared, on one declared that is not
  written (both are named in the message; run it once and list the files it names), on KSP errors, and
  on generated Java sources, classes or resources, which these rules do not compile.
- KSP sees the common sources and the platform's as one module, not as a multiplatform compilation,
  so an `expect` declaration and its `actual` are two declarations of the same name and the one in the
  first source root wins: the action lists the platform sources before `common_srcs` (whatever the
  order of `srcs`), as the KSP Gradle plugin does, so an `@Inject expect class` or an `expect`
  interface with `@Provides` resolves to the `actual` of the platform.
- The symbols are resolved against the libraries of the platform. For the JVM and Android, the compile
  jars of `deps` and the Kotlin standard library, plus the Android SDK jar with `android = True`. For a
  konan target, the klibs of `deps` of that target (the target of the build's `--platforms`, resolved
  by the aliases of `kmp_maven` below the Kotlin/Native transition, cinterop klibs included), the
  standard library and the platform libraries of the distribution; never JVM jars.
- `processors` are `kt_ksp_plugin` targets, whose runtime classpath KSP loads the processors from, and
  whose options (and `processor_options`) are passed on. The language and API versions, and the JVM
  target, are those of the Kotlin toolchain unless set on the rule.

This is a deliberate exception, not inline KSP: it is one KSP run per platform, which does not give the
processors the sources other compiler plugins generate. The compiler plugin still does not work with
the libraries of a `kt_multiplatform_library`, and no generated `.srcjar` is supported by them.
`examples/kmp` shows it with kotlin-inject 0.9.0 components in the `jvm`, `android` and `apple` sources.

### From Gradle to Bazel

| Gradle (the Kotlin Multiplatform plugin)                                                             | Bazel (rules_kotlin)                                                                                                                                             |
|------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `kotlin { androidTarget(); iosArm64(); iosSimulatorArm64(); jvm() }`                                 | `kt_multiplatform_library(platforms = ["android", "ios_arm64", "ios_simulator_arm64", "jvm"], ...)`                                                             |
| The `sourceSets` of the default hierarchy: `commonMain`, `iosMain`, `appleMain`, `nativeMain`, `jvmMain` | `srcs`, `srcs_ios`, `srcs_apple`, `srcs_native`, `srcs_jvm`, with a list per source set, e.g. `COMMON = glob(["src/commonMain/kotlin/**/*.kt"])`: the hierarchy makes the fragments and what they refine (see [Fragments](#fragments)) |
| A source set outside the default hierarchy, e.g. `nonAndroidMain`, and its `dependsOn`               | A list in the srcs of each group or platform compiling it, e.g. `srcs_jvm` and `srcs_native`, which forms the fragment `jvm-native`                             |
| `commonMain.dependencies { implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2") }` | `kmp_maven.install(artifacts = [...])` in `MODULE.bazel`, and `"@kmp_maven//:org_jetbrains_kotlinx_kotlinx_coroutines_core"` in the `deps` of the macro; those of `iosMain.dependencies` in `deps_ios` |
| `binaries.framework { baseName = "Shared"; isStatic = true }`                                        | `kt_native_framework(name = "Shared", exports = ["//shared"], transitive_exports = False)`; `export(...)` in the block is `transitive_exports = True` for the listed exports |
| The Xcode build phase that embeds the framework (`embedAndSignAppleFrameworkForXcode`)               | `filegroup(output_group = "framework_files")`, `apple_static_framework_import` and `ios_application`; or a build phase of the Xcode project that runs `bazel build` (see [The iOS app](#the-ios-app)) |
| The `androidApp` module                                                                              | `kt_android_library` and `android_binary`, with `--android_platforms`                                                                                            |
| The Android SDK of `local.properties` (`sdk.dir`) or `ANDROID_HOME`                                  | `android.sdk` and `android.ndk` of `hermetic_android_toolchains` in `MODULE.bazel`, their licenses accepted with `--repo_env` in `.bazelrc`                      |
| `./gradlew :shared:jvmTest`                                                                          | A `kt_jvm_test` that depends on `//shared`                                                                                                                       |
| `./gradlew :shared:iosSimulatorArm64Test`                                                            | No equivalent yet: `kt_native_test` runs for the konan target of the exec host only                                                                              |

### Limitations of the fragments

- The groups and platforms share sources by label. The macro resolves the labels of its lists in its
  package, so `"common/Greeting.kt"`, `":common/Greeting.kt"` and `"//shared:common/Greeting.kt"` are
  one source, but a file that a platform reaches through two labels, e.g. its path in the `srcs` of
  the macro and a `filegroup` containing it in `srcs_jvm`, lands in two fragments, and the analysis
  of the library of that platform fails with `the source <path> is in both fragment '<a>' and '<b>'`.
  A file that two platforms list through different labels is not shared: each compiles it in its
  leaf. List each file by one label.
- Fragments shared outside the hierarchy whose owners are incomparable, e.g. `android-jvm` and
  `jvm-linux_x64`, do not refine each other, and the compilation of a platform they share gets both:
  the `jvm` leaf refines both. An `expect` declaration above them with an `actual` in each gives the
  JVM two `actual`s, which the compiler rejects.
- A library of a single platform compiles its `srcs` as the fragment `common` too, so the
  restrictions of the libraries with fragments apply to it: no `.srcjar` sources, no kapt and no KSP
  compiler plugin (see [Limitations](#limitations)). Sources in the list of the platform alone, e.g.
  `srcs_jvm`, are its leaf and compile without fragments.
- The lists of sources are plain lists: the macro derives the fragments when it is called, before any
  `select()` is resolved, and fails on a `select()` there. A source of some konan targets only goes
  in the srcs of their group or platform, e.g. `srcs_linux` or `srcs_ios_arm64`.
- The groups are those of the default hierarchy: there are no custom groups, the `aliases` of the
  Kotlin Toolchain, and the dicts of attributes are per library, not per group.

## Dependencies

The deps of a Kotlin/Native rule are klibs of its konan target, and each platform of a
`kt_multiplatform_library` compiles its fragments against its own deps, so a library that differs
per platform is an alias that selects its variant, as `kt_multiplatform_library` and `kmp_maven`
declare them: the platforms then share the alias, listed once in the `deps` of the macro for the
common code.

The Maven libraries of multiplatform code come from the `kmp_maven` module extension, the counterpart
of the `commonMain` dependencies of a Gradle build: `kmp_maven.install` declares their coordinates,
`bazel run @kmp_maven//pin` pins them into a manifest committed in the workspace, and the alias
`@kmp_maven//:<group>_<artifact>` of each library is the klib of the konan target for the
Kotlin/Native rules, the Android variant on Android and the JVM jar otherwise. See
[Kotlin Multiplatform dependencies](kmp_dependencies.md), and
[Importing a klib by hand](kmp_dependencies.md#importing-a-klib-by-hand) for a prebuilt klib.

## The Android app

An `android_binary` needs the Android SDK and, even without native code, the Android NDK: it
resolves a C++ toolchain for the Android platform. `hermetic_android_toolchains` downloads both and
registers their toolchains, so the host needs neither installed, as in the `MODULE.bazel` of
`examples/kmp_app`:

```starlark
# MODULE.bazel
bazel_dep(name = "rules_android", version = "0.8.0")
bazel_dep(name = "hermetic_android_toolchains", version = "0.5.0", dev_dependency = True)
bazel_dep(name = "rules_android_ndk", version = "0.1.5", dev_dependency = True)

android = use_extension("@hermetic_android_toolchains//:extensions.bzl", "android", dev_dependency = True)
android.sdk(
    build_tools_version = "35.0.0",
    version = "35",
)
android.ndk(version = "r29")
use_repo(android, "androidndk", "androidsdk")

# The @androidsdk of rules_android and the @androidndk of rules_android_ndk are the hermetic ones.
android_sdk_repository_extension = use_extension(
    "@rules_android//rules/android_sdk_repository:rule.bzl",
    "android_sdk_repository_extension",
    dev_dependency = True,
)

override_repo(android_sdk_repository_extension, "androidsdk")

android_ndk_repository_extension = use_extension(
    "@rules_android_ndk//:extension.bzl",
    "android_ndk_repository_extension",
    dev_dependency = True,
)

override_repo(android_ndk_repository_extension, "androidndk")

register_toolchains(
    "@androidndk//:all",
    "@androidsdk//:all",
    dev_dependency = True,
)
```

Once you have reviewed the licenses of the SDK and the NDK, accept them in `.bazelrc` for the
versions the build downloads:

```
# .bazelrc
common --repo_env=ACCEPTED_ANDROID_SDK_LICENSE_VERSION=35
common --repo_env=ACCEPTED_ANDROID_NDK_LICENSE_VERSION=r29
```

`android_binary` builds its deps for the platforms of `--android_platforms`. Set it to an Android
platform, so that `//shared` and the aliases of `@kmp_maven` resolve to their Android variants, as
the `androidApp` module of a Gradle build gets the Android variants of its dependencies. Without it,
rules_android leaves `--platforms` alone: the deps build for the host platform, where the aliases
select their JVM variants.

```starlark
# BUILD.bazel
platform(
    name = "android_arm64",
    constraint_values = [
        "@platforms//cpu:arm64",
        "@platforms//os:android",
    ],
)
```

```
# .bazelrc
build --android_platforms=@@//:android_arm64
```

The label is canonical, `@@//` for the main repository: on Bazel 9, rules_android makes
`--android_platforms` an alias of its own flag, `@rules_android//flags:android_platforms` (a
`flag_alias` of its `MODULE.bazel`), which would read `//:android_arm64` as a label of the
rules_android repository.

```starlark
# androidApp/BUILD.bazel
load("@rules_android//android:rules.bzl", "android_binary")
load("@rules_kotlin//kotlin:android.bzl", "kt_android_library")

kt_android_library(
    name = "lib",
    srcs = glob(["src/main/kotlin/**/*.kt"]),
    custom_package = "org.example.kmpapp.android",
    manifest = "src/main/AndroidManifest.xml",
    deps = [
        "//shared",
        "@kmp_maven//:org_jetbrains_kotlinx_kotlinx_coroutines_core",
    ],
)

android_binary(
    name = "androidApp",
    custom_package = "org.example.kmpapp.android",
    manifest = "src/main/AndroidManifest.xml",
    deps = [":lib"],
)
```

`bazel build //androidApp` builds `bazel-bin/androidApp/androidApp.apk`, which
`adb install bazel-bin/androidApp/androidApp.apk` installs on a device or an emulator.
`bazel mobile-install //androidApp` (`--adb=<path>` when adb is not on the PATH) installs it
incrementally instead, through the mobile-install of rules_android.

## The iOS app

An iOS app links the framework through rules_apple and rules_swift, as `//iosApp` of
`examples/kmp_app` does:

```starlark
load("@rules_apple//apple:apple.bzl", "apple_static_framework_import")
load("@rules_apple//apple:ios.bzl", "ios_application")
load("@rules_kotlin//kotlin:native.bzl", "kt_native_framework")
load("@rules_swift//swift:swift.bzl", "swift_library")

# Built in the iOS configuration of the app only.
IOS_ONLY = ["@platforms//os:ios"]

kt_native_framework(
    name = "Shared",
    bundle_id = "org.example.kmpapp.Shared",
    target_compatible_with = IOS_ONLY,
    exports = ["//shared"],
)

filegroup(
    name = "Shared_files",
    srcs = [":Shared"],
    output_group = "framework_files",
    target_compatible_with = IOS_ONLY,
)

apple_static_framework_import(
    name = "Shared_import",
    framework_imports = [":Shared_files"],
    # What konanc links an iOS binary with: the Kotlin/Native runtime needs them.
    sdk_dylibs = ["c++", "objc"],
    sdk_frameworks = ["Foundation", "UIKit"],
    target_compatible_with = IOS_ONLY,
)

swift_library(
    name = "iosApp_lib",
    srcs = glob(["iosApp/*.swift"]),
    module_name = "iosApp",
    target_compatible_with = IOS_ONLY,
    deps = [":Shared_import"],
)

ios_application(
    name = "iosApp",
    bundle_id = "org.example.kmpapp",
    families = ["iphone"],
    infoplists = ["Info.plist"],
    minimum_os_version = "15.0",
    deps = [":iosApp_lib"],
)
```

The Swift code imports the module `Shared`. The Objective-C names of the framework start with its
name, e.g. `SharedGreeting`, while Swift sees the Kotlin ones, e.g. `Greeting`, and a `suspend`
function is `async throws` in Swift:

```swift
import Shared
import SwiftUI

struct ContentView: View {
    @State private var greeting = Greeting().greet()

    var body: some View {
        Text(greeting)
            .task { greeting = (try? await Greeting().greetLater()) ?? greeting }
    }
}
```

The framework follows the platform of the app: `ios_application` builds its deps for the iOS
platform of `--ios_multi_cpus`, an apple_support platform whose constraints the Kotlin/Native
toolchains match, so the BUILD files name no konan target:

| `--ios_multi_cpus`                            | Konan target of `Shared` | The app                                                                                              |
|-----------------------------------------------|--------------------------|------------------------------------------------------------------------------------------------------|
| `sim_arm64`, as in the `.bazelrc` of the example | `ios_simulator_arm64` | Runs in the simulator of an arm64 Mac, unsigned: `bazel run //iosApp` launches it.                   |
| `arm64`                                       | `ios_arm64`              | Runs on a device, signed with a provisioning profile (`provisioning_profile` of `ios_application`). |

Both targets are in the `kotlin_native.targets(...)` of the example. The four targets between the
framework and the app are `target_compatible_with = ["@platforms//os:ios"]`, so `bazel build //...`
skips them in the host configuration and builds them in the configuration of the app. The framework
alone builds for an explicit platform, e.g. to read its header:

```shell
bazel build //iosApp:Shared --platforms=@rules_kotlin//kotlin/native/platforms:ios_simulator_arm64
```

An app that stays an Xcode project (signing, asset catalogs, Swift packages in Xcode) links the
framework the way it links the one of the Kotlin Gradle plugin: a "Run Script" build phase before
"Compile Sources" runs that `bazel build` for the konan target of `PLATFORM_NAME` (`iphonesimulator`:
`ios_simulator_arm64`, `iphoneos`: `ios_arm64`), asks `bazel cquery --output=files` for the path of
the `<name>.framework` directory (the output directory of an iOS configuration is not the one
`bazel-bin` points to) and copies it into `$BUILT_PRODUCTS_DIR`, which Xcode searches for frameworks;
`OTHER_LDFLAGS = -framework <name>` and `import <name>` in Swift do the rest. A static framework
needs no embedding or signing. `-c opt` for the `Release` configuration gives the optimized link of
the `releaseFramework` task.

## Limitations

- Linux x86_64 and macOS arm64 exec hosts only: Windows is not supported. The konan targets are the
  five above.
- Kotlin/Native defaults to a dev build of the next Kotlin release, 2.5.20-dev-5696, whose klibs
  compile through the experimental Kotlin/Native Build Tools API: see
  [The Kotlin/Native Build Tools API](#the-kotlinnative-build-tools-api).
  `kotlin_native.version(version = "2.4.21")` selects the release.
- No cinterop rule yet: the code cannot bind a C or Objective-C library of its own. The platform
  libraries of the distribution are available, and the cinterop klibs of a Maven library are imported
  with it.
- No Kotlin/JS or Kotlin/Wasm platform: the platforms of `kt_multiplatform_library` are `jvm`,
  `android` and the konan targets, and `kmp_maven` leaves the `wasmjs` variants out.
- Static frameworks only: no dynamic framework and no XCFramework. A framework is for one konan
  target, which the platform of the app selects.
- `kt_native_test` runs for the konan target of the exec host only (`linux_x64` or `macos_arm64`):
  not in the iOS simulator, nor through an emulator.
- `bazel coverage` instruments the Kotlin code compiled for the JVM and Android, the sources of
  their fragments included; the Kotlin/Native rules do not instrument theirs. An `ios_application`
  does not link the profile runtime of instrumented Swift code, so `examples/kmp_app` leaves its
  Swift app out of `--instrumentation_filter`.
- The JVM and Android libraries of a `kt_multiplatform_library` cannot have `.srcjar` sources, kapt
  or the KSP compiler plugin; [KSP for a multiplatform library](#ksp-for-a-multiplatform-library) is
  a separate action with declared plain `.kt` outputs, which they compile. KSP of a native target is
  that action too; there is no inline KSP plugin for Kotlin/Native. Generated Java sources, classes
  and resources of that action are not supported.
- The fragments follow from the groups and platforms that list each label, with limits of their
  own: see [Limitations of the fragments](#limitations-of-the-fragments).
- The JVM and Android variants of Maven libraries bring the `kotlin-stdlib` jar of the manifest next
  to the standard library of the Kotlin toolchain. The dexing of `android_binary` tolerates the
  duplicate classes; a substitution of `kmp_maven.install` aligns the versions (see the
  [limitations of the dependencies](kmp_dependencies.md#limitations)).
- Compilation avoidance is experimental and off by default on every platform. On the JVM and Android,
  libraries emit ABI jars when the Kotlin toolchain sets `experimental_use_abi_jars = True`. On
  Kotlin/Native, libraries write header klibs with the build setting
  `experimental_native_header_klibs`, and a Kotlin/Native link still reruns after every edit to a
  klib it links. See [Kotlin Multiplatform](../CompileAvoidance.md#kotlin-multiplatform) in the
  compilation avoidance docs.

## Examples

| Example                                   | Shows                                                                                                                                                                                       | Hosts                                                                         |
|-------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------|
| [`examples/native`](../examples/native)   | klibs for the host and for every konan target, an executable run end to end, tests, Linux executables linked for both Linux targets, and a framework and its `framework_files` per Apple target. | Linux x86_64 and macOS arm64, the Apple targets on macOS only.             |
| [`examples/kmp`](../examples/kmp)         | A `kt_multiplatform_library` for the JVM, Android, the Apple and the Linux targets, with its common sources and deps in the `srcs` and `deps` of the macro, those of the Apple and Linux targets in `srcs_apple` and `srcs_linux`, and Gradle's `nonAndroidMain` in `srcs_jvm` and `srcs_native`, the fragment `jvm-native` between `common` and the fragments `apple` and `linux`; JVM and native tests that depend on `//shared`, `kotlinx-coroutines-core` from `kmp_maven`, and kotlin-inject components generated by KSP for the JVM, Android and Apple sources. | Linux x86_64 and macOS arm64, the Apple klibs on macOS only; Bazel 8.4.2 or newer. |
| [`examples/kmp_app`](../examples/kmp_app) | An Android app and an iOS app that share one `kt_multiplatform_library`, laid out like the project of the Kotlin Multiplatform wizard.                                                      | macOS arm64 builds both apps, Linux x86_64 the Android app; Bazel 8.4.2 or newer. |

Each builds and tests with `bazel build //...` and `bazel test //...` in its directory.
