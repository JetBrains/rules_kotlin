# Kotlin/Native and Kotlin Multiplatform

Experimental. rules_kotlin compiles Kotlin/Native code into klibs and links them into executables,
test runners and static Apple frameworks, and it declares Kotlin Multiplatform (KMP) modules whose
common code compiles for the JVM, Android and Kotlin/Native, as the Kotlin Gradle plugin does. The
rules, their attributes and their module extensions may change in any release.

This guide covers the setup, the platforms, the rules, the mapping from a Gradle KMP project, the
migration from `kt_source_set` and the integration with Android and iOS apps. The attributes of each
rule are in the [API reference](kotlin.md), and the Maven dependencies of multiplatform code in
[Kotlin Multiplatform dependencies](kmp_dependencies.md).

## Status and prerequisites

- **Exec hosts**: Linux x86_64 and macOS arm64, the hosts of the Kotlin/Native distributions. There
  is no Windows, Linux arm64 or macOS x86_64 exec host; the JVM and Android builds of those hosts are
  unaffected.
- **Konan targets**: `linux_x64` and `linux_arm64` on both hosts; `macos_arm64`, `ios_arm64` and
  `ios_simulator_arm64` on macOS only.
- **Xcode**: the Apple targets need a macOS host with Xcode, whose SDK konanc finds with `xcrun`.
- **Compiler**: Kotlin/Native 2.4.21, the release of the Kotlin compiler rules_kotlin pins, as klibs
  are coupled to the compiler that produced them.
- **Bazel**: the rules build with Bazel 7 and newer (`examples/native` runs with 7.x, 8.x and 9.3.1).
  `examples/kmp` and `examples/kmp_app` need Bazel 8.4.2 or newer, as they get the Android SDK (and
  `examples/kmp_app` the Android NDK) from `hermetic_android_toolchains`; `examples/kmp_app` also
  builds its iOS app with rules_apple 5.x, which dropped Bazel 7.
