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
rules also take Kotlin compiler `plugins` (`kt_compiler_plugin`) and `source_sets`
(see [Source sets](#source-sets-and-kt_multiplatform_library)). [`KtKlibInfo`](kotlin.md#KtKlibInfo)
is the provider of a klib.

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

## Source sets and `kt_multiplatform_library`

`@rules_kotlin//kotlin:kmp.bzl` has the multiplatform rules.

A [`kt_source_set`](kotlin.md#kt_source_set) is the source set of the Kotlin Gradle plugin: Kotlin
`srcs`, the `deps` they use and the source sets they refine, `depends_on`, Gradle's `dependsOn`. It
compiles nothing by itself. A rule that lists it in its `source_sets`, `kt_native_library`, a linking
rule or a JVM or Android rule such as `kt_jvm_library`, `kt_jvm_test` or `kt_android_library`,
compiles its sources and those of the source sets it refines with its own `srcs` in one compilation,
as the K2 fragments of a multiplatform module (`-Xmulti-platform`): the `expect` declarations of the
common code and the `actual` ones of the platform are in one module. The deps of a source set
resolve in the configuration of each rule compiling it: JVM libraries for the JVM and Android rules,
klibs of the konan target for the Kotlin/Native rules. [`KtSourceSetInfo`](kotlin.md#KtSourceSetInfo)
is the provider of a source set.

```starlark
load("@rules_kotlin//kotlin:jvm.bzl", "kt_jvm_library")
load("@rules_kotlin//kotlin:kmp.bzl", "kt_source_set")
load("@rules_kotlin//kotlin:native.bzl", "kt_native_library")

kt_source_set(
    name = "common",
    srcs = ["Runtime.kt"],  # expect val runtime: String
)

kt_jvm_library(
    name = "explicit_jvm",
    srcs = ["Runtime.jvm.kt"],  # actual val runtime: String = "the JVM"
    source_sets = [":common"],
)

kt_native_library(
    name = "explicit_native",
    srcs = ["Runtime.native.kt"],  # actual val runtime: String = "Kotlin/Native"
    source_sets = [":common"],
)
```

[`kt_multiplatform_library`](kotlin.md#kt_multiplatform_library) declares such a module from a
declaration like the one of the Kotlin Gradle plugin:

```starlark
load("@rules_kotlin//kotlin:kmp.bzl", "kt_multiplatform_library")

kt_multiplatform_library(
    name = "shared",
    common_srcs = glob(["src/commonMain/kotlin/**/*.kt"]),
    common_deps = ["@kmp_maven//:org_jetbrains_kotlinx_kotlinx_coroutines_core"],
    android = dict(
        srcs = glob(["src/androidMain/kotlin/**/*.kt"]),
        custom_package = "org.example.kmpapp",
        manifest = "src/androidMain/AndroidManifest.xml",
    ),
    jvm = dict(srcs = glob(["src/jvmMain/kotlin/**/*.kt"])),
    native = {
        "ios": dict(
            srcs = glob(["src/iosMain/kotlin/**/*.kt"]),
            targets = ["ios_arm64", "ios_simulator_arm64"],
        ),
    },
    visibility = ["//visibility:public"],
)
```

It declares:

| Target           | Rule                 | Content                                                                                                                                                                                  |
|------------------|----------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `shared_common`  | `kt_source_set`      | `common_srcs` and `common_deps`: Gradle's `commonMain`.                                                                                                                                  |
| `shared_jvm`     | `kt_jvm_library`     | The attributes of `jvm`, compiling the common source set: `jvmMain`.                                                                                                                     |
| `shared_android` | `kt_android_library` | The attributes of `android`, compiling the common source set: `androidMain`.                                                                                                             |
| `shared_ios`     | `kt_source_set`      | A source set per group of `native`, of its `srcs` and `deps`, which refines the common one and the source sets of its `depends_on`: `iosMain`. Only compatible below a Kotlin/Native consumer building for a target of the group (`shared_native`), so that `bazel build //...`, for any platform, skips it rather than resolving its deps as a JVM consumer does (they may exist for its targets alone, like Ktor's Darwin engine). |
| `shared_native`  | `kt_native_library`  | Compiles the source set of the group of the build's konan target, and is incompatible with the other platforms. The other keys of a group, e.g. `opts`, are its attributes for the targets of the group. |
| `shared_srcs`    | `filegroup`          | The sources of every source set and platform.                                                                                                                                            |
| `shared`         | `alias`              | `shared_native` for a Kotlin/Native consumer building for a target of the groups, `shared_android` on `@platforms//os:android`, and otherwise `shared_jvm` (or, without `jvm`, `shared_android`, then `shared_native`). |

A konan target is in one group at most, and a group cannot be named `android`, `common`, `jvm`,
`native` or `srcs`.

An intermediate source set of the module, between the common source set and the platforms, is a
`kt_source_set` that refines the common one, which the platforms compile: a JVM or Android platform
lists it in its `source_sets`, and a group of `native` in its `depends_on`, as `examples/kmp` does
with Gradle's `nonAndroidMain`:

```starlark
kt_source_set(
    name = "shared_non_android",
    srcs = glob(["src/nonAndroidMain/kotlin/**/*.kt"]),
    depends_on = [":shared_common"],
)

kt_multiplatform_library(
    name = "shared",
    common_srcs = glob(["src/commonMain/kotlin/**/*.kt"]),
    android = dict(srcs = glob(["src/androidMain/kotlin/**/*.kt"]), ...),
    jvm = dict(
        srcs = glob(["src/jvmMain/kotlin/**/*.kt"]),
        source_sets = [":shared_non_android"],
    ),
    native = {
        "ios": dict(
            srcs = glob(["src/iosMain/kotlin/**/*.kt"]),
            depends_on = [":shared_non_android"],
            targets = ["ios_arm64", "ios_simulator_arm64"],
        ),
    },
)
```

The deps of a source set are deps of the rule that compiles it, but they are reachable from that
rule only through `source_sets` (and `depends_on`), which the aspects of other rule sets do not
follow. Those aspects follow Bazel's conventional dependency attributes, `deps`, `exports` and
`runtime_deps`. The dexing aspect of `android_binary` is one: it dexes the jars of the targets it
reaches and fails on a jar of the runtime classpath it did not (`Dependencies on .jar artifacts are
not allowed in Android binaries`). `kt_multiplatform_library` lists the source sets of its JVM and
Android libraries in `runtime_deps` as well, so the aspect reaches their `deps`. An explicit
`kt_jvm_library` / `kt_android_library` that sets `source_sets` should do the same
(`runtime_deps = [":common", ...]`): a source set listed there adds nothing to the classpath (it is
already a fragment of the compilation) and must be one the target compiles. Some aspects forward
nothing from a target without `JavaInfo`, not even what they reached through its `deps`: the
mobile-install of rules_android (`bazel mobile-install //androidApp`) dexes the jars of the targets
with `JavaInfo` it reaches and ignores the others, so the classes of the deps of a source set would
be missing from the installed app. A source set therefore provides a `JavaInfo` of no classes of its
own (the empty jar) that exports the `JavaInfo` of its deps: the aspect goes on to the deps and dexes
nothing twice. The `JavaInfo` makes a source set acceptable to `deps` and `exports`, which take
libraries; the rules reject it there, as it would export its deps and compile none of its sources.

The alias tells a Kotlin/Native consumer from a JVM one by the Kotlin platform type,
`@rules_kotlin//kotlin/settings:kotlin_platform_type`: `jvm` by default, and `native` for the
Kotlin/Native rules and their deps, which set it with a rule transition. So on a Linux x86_64 or
macOS arm64 host, whose platform is also the one of a konan target, a `kt_jvm_test` gets `shared_jvm`
and a `kt_native_framework` gets `shared_native`. The aliases of `@kmp_maven` select the same way,
and so does a dependency written by hand: see
[The Kotlin platform type](kmp_dependencies.md#the-kotlin-platform-type).

### KSP for the source sets

A target with `source_sets` cannot run the KSP compiler plugin (`kt_ksp_plugin` in `plugins`, see the
limitations), and Kotlin/Native has no such plugin. To process the common sources and those of a
platform together, as the Kotlin Gradle plugin does for a multiplatform module (`KSPJvmMain` of
`ksp2` for the JVM and Android, `KSPNativeMain` for a konan target), a **separate action** runs the
KSP command-line tool of the KSP release the rules pin and declares the Kotlin files it generates:

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
    common_srcs = COMMON_SRCS,
    jvm = dict(srcs = ["jvm/JvmComponent.kt", ":shared_ksp_jvm"]),
    native = {"apple": dict(srcs = ["apple/AppleComponent.kt", ":shared_ksp_apple"], targets = [...])},
)
```

- The generated files are listed in `generated`, relative to the output root of KSP (the directory of the
  package and the file name), and are outputs of the target under a directory of its name. They go in
  the `srcs` of the platform: the leaf fragment (or the group's source set) compiles them with the
  platform's own sources and the common ones, so they use the `@Inject` classes of the common code.
  No `.srcjar` and no directory is an output: JVM and Android targets with `source_sets` reject
  srcjars, and a Kotlin/Native fragment needs concrete source paths.
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
`source_sets`, and no generated `.srcjar` is supported by them. `examples/kmp` shows it with
kotlin-inject 0.9.0 components in the `jvm`, `android` and `apple` sources.

### From Gradle to Bazel

| Gradle (the Kotlin Multiplatform plugin)                                                             | Bazel (rules_kotlin)                                                                                                                                             |
|------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `kotlin { androidTarget(); iosArm64(); iosSimulatorArm64(); jvm() }` and its `sourceSets`            | `kt_multiplatform_library(common_srcs = ..., android = dict(...), native = {"ios": dict(targets = ["ios_arm64", "ios_simulator_arm64"], ...)}, jvm = dict(...))` |
| `dependsOn`, the hierarchy of the source sets                                                        | `kt_source_set(depends_on = [...])`; each group of `native` refines the common source set and the source sets of its `depends_on`, which `jvm` and `android` list in their `source_sets` |
| `commonMain.dependencies { implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2") }` | `kmp_maven.install(artifacts = [...])` in `MODULE.bazel`, and `common_deps = ["@kmp_maven//:org_jetbrains_kotlinx_kotlinx_coroutines_core"]`                     |
| `binaries.framework { baseName = "Shared"; isStatic = true }`                                        | `kt_native_framework(name = "Shared", exports = ["//shared"], transitive_exports = False)`; `export(...)` in the block is `transitive_exports = True` for the listed exports |
| The Xcode build phase that embeds the framework (`embedAndSignAppleFrameworkForXcode`)               | `filegroup(output_group = "framework_files")`, `apple_static_framework_import` and `ios_application`; or a build phase of the Xcode project that runs `bazel build` (see [The iOS app](#the-ios-app)) |
| The `androidApp` module                                                                              | `kt_android_library` and `android_binary`, with `--android_platforms`                                                                                            |
| The Android SDK of `local.properties` (`sdk.dir`) or `ANDROID_HOME`                                  | `android.sdk` and `android.ndk` of `hermetic_android_toolchains` in `MODULE.bazel`, their licenses accepted with `--repo_env` in `.bazelrc`                      |
| `./gradlew :shared:jvmTest`                                                                          | A `kt_jvm_test` that depends on `//shared`                                                                                                                       |
| `./gradlew :shared:iosSimulatorArm64Test`                                                            | No equivalent yet: `kt_native_test` runs for the konan target of the exec host only                                                                              |

## Dependencies

The deps of a Kotlin/Native rule are klibs of its konan target, and those of a source set resolve
per platform, so a library that differs per platform is an alias that selects its variant, as
`kt_multiplatform_library` and `kmp_maven` declare them.

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
reaches through `deps`, `exports` and `runtime_deps`: the source sets of a `kt_multiplatform_library`
lead it to their deps (see [Source sets and `kt_multiplatform_library`](#source-sets-and-kt_multiplatform_library)).

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
- `bazel coverage` instruments the Kotlin code compiled for the JVM and Android, the common code of
  the source sets included; the Kotlin/Native rules do not instrument theirs. An `ios_application`
  does not link the profile runtime of instrumented Swift code, so `examples/kmp_app` leaves its
  Swift app out of `--instrumentation_filter`.
- A JVM or Android target with `source_sets` cannot have `.srcjar` sources, kapt or the KSP compiler
  plugin; [KSP for the source sets](#ksp-for-the-source-sets) is a separate action with declared plain
  `.kt` outputs, which they compile. KSP of a native target is that action too; there is no inline
  KSP plugin for Kotlin/Native. Generated Java sources, classes and resources of that action are not
  supported.
- The JVM and Android variants of Maven libraries bring the `kotlin-stdlib` jar of the manifest next
  to the standard library of the Kotlin toolchain. The dexing of `android_binary` tolerates the
  duplicate classes; a substitution of `kmp_maven.install` aligns the versions (see the
  [limitations of the dependencies](kmp_dependencies.md#limitations)).

## Examples

| Example                                   | Shows                                                                                                                                                                                       | Hosts                                                                         |
|-------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------|
| [`examples/native`](../examples/native)   | klibs for the host and for every konan target, an executable run end to end, tests, Linux executables linked for both Linux targets, and a framework and its `framework_files` per Apple target. | Linux x86_64 and macOS arm64, the Apple targets on macOS only.             |
| [`examples/kmp`](../examples/kmp)         | A `kt_multiplatform_library` for the JVM, Android, the Apple and the Linux targets with an intermediate source set, the same kind of module declared with `kt_source_set`, JVM and native tests, `kotlinx-coroutines-core` from `kmp_maven`, and kotlin-inject components generated by KSP for the JVM, Android and Apple sources. | Linux x86_64 and macOS arm64, the Apple klibs on macOS only; Bazel 8.4.2 or newer. |
| [`examples/kmp_app`](../examples/kmp_app) | An Android app and an iOS app that share one `kt_multiplatform_library`, laid out like the project of the Kotlin Multiplatform wizard.                                                      | macOS arm64 builds both apps, Linux x86_64 the Android app; Bazel 8.4.2 or newer. |

Each builds and tests with `bazel build //...` and `bazel test //...` in its directory.