- **Android**: an Android app, `android_binary`, needs the Android SDK and, even without native code,
  the Android NDK, whose C++ toolchain it resolves for the Android platform.
  `hermetic_android_toolchains` downloads both once `.bazelrc` accepts their licenses: see
  [The Android app](#the-android-app).
- **Network**: no action needs it. The Kotlin/Native distribution and its link dependencies, like the
  Android SDK and NDK, are Bazel repositories, fetched before any action runs, and the examples build
  with `--sandbox_default_allow_network=false`.

## The `kotlin_native` module extension

rules_kotlin registers a Kotlin/Native toolchain per exec host and konan target. Their repositories
come from the `kotlin_native` module extension, two per exec host:

- `com_github_jetbrains_kotlin_native_<host>`: the prebuilt distribution,
  `kotlin-native-prebuilt-<host>-<version>` from the GitHub releases of JetBrains/kotlin. It compiles
  klibs for every konan target of the host, with the standard library and the platform libraries of
  the target, e.g. `platform.posix` or `platform.UIKit`.
- `com_github_jetbrains_kotlin_native_deps_<host>`: the link dependencies of the targets of
  `kotlin_native.targets(...)`, from `download.jetbrains.com`: the LLVM and libffi of the host, lldb
  for the host's own target, the GCC cross-toolchain of a Linux target and, on a Linux host, the qemu
  emulator of `linux_arm64`. The iOS targets add none, as Xcode provides their toolchain and SDK.

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
| `version` | `version`, and `sha256`: the checksum of the archive per exec host, `linux-x86_64` and `macos-aarch64`. | Another Kotlin/Native release than 2.4.21. An archive without checksum downloads unverified. The link dependencies are staged with the LLVM of the release: rules_kotlin pins the LLVM of 2.4.21 (LLVM 21), and checks the bundle against the `konan.properties` of the release when it is fetched. A release without a pinned LLVM, or one that needs other dependencies, fails with the differences, naming the archives to add to `KOTLIN_NATIVE_LLVM` and `KOTLIN_NATIVE_ARCHIVES` of `src/main/starlark/core/repositories/native_compiler.bzl`; with `kotlin_native.targets(targets = [])` its klibs still compile. |

List the targets the build links for: the link dependencies are large archives. The iOS targets of
`examples/kmp_app` add nothing to the LLVM and libffi of a macOS host, while `examples/native`, which
links for every target, lists all five.

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
and an alias that selects the library of its consumer. A platform is `jvm`, `android` or a konan
target, and a group of `native` stands for each of its `targets`. Each platform lists every source
it compiles in its `srcs`, a plain list of labels, and the libraries they use in its `deps`. The
sources that several platforms compile are Starlark lists that their `srcs` add up, as in
`examples/kmp_app`:

```starlark
load("@rules_kotlin//kotlin:kmp.bzl", "kt_multiplatform_library")

COMMON = glob(["src/commonMain/kotlin/**/*.kt"])

COROUTINES = "@kmp_maven//:org_jetbrains_kotlinx_kotlinx_coroutines_core"

kt_multiplatform_library(
    name = "shared",
    android = dict(
        srcs = COMMON + glob(["src/androidMain/kotlin/**/*.kt"]),
        custom_package = "org.example.kmpapp",
        manifest = "src/androidMain/AndroidManifest.xml",
        deps = [COROUTINES],
    ),
    jvm = dict(
        srcs = COMMON + glob(["src/jvmMain/kotlin/**/*.kt"]),
        deps = [COROUTINES],
    ),
    native = {
        "ios": dict(
            srcs = COMMON + glob(["src/iosMain/kotlin/**/*.kt"]),
            targets = ["ios_arm64", "ios_simulator_arm64"],
            deps = [COROUTINES],
        ),
    },
    visibility = ["//visibility:public"],
)
```

The other keys of `jvm` and `android` are attributes of their libraries, e.g. `manifest`, and those
of a group, e.g. `opts`, attributes of the native library for the targets of the group. A platform
lists a label once, and a konan target is in one group at most.

### Fragments

The macro derives the fragments of the compilations from the sources the platforms list:

- The sources that exactly the same platforms list form one fragment, named after those platforms:
  their names, sorted and joined with `-`. Above, `COMMON`, which every platform lists, is the
  fragment `android-ios_arm64-ios_simulator_arm64-jvm`, and the sources of `src/iosMain`, which both
  iOS targets list, are the fragment `ios_arm64-ios_simulator_arm64`.
- A fragment `A` refines a fragment `B`, as a Gradle source set depends on another, when the
  platforms of `A` are a strict subset of those of `B` and no fragment lies in between:
  `ios_arm64-ios_simulator_arm64` refines `android-ios_arm64-ios_simulator_arm64-jvm`.
- The sources that a single platform lists stay in the library of that platform as its leaf
  fragment, named after the platform, `jvm`, `android` or the konan target, which refines the
  fragments directly above the platform. A leaf may be empty: `ios_arm64` and `ios_simulator_arm64`
  are, as both targets list the same sources.

The library of a platform compiles every fragment whose platforms include it, most shared first,
then its leaf, in one compilation (`-Xfragments`, `-Xfragment-sources` and `-Xfragment-refines`). A
fragment has no deps: each platform compiles all its fragments against its own `deps`, which
resolve in its configuration, JVM libraries for the JVM and Android and klibs of the konan target
for Kotlin/Native. So the deps of shared code are in the `deps` of every platform compiling it; an
alias that selects the variant of the platform, like those of `kmp_maven`, lets the platforms share
one list.

An intermediate source set of the Gradle build, between the common code and the platforms, is a
list that the platforms compiling it add to their `srcs`, as `examples/kmp` does with Gradle's
`nonAndroidMain`:

```starlark
COMMON = glob(["common/**/*.kt"])

NON_ANDROID = glob(["non_android/**/*.kt"])  # Gradle's nonAndroidMain: every platform but Android

kt_multiplatform_library(
    name = "shared",
    android = dict(srcs = COMMON + glob(["android/**/*.kt"]), deps = DEPS, ...),
    jvm = dict(srcs = COMMON + NON_ANDROID + glob(["jvm/**/*.kt"]), deps = DEPS),
    native = {
        "apple": dict(
            srcs = COMMON + NON_ANDROID + glob(["apple/**/*.kt"]),
            targets = ["ios_arm64", "macos_arm64"],
            deps = DEPS,
        ),
    },
)
```

| Sources       | Fragment                                    | Refines                             |
|---------------|---------------------------------------------|-------------------------------------|
| `COMMON`      | `android-ios_arm64-jvm-macos_arm64`         |                                     |
| `NON_ANDROID` | `ios_arm64-jvm-macos_arm64`                 | `android-ios_arm64-jvm-macos_arm64` |
| `apple/`      | `ios_arm64-macos_arm64`                     | `ios_arm64-jvm-macos_arm64`         |
| `jvm/`        | `jvm`, the leaf of the JVM                  | `ios_arm64-jvm-macos_arm64`         |
| `android/`    | `android`, the leaf of Android              | `android-ios_arm64-jvm-macos_arm64` |
| None          | `ios_arm64` and `macos_arm64`, empty leaves | `ios_arm64-macos_arm64`             |

`examples/kmp` also has a group `linux` of `linux_arm64` and `linux_x64`, whose own sources are the
fragment `linux_arm64-linux_x64`, which refines the non-Android one too.

### The declared targets

| Target                       | Rule                         | Content                                                                                                                                                                                                                                                                                 |
|------------------------------|------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `shared_fragment_<fragment>` | `kt_kmp_fragment` (internal) | A private target per fragment, e.g. `shared_fragment_ios_arm64-ios_simulator_arm64`: its sources and the fragments it refines. It compiles nothing by itself. A fragment of konan targets only is compatible only below a Kotlin/Native consumer building for one of them, so that `bazel build //...` skips it. |
| `shared_jvm`                 | `kt_jvm_library`             | The attributes of `jvm`; it compiles the fragments of the JVM and its leaf.                                                                                                                                                                                                             |
| `shared_android`             | `kt_android_library`         | The attributes of `android`; it compiles the fragments of Android and its leaf.                                                                                                                                                                                                         |
| `shared_native`              | `kt_native_library`          | For the konan target of the build's platform, the fragments of that target and its leaf, with the other attributes of its group. It is incompatible with the other platforms.                                                                                                           |
| `shared_srcs`                | `filegroup`                  | The sources of every platform.                                                                                                                                                                                                                                                          |
| `shared`                     | `alias`                      | `shared_native` for a Kotlin/Native consumer building for a target of the groups, `shared_android` on `@platforms//os:android`, and otherwise `shared_jvm` (or, without `jvm`, `shared_android`, then `shared_native`).                                                                 |

There is no target of the common sources or of a group: a consumer depends on the alias or on the
library of a platform. The libraries get their fragments through an internal attribute,
`kmp_fragments`, which only the macro sets.

The alias tells a Kotlin/Native consumer from a JVM one by the Kotlin platform type,
`@rules_kotlin//kotlin/settings:kotlin_platform_type`: `jvm` by default, and `native` for the
Kotlin/Native rules and their deps, which set it with a rule transition. So on a Linux x86_64 or
macOS arm64 host, whose platform is also the one of a konan target, a `kt_jvm_test` gets `shared_jvm`
and a `kt_native_framework` gets `shared_native`. The aliases of `@kmp_maven` select the same way,
and so does a dependency written by hand: see
[The Kotlin platform type](kmp_dependencies.md#the-kotlin-platform-type).

The deps of the libraries are their `deps`, which the aspects of other rule sets follow, e.g. the
dexing aspect of `android_binary` and the mobile-install of rules_android: a fragment has no deps
for them to miss, and its sources compile into the jar of each library that compiles it.

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
    jvm = dict(
        srcs = COMMON_SRCS + ["jvm/JvmComponent.kt", ":shared_ksp_jvm"],
        deps = ["@kmp_maven//:me_tatarka_inject_kotlin_inject_runtime_kmp"],
    ),
    native = {"apple": dict(
        srcs = COMMON_SRCS + ["apple/AppleComponent.kt", ":shared_ksp_apple"],
        targets = [...],
        deps = ["@kmp_maven//:me_tatarka_inject_kotlin_inject_runtime_kmp"],
    )},
)
```

- The generated files are listed in `generated`, relative to the output root of KSP (the directory of the
  package and the file name), and are outputs of the target under a directory of its name. Only the
  platform that compiles them lists the target in its `srcs`, so they are in the leaf of that platform,
  compiled with its own sources and the shared ones: they use the `@Inject` classes of the common code.
  The target of a native group is in the `srcs` of each of its konan targets, so it is in their fragment
  (the leaf, for a group of one target), and runs for each of them. No `.srcjar` and no directory is an
  output: the libraries of a `kt_multiplatform_library` reject srcjars, and a Kotlin/Native fragment
  needs concrete source paths.
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
| `kotlin { androidTarget(); iosArm64(); iosSimulatorArm64(); jvm() }` and its `sourceSets`            | `kt_multiplatform_library(android = dict(srcs = COMMON + ANDROID, ...), jvm = dict(srcs = COMMON + JVM, ...), native = {"ios": dict(srcs = COMMON + IOS, targets = ["ios_arm64", "ios_simulator_arm64"], ...)})`, with a list per source set, e.g. `COMMON = glob(["src/commonMain/kotlin/**/*.kt"])` |
| `dependsOn`, the hierarchy of the source sets                                                        | The sources of a source set in the `srcs` of every platform that compiles it: the platforms listing each source make the fragments and what they refine (see [Fragments](#fragments)) |
| `commonMain.dependencies { implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2") }` | `kmp_maven.install(artifacts = [...])` in `MODULE.bazel`, and `"@kmp_maven//:org_jetbrains_kotlinx_kotlinx_coroutines_core"` in the `deps` of every platform           |
| `binaries.framework { baseName = "Shared"; isStatic = true }`                                        | `kt_native_framework(name = "Shared", exports = ["//shared"], transitive_exports = False)`; `export(...)` in the block is `transitive_exports = True` for the listed exports |
| The Xcode build phase that embeds the framework (`embedAndSignAppleFrameworkForXcode`)               | `filegroup(output_group = "framework_files")`, `apple_static_framework_import` and `ios_application`; or a build phase of the Xcode project that runs `bazel build` (see [The iOS app](#the-ios-app)) |
| The `androidApp` module                                                                              | `kt_android_library` and `android_binary`, with `--android_platforms`                                                                                            |
| The Android SDK of `local.properties` (`sdk.dir`) or `ANDROID_HOME`                                  | `android.sdk` and `android.ndk` of `hermetic_android_toolchains` in `MODULE.bazel`, their licenses accepted with `--repo_env` in `.bazelrc`                      |
| `./gradlew :shared:jvmTest`                                                                          | A `kt_jvm_test` that depends on `//shared`                                                                                                                       |
| `./gradlew :shared:iosSimulatorArm64Test`                                                            | No equivalent yet: `kt_native_test` runs for the konan target of the exec host only                                                                              |

### Migrating from `kt_source_set`

`kt_source_set`, its provider `KtSourceSetInfo` and the `source_sets` attribute of the JVM, Android
and Kotlin/Native rules are removed: the platforms of a `kt_multiplatform_library` list their
sources, and the macro derives the fragments that the source sets declared. The parameters and keys
of the former declaration fail the build with what replaces them, e.g.
`kt_multiplatform_library shared: common_srcs is removed: each platform lists every source it compiles: ...`.

| Before                                                                                                                                  | Now                                                                                                                                                                                      |
|-----------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `common_srcs = COMMON`                                                                                                                  | `COMMON` in the `srcs` of every platform: `jvm = dict(srcs = COMMON + JVM, ...)`, and so on.                                                                                            |
| `common_deps = DEPS`                                                                                                                    | `DEPS` in the `deps` of every platform.                                                                                                                                                  |
| An intermediate `kt_source_set`, in the `source_sets` of `jvm` or `android` and in the `depends_on` of groups of `native`               | Its sources in the `srcs` of every platform that compiled it, and its deps in their `deps`: the platforms listing the sources make the fragment and what it refines.                     |
| `source_sets` of a `kt_jvm_test`, `kt_android_local_test`, `kt_jvm_binary`, `kt_native_binary`, `kt_native_test` or `kt_native_framework` | A dep on the library of the platform, `//shared` (or `//shared:shared_jvm`, `//shared:shared_native`), whose fragments hold those sources: the target compiles its own `srcs` only. |
| A `kt_source_set` in the `source_sets` of a `kt_jvm_library`, `kt_android_library` or `kt_native_library` declared by hand            | A `kt_multiplatform_library`, whose libraries are the only ones to compile fragments. The `runtime_deps` that listed the source sets for the aspects go away.                          |
| The targets `shared_common` and `shared_<group>`                                                                                        | None: depend on `shared` or on the library of a platform; `shared_srcs` has every source.                                                                                                |

The source sets of exactly the same platforms become one fragment: see the
[limitations of the fragments](#limitations-of-the-fragments).

### Limitations of the fragments

- Source sets of exactly the same platforms collapse into one fragment, e.g. Gradle's `commonMain`
  and `iosMain` in a module of iOS targets only, or `commonMain` and `nonAndroidMain` in a module
  without Android. An `expect` declaration in one and its `actual` in the other are then in one
  fragment, which does not compile: the `actual`s must be in the sources of fewer platforms, e.g.
  of a group per konan target, or the declaration needs no `expect`. A library of a single platform
  has no fragment at all: all its sources are its leaf.
- The platforms share sources by label. The macro resolves the labels of the `srcs` in its package,
  so `"common/Greeting.kt"`, `":common/Greeting.kt"` and `"//shared:common/Greeting.kt"` are one
  source, but a file that a platform reaches through two labels, e.g. its path and a `filegroup`
  containing it, lands in two fragments, and the analysis of the library of that platform fails
  with `the source <path> is in both fragment '<a>' and '<b>'`. A file that two platforms list
  through different labels is not shared: each compiles it in its leaf. List each file by one label.
- Fragments of incomparable sets of platforms, e.g. `android-jvm` and `jvm-linux_x64`, do not
  refine each other, and the compilation of a platform they share gets both: the `jvm` leaf refines
  both. An `expect` declaration above them with an `actual` in each gives the JVM two `actual`s,
  which the compiler rejects.
- A fragment is named after all its platforms, so the names of the fragments, in the targets
  `<name>_fragment_<fragment>` and in the `-Xfragments` of the compilations, grow with the number
  of konan targets: the common fragment of `examples/kmp`, for the JVM, Android and five konan
  targets, is `android-ios_arm64-ios_simulator_arm64-jvm-linux_arm64-linux_x64-macos_arm64`.
- The `srcs` of a platform are a plain list: the macro derives the fragments when it is called,
  before any `select()` is resolved, and fails on a `select()` there. A source of some konan
  targets only goes in the `srcs` of a group of those targets.

## Dependencies

The deps of a Kotlin/Native rule are klibs of its konan target, and each platform of a
`kt_multiplatform_library` compiles its fragments against its own deps, so a library that differs
per platform is an alias that selects its variant, as `kt_multiplatform_library` and `kmp_maven`
declare them: the platforms then list the same alias.

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
incrementally instead, through the mobile-install of rules_android, which dexes the targets it
reaches through `deps`, `exports` and `runtime_deps`: the deps of `shared_android` are its own
`deps`, as a fragment has none (see [The declared targets](#the-declared-targets)).

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
- No cinterop rule yet: the code cannot bind a C or Objective-C library of its own. The platform
  libraries of the distribution are available, and the cinterop klibs of a Maven library are imported
  with it.
- No Kotlin/JS or Kotlin/Wasm platform: `kt_multiplatform_library` has `jvm`, `android` and `native`
  ones, and `kmp_maven` leaves the `wasmjs` variants out.
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
- The fragments follow from the labels the platforms list, with limits of their own: see
  [Limitations of the fragments](#limitations-of-the-fragments).
- The JVM and Android variants of Maven libraries bring the `kotlin-stdlib` jar of the manifest next
  to the standard library of the Kotlin toolchain. The dexing of `android_binary` tolerates the
  duplicate classes; a substitution of `kmp_maven.install` aligns the versions (see the
  [limitations of the dependencies](kmp_dependencies.md#limitations)).

## Examples

| Example                                   | Shows                                                                                                                                                                                       | Hosts                                                                         |
|-------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------|
| [`examples/native`](../examples/native)   | klibs for the host and for every konan target, an executable run end to end, tests, Linux executables linked for both Linux targets, and a framework and its `framework_files` per Apple target. | Linux x86_64 and macOS arm64, the Apple targets on macOS only.             |
| [`examples/kmp`](../examples/kmp)         | A `kt_multiplatform_library` for the JVM, Android, the Apple and the Linux targets, whose platforms add up shared lists of sources, with a non-Android fragment between the common one and those of the Apple and Linux groups; JVM and native tests that depend on `//shared`, `kotlinx-coroutines-core` from `kmp_maven`, and kotlin-inject components generated by KSP for the JVM, Android and Apple sources. | Linux x86_64 and macOS arm64, the Apple klibs on macOS only; Bazel 8.4.2 or newer. |
| [`examples/kmp_app`](../examples/kmp_app) | An Android app and an iOS app that share one `kt_multiplatform_library`, laid out like the project of the Kotlin Multiplatform wizard.                                                      | macOS arm64 builds both apps, Linux x86_64 the Android app; Bazel 8.4.2 or newer. |

Each builds and tests with `bazel build //...` and `bazel test //...` in its directory.
