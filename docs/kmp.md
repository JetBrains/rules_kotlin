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
- **Other hosts and platforms**: no Kotlin/Native toolchain is registered for another exec host, or
  for a platform of no konan target, e.g. the x86_64 iOS simulator (`ios_x64`). Built for such a
  platform, a Kotlin/Native target fails the analysis with `No matching toolchains found` for
  `//kotlin/internal/native:kt_native_toolchain_type`, unless its `target_compatible_with` skips it.
- **Xcode**: the Apple targets need a macOS host with Xcode, whose SDK konanc finds with `xcrun`:
  Xcode 15.4 or newer for Kotlin/Native 2.5.20-dev-5696 (`minimalXcodeVersion` of its
  `konan.properties`).
- **Compiler**: Kotlin/Native 2.5.20-dev-5696, a dev build of the next Kotlin release, which compiles
  klibs through the Kotlin Build Tools API (see
  [The Kotlin/Native Build Tools API](#the-kotlinnative-build-tools-api)). It is pinned apart from the
  Kotlin compiler of the JVM toolchain, 2.4.21, as klibs are coupled to the Kotlin/Native compiler
  that produced them; `kotlin_native.version(version = "2.4.21")` stays on the release.
- **Bazel**: the rules build with Bazel 7 and newer (`examples/native` runs with 7.x, 8.x and 9.x).
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
come from the `kotlin_native` module extension, two per exec host and two for the release:

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
- `kotlin_native_build_tools_api`: the Build Tools API jar of the release rules_kotlin pins, which the
  launcher of the Kotlin/Native actions is compiled against, whatever release the `version` tag
  selects.

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
`kt_multiplatform_library` and of the private klib of `kt_native_binary`, `kt_native_test`,
`kt_native_xctest_library` and `kt_native_framework`, runs a `NativeKlibCompilationOperation` of the
[Kotlin Build Tools API](https://youtrack.jetbrains.com/issue/KT-78202) in-process in its action,
instead of the konanc command line. It gets the same flags and writes the same klib and header klib,
its diagnostics name the sources relative to the execroot, and the action keeps the mnemonic
`KotlinNativeKlibCompile` and its exit codes. A link, which produces a program, a framework or
a static library, runs the konanc command line: the Build Tools API has no link operation.

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
| [`kt_native_binary`](kotlin.md#kt_native_binary)       | `<name>.kexe`      | Links an executable, which `bazel run` runs on a host of its target, with the files of its `data`. Its `main` is in the `srcs` or in a dep.                                                             |
| [`kt_native_test`](kotlin.md#kt_native_test)           | `<name>.kexe`      | Links the `kotlin.test` tests of its sources into a test runner, which `bazel test` runs on a host of its konan target, with the files of its `data`. Its `associates` are libraries whose internal declarations it sees; runner options, e.g. `--ktest_filter=<pattern>`, go in `args` or `--test_arg`. |
| [`kt_native_xctest_library`](kotlin.md#kt_native_xctest_library) | `_kt_native/<name>/lib<package>_<name>.a` | Links the `kotlin.test` tests of its sources into a static library with an XCTest case that runs them, which rules_apple's `ios_unit_test` takes in `deps`: see [Tests in the iOS simulator](#tests-in-the-ios-simulator). |
| [`kt_native_framework`](kotlin.md#kt_native_framework) | `<name>.framework` | Links a static Apple framework, named after the target like the prefix of its Objective-C names, whose header declares the API of its `srcs` and `exports` (and of their exports, unless `transitive_exports = False`). `bundle_id` is its `CFBundleIdentifier`. |
| [`kt_klib_import`](kotlin.md#kt_klib_import)           | the `klib`         | A prebuilt klib of one `konan_target`, e.g. of a Maven library, as a dep.                                                                                                                               |

The linking rules compile their sources, if any, into a private klib, `_kt_native/<name>.klib`, and
link it with the klibs of their deps, as the Kotlin Gradle plugin does: `opts` are konanc options of
the compilation and `link_opts` konanc options of the link, e.g. `-opt`. `kt_native_library` and the linking
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

### Options, data and inputs

- **Entry point.** A `kt_native_binary` starts at the function `main` of the root package; without
  one, the link fails with `Could not find '/main' function`. Another function is named in full
  with the konanc option `-e`, the `settings.native.entryPoint` of the Kotlin Toolchain:
  `link_opts = ["-e", "org.example.main"]`.
- **Linker arguments.** `link_opts` are options of konanc, not of the linker it runs:
  `link_opts = ["-dead_strip"]` fails with `Invalid argument`. An argument of the linker, one of the
  `linkerOptions` of the Kotlin Toolchain, is the value of the konanc option `-linker-option`:
  `link_opts = ["-linker-option", "-dead_strip"]`.
- **Data.** `data` lists the files a `kt_native_binary` or a `kt_native_test` reads when it runs,
  with their own runfiles. They are in its runfiles tree, where `bazel run` and `bazel test` start
  it, a file of the main repository at its path from the root of the workspace: `data_test` of
  `examples/native` opens `greeting.txt` with `fopen("greeting.txt", "r")`.
- **Tests for another konan target.** `bazel test` runs a `kt_native_test` on the exec host, so for
  the konan target of that host, `linux_x64` or `macos_arm64`, as by default. Built for another
  target, e.g. with `--platforms`, the runner links, like a `cc_test` for another platform, but
  nothing runs it: not the host, the iOS simulator or an emulator. `target_compatible_with` on a
  test skips it for the platforms it does not run on. The tests of an iOS target run in the
  simulator as a `kt_native_xctest_library`: see
  [Tests in the iOS simulator](#tests-in-the-ios-simulator), and [iOS tests](#ios-tests) for those
  of a `kt_multiplatform_test`.
- **Staged link dependencies.** A binary, a test, a test library or a framework links for the
  targets of `kotlin_native.targets(...)` only. A build of every target for another one, e.g.
  `bazel build //... --platforms=@rules_kotlin//kotlin/native/platforms:linux_arm64`, fails on each
  of them with `the Kotlin/Native link dependencies of linux_arm64 are not staged`: add the target
  to the tag, or make them incompatible with that platform.
- **Sources.** A `kt_native_library` without `srcs` compiles an empty klib and passes its `exports`
  on, like a `kt_jvm_library` that only exports. A `kt_native_binary` needs `srcs` or `deps`, a
  `kt_native_test` and a `kt_native_xctest_library` `srcs`, and a `kt_native_framework` `srcs` or
  `exports`: without them the analysis fails with what to add.
- **Module names.** `module_name`, derived from the label by default, is the `unique_name` of the
  klib. No analysis check finds two klibs with one name among the deps of a target, e.g. two
  imports of one library: konanc fails with `The same 'unique_name=<name>' found in more than one
  library`, naming both files.

### Frameworks and the `framework_files` output group

`kt_native_framework` links a static framework (`-Xstatic-framework`) for an Apple konan target, and
fails for another one: its `target_compatible_with`, e.g. `["@platforms//os:ios"]`, skips it there.
The framework, its module and the prefix of its Objective-C names are named after the target, so a
name that starts with a digit fails the analysis.
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
directory, so a `filegroup` of the output group bridges the two: see [The iOS app](#the-ios-app).

The link always gets the whole closure of the `deps` and `exports`; what the header declares is the
API of the `exports` (`-Xexport-library`). By default it includes their own exports too, as Bazel's
`exports` are transitive; `transitive_exports = False` restricts it to the listed klibs, as a
framework of the Kotlin Gradle plugin exports only the libraries its `export()` names (its
`transitiveExport` is off by default). A module whose `api` dependencies are Compose or Ktor keeps
them out of its Objective-C header that way: `kt_native_framework(name = "shared", exports =
["//app/shared"], transitive_exports = False)` declares the API of `app/shared` alone.

### Tests in the iOS simulator

`kt_native_xctest_library` links the tests of its sources for the test bundle of an Apple platform,
where `kt_native_test` links a runner for the exec host. It takes `srcs`, `associates`, `deps` and
the options of the linking rules, like `kt_native_test`, and provides a `CcInfo`: a static library
with the tests, the klibs of its deps and the Kotlin/Native runtime,
`_kt_native/<name>/lib<package>_<name>.a`, and an XCTest case, `KotlinNativeTests_<package>_<name>`, which
the rule compiles with the Objective-C compiler of the C++ toolchain. rules_apple's `ios_unit_test`
links its `deps` into the test bundle and runs it in the simulator:

```starlark
load("@rules_apple//apple:ios.bzl", "ios_unit_test")
load("@rules_kotlin//kotlin:native.bzl", "kt_native_library", "kt_native_xctest_library")

kt_native_library(
    name = "greeter",
    srcs = ["Greeter.kt"],
)

kt_native_xctest_library(
    name = "greeter_test_lib",
    testonly = True,
    srcs = ["GreeterTest.kt"],
    associates = [":greeter"],
    # A build of //... for the host skips it; the test builds it for iOS.
    target_compatible_with = ["@platforms//os:ios"],
)

ios_unit_test(
    name = "greeter_test",
    minimum_os_version = "15.0",
    deps = [":greeter_test_lib"],
)
```

`bazel test //:greeter_test` needs no `--platforms`: the test bundle of the test builds its deps for
an iOS platform of its own, that of `--ios_multi_cpus` and, by default on an arm64 Mac, the iOS
simulator, whose konan target, `ios_simulator_arm64`, the library is linked for. The test itself
stays a target of the platform of the build. The one test method of the XCTest case runs the
Kotlin tests in the process of the test and fails when one of them fails. XCTest reports that one
test; the names and results of the Kotlin tests are in the test log, as the Kotlin test runner
prints them:

```
Test Case '-[KotlinNativeTests_greeter_test_lib testKotlin]' started.
[ RUN      ] greeter.GreeterTest.greets
[       OK ] greeter.GreeterTest.greets (0 ms)
[ RUN      ] greeter.GreeterTest.decorates
[       OK ] greeter.GreeterTest.decorates (0 ms)
[  PASSED  ] 2 tests.
Test Case '-[KotlinNativeTests_greeter_test_lib testKotlin]' passed (0.003 seconds).
```

rules_kotlin does not depend on rules_apple: the module that declares the test does, and loads
`ios_unit_test` itself. [`kt_multiplatform_test`](#ios-tests) declares the library and the test for
the iOS targets of a multiplatform library.

- **Requirements.** The link dependencies of the iOS target are staged (`kotlin_native.targets`),
  and the C++ toolchain of the platform compiles Objective-C, as the toolchains of apple_support do
  on a Mac. The analysis fails with what to do for a target that is not an Apple one, for a library
  without sources and for a platform without a C++ toolchain.
- **Several libraries in a test bundle.** The XCTest case and the other symbols a library exports,
  e.g. the Objective-C classes konanc names after the static library, are named after the package
  and the name of the library, with `_` for every character that is not a letter or a digit:
  `KotlinNativeTests_app_shared_tests` and `libapp_shared_tests.a` for `//app/shared:tests`; the
  archive is in a directory of the name of the target, so targets of one package never share an
  output file. A test takes several `kt_native_xctest_library` targets in `deps`, also ones of the same name in
  different packages, and XCTest runs and reports the test case of each. Each is a link of its own,
  with its own copy of the Kotlin/Native runtime and of the klibs of its deps: the libraries of one
  bundle share no Kotlin state, e.g. no top-level property of a common dep. Two libraries whose
  labels differ in nothing but such characters, e.g. `//app:shared_tests` and `//app/shared:tests`,
  build on their own and in separate bundles, and fail to link only when one bundle takes both,
  with duplicate symbols.
- **Linking.** Only the XCTest case is linked whole (`alwayslink`), as XCTest finds its class at
  run time. The static library links like any other one, as konanc links a binary: the linker
  takes the object files that something refers to. The Kotlin code of the library is one object
  file, with the function the XCTest case calls, so every test is in the bundle. The other object
  files are those of the static libraries that the klibs embed, e.g. Skia in a klib of Compose
  Multiplatform, which konanc copies into the library, some of them more than once: loading all
  of them (`-force_load`) fails with duplicate symbols. A native library that a klib refers to
  without embedding it, e.g. an Objective-C or Swift SDK behind a cinterop klib, is a dep of the
  test, next to the library: `ios_unit_test(deps = [":greeter_test_lib", "//sdk"])`. A static
  library whose Objective-C categories have to load needs `linkopts = ["-ObjC"]` on the test, as
  in an app.
- **No options of the test runner.** The Kotlin test runner gets none, e.g. no `--ktest_filter`: it
  runs every test of the library.
- **Deployment target.** Kotlin/Native compiles for the iOS version its `konan.properties` gives as
  `minVersion.ios`. With a lower `minimum_os_version`, the test bundle links with the warning that
  an object file `was built for newer 'iOS-simulator' version` than the one being linked. Another
  warning of the linker does not come from the library: with a `minimum_os_version` lower than the
  one the XCTest framework of the Xcode was built for, it reports that `XCTest.framework/XCTest`
  `was built for newer version`.
- **Coverage.** The report of `bazel coverage` has no Kotlin code of the test, which the
  Kotlin/Native rules do not instrument. The runner of rules_apple fails a test of a coverage
  build that passed when its process wrote no profile (`coverage.profraw: No such file or
  directory`), which only instrumented code writes. With `--experimental_use_llvm_covmap` the
  XCTest case of the library is instrumented, and the test passes. In the default format, gcov,
  it is not: the test bundle does not link the runtime of that format, as a test of Objective-C
  sources shows with rules_apple 5.x (`Undefined symbols ... _llvm_gcov_init`). So a test whose
  bundle has Kotlin tests alone sets `collect_code_coverage = False` to pass in either format;
  `kt_multiplatform_test` sets it.

The rule runs in the iOS simulator. If the default runner of the rules_apple in use does not start
the simulator of the installed Xcode, set `runner =
"@rules_apple//apple/testing/default_runner:ios_xctestrun_ordered_runner"` on the `ios_unit_test`.
Devices need signing and are not supported, and neither is the test bundle of another Apple
platform.

## `kt_multiplatform_library`

`@rules_kotlin//kotlin:kmp.bzl` has the multiplatform rules:
[`kt_multiplatform_library`](kotlin.md#kt_multiplatform_library),
[`kt_multiplatform_test`](kotlin.md#kt_multiplatform_test) for its tests (see
[Tests, binaries and frameworks](#tests-binaries-and-frameworks)), and the rules of
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

`aliases` names the sets of platforms that the hierarchy has no group for, as the `aliases:` of a
Kotlin Toolchain module do. It is a dict of the name of each alias to its platforms:

```starlark
aliases = {"non_android": ["jvm", "ios_arm64", "ios_simulator_arm64"]},
```

A name is made of lowercase letters, digits and `_`, and is not the name of a group or a platform.
An alias lists platforms of `platforms`, not groups, and names a set that nothing else names: not
the platforms of a group, a single platform, every platform, or the platforms of another alias. A
group, a platform or an alias is above another when the hierarchy puts it above, and otherwise when
its platforms include those of the other and more. With `platforms` listing those three platforms
and `android`, `non_android` is below `common` and above `jvm`, `native`, `apple`, `ios` and both
iOS targets.

The lists of a group, a platform or an alias are `<attr>_<qualifier>`: `<attr>` is `srcs`, `deps`,
`exports` or `plugins`, and `<qualifier>` the name of a group or a platform below `common`, or of an
alias, e.g. `srcs_native`, `deps_apple`, `plugins_ios`, `exports_linux`, `srcs_ios_arm64`, `deps_jvm`
or `srcs_non_android`. The `srcs`, `deps`, `exports` and `plugins` of the macro are the lists of
`common`. Each is a plain list of labels, and an empty one is the same as none, so a wrapper macro
can pass a `glob()` for every group. The `deps`, `exports` and `plugins` of `jvm` and `android`,
whose libraries build a single platform, may also be, or end with, a `select()`. Each platform
receives, per attribute, the lists of the groups and aliases above it and its own, from `common`
down to itself:

| Platform    | `deps` of its library                                         |
|-------------|---------------------------------------------------------------|
| `jvm`       | `deps + deps_jvm`                                             |
| `android`   | `deps + deps_android`                                         |
| `ios_arm64` | `deps + deps_native + deps_apple + deps_ios + deps_ios_arm64` |
| `linux_x64` | `deps + deps_native + deps_linux + deps_linux_x64`            |

Below the alias `non_android` above, `jvm` receives `deps + deps_non_android + deps_jvm`, and
`ios_arm64` receives `deps + deps_non_android + deps_native + deps_apple + deps_ios +
deps_ios_arm64`. An alias and a group may share platforms without one being above the other, e.g. an
alias of `jvm` and `ios_arm64` and the group `ios` of both iOS targets. A dep that both list reaches
the platform they share once.

`exports` and `plugins` propagate the same way, and the `srcs` make the fragments (see
[Fragments](#fragments)). A dep resolves for every platform that receives it: in the lists of
`common`, of the groups and of the aliases, an alias target that selects the variant of the
platform, such as those of `kmp_maven`, or another `kt_multiplatform_library`; in those of `jvm` and
`android`, JVM libraries;
in those below `native`, klibs of the konan target or aliases that select them. A JVM library alone
fails the native library, which takes klibs only. When the JVM compiles no source of the module,
`<name>_jvm` gets its deps as `runtime_deps`: a `kt_jvm_library` takes no `deps` without sources.
`plugins` are `kt_compiler_plugin` targets, the only kind of plugin `kt_native_library` takes; KSP
runs as a separate action instead: see
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
| A dependency that is `exported`               | A label in `exports`                                 |
| `src@ios/`, `dependencies@ios:`               | `srcs_ios`, `deps_ios`, `exports_ios`, `plugins_ios` |
| `settings@android:`                           | `android = dict(...)`, likewise `jvm` and `native`   |
| Lists appended from common to specific        | The same, per attribute                              |
| `aliases:` with `nonAndroid: [jvm, iosArm64]` | `aliases = {"non_android": ["jvm", "ios_arm64"]}`    |
| `src@nonAndroid/`, `dependencies@nonAndroid:` | `srcs_non_android`, `deps_non_android`, likewise `exports` and `plugins` |
| `test/`, `test@ios/`, `test-dependencies:`    | The `srcs`, `srcs_ios` and `deps` of a `kt_multiplatform_test` (see [Tests, binaries and frameworks](#tests-binaries-and-frameworks)) |
| `settings: kotlin: linkerOptions`             | `link_opts = ["-linker-option", ...]` of the rule that links |
| `settings: native: entryPoint`                | `link_opts = ["-e", ...]` of `kt_native_binary`      |

A Bazel keyword cannot hold `@`, so the qualifier follows `_`: `srcs@ios` is `srcs_ios`.

### Checks

The macro checks the declaration when it is called, before any `select()` is resolved, comparing
labels as it compares the `srcs` (`a.kt`, `:a.kt` and `//shared:a.kt` are one label). It fails with
`kt_multiplatform_library <name>: <message>`, whose names come from the hierarchy and the aliases:

| Declaration                                         | Message                                                                                                                                                       |
|-----------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------|
| No `platforms`, or an empty list                    | `it declares no platforms: list them in platforms, e.g. ["jvm", "android", "ios_arm64"]`                                                                      |
| A group in `platforms`                              | `platforms lists the group 'ios': list the platforms to build for instead, among ios_arm64, ios_simulator_arm64`                                              |
| An unknown name in `platforms`                      | `platforms lists the unknown platform 'ios_arm'; the supported ones are android, ios_arm64, ...`, with a hint for a label                                      |
| A platform no library builds yet                    | `platform 'ios_x64' is not supported yet: rules_kotlin has no Kotlin/Native toolchain for it`                                                                 |
| A platform listed twice                             | `platforms lists 'jvm' twice`                                                                                                                                 |
| `aliases` that is not a dict                        | `aliases must be a dict of a name to the platforms it groups, not a list`                                                                                     |
| An alias whose name is not valid                    | `aliases: 'nonAndroid' is not a name of lowercase letters, digits and _`                                                                                      |
| An alias named after a group or a platform          | `aliases: 'apple' is a group of the hierarchy: give the alias another name`                                                                                   |
| An alias without platforms                          | `aliases: 'non_android' must list the platforms it groups`                                                                                                    |
| A group in an alias                                 | `aliases: 'non_android' lists the group 'native': list its platforms instead, among ios_arm64, ios_simulator_arm64`                                           |
| An unknown name in an alias                         | `aliases: 'non_android' lists the unknown platform 'ios_arm'; the listed ones are android, ios_arm64, ...`                                                    |
| A platform of an alias that is not listed           | `aliases: 'non_android' lists linux_x64, which platforms does not list`                                                                                       |
| A platform twice in an alias                        | `aliases: 'non_android' lists 'jvm' twice`                                                                                                                    |
| An alias of the platforms of a group or a platform  | `aliases: 'apple_only' groups the platforms of apple: use that qualifier instead`; `'desktop' groups jvm alone: ...`; `'all' groups every platform: ...`      |
| Two aliases of the same platforms                   | `aliases: 'jvm_ios' and 'ios_jvm' group the same platforms: declare one of them`                                                                              |
| An unknown qualifier                                | `srcs_iso: 'iso' is neither a group, a platform nor an alias; the groups are apple, ios, linux, macos, native and the platforms android, ...`                 |
| `common` as a qualifier                             | `srcs_common: the sources of every platform are the srcs of the macro`                                                                                        |
| Another attribute with a qualifier                  | `opts_ios: only srcs, deps, exports and plugins take a group or a platform`; `opts_non_android: only srcs, deps, exports and plugins take an alias`           |
| Entries of a group none of whose platforms is listed | `srcs_ios lists sources, but platforms lists no ios platform: add ios_arm64 or ios_simulator_arm64, or remove srcs_ios`                                     |
| Entries of a platform that is not listed            | `deps_linux_x64 lists deps, but platforms does not list linux_x64`                                                                                            |
| A `select()` where a plain list is required         | `srcs_ios must be a list of labels, not a select: ...`                                                                                                        |
| A label twice in one list                           | `srcs_ios lists a.kt twice`                                                                                                                                   |
| A label that a list above already lists             | `deps_ios lists :lib, which deps_apple already lists`, or `which the deps of the macro already list`                                                          |
| A source in two lists, neither above the other      | `srcs_ios_arm64 and srcs_ios_simulator_arm64 both list a.kt: a source is in one fragment; list it in srcs_ios alone`; without a list of exactly their platforms, `declare an alias of their platforms, e.g. aliases = {"jvm_native": [...]}, and list it in srcs_jvm_native alone` |
| Settings of a library that is not declared          | `android sets attributes of the Android library, but platforms does not list android`                                                                         |
| An attribute the macro sets, in a settings dict     | `jvm sets srcs: pass srcs_jvm to the macro`; `native sets kmp_fragments, which the macro derives from the sources`                                            |
| A dict of attributes for another node               | `ios: only jvm, android and native take a dict of attributes of their library`                                                                                |

The macro cannot read the labels of a `select()` in the `deps`, `exports` or `plugins` of `jvm` or
`android`, which comes after the lists above it: Bazel reports a label repeated there instead, as
`Label '<label>' is duplicated in the 'deps' attribute of rule '<name>_jvm'`.

### Fragments

The macro derives the fragments of the compilations from its lists of sources: a fragment per group
and alias with sources, and a leaf per platform.

- The sources of a group or an alias form one fragment named after it: `common` for the `srcs` of
  the macro, `ios` for `srcs_ios`, `non_android` for `srcs_non_android`. Its platforms are the
  listed platforms at or below the group, or those of the alias: above, every platform compiles
  `common`, and both iOS targets compile `ios`.
- A fragment refines the fragments directly above it, as a Gradle source set depends on another:
  `ios` refines `common`, or `apple` when `srcs_apple` lists sources. Above is the order of
  [the hierarchy](#the-hierarchy) and of the platforms: `apple` also refines an alias whose
  platforms are the Apple targets and more, although the hierarchy does not relate them. Groups of
  the same platforms stay apart: in a library of iOS targets only, `common`, `native`, `apple` and
  `ios` are four fragments, so an `expect` declaration in one and its `actual` in a lower one
  compile.
- The sources of a platform stay in the library of that platform as its leaf fragment, named after
  the platform, `jvm`, `android` or the konan target, which refines the fragments directly above the
  platform. A leaf may be empty: `ios_arm64` and `ios_simulator_arm64` are, as both targets compile
  the fragment `ios`.

The library of a platform compiles every fragment of its platform, most shared first, each after
those it refines, then its leaf, in one compilation (`-Xfragments`, `-Xfragment-sources` and
`-Xfragment-refines`): with sources in each of those groups, the native library built for the iOS
simulator gets `-Xfragments=common,native,apple,ios,ios_simulator_arm64`. A fragment has no deps:
each platform compiles all its fragments against its own deps, which resolve in its configuration,
JVM libraries for the JVM and Android and klibs of the konan target for Kotlin/Native. So the deps
of the sources of a group or an alias are in the deps of that group or alias, or above, and those of
the common code once in the `deps` of the macro, which every platform resolves: an alias target that
selects the variant of the platform, like those of `kmp_maven`, is one label for all of them.

A source is in one fragment, so one list names it. A source set of the Gradle build outside the
default hierarchy is an alias of the platforms compiling it, as `examples/kmp` declares Gradle's
`nonAndroidMain`:

```starlark
COMMON = glob(["common/**/*.kt"])

NON_ANDROID = glob(["non_android/**/*.kt"])  # Gradle's nonAndroidMain: every platform but Android

kt_multiplatform_library(
    name = "shared",
    srcs = COMMON,
    aliases = {"non_android": ["jvm", "ios_arm64", "macos_arm64"]},
    android = dict(...),
    platforms = ["jvm", "android", "ios_arm64", "macos_arm64"],
    srcs_android = glob(["android/**/*.kt"]),
    srcs_apple = glob(["apple/**/*.kt"]),
    srcs_jvm = glob(["jvm/**/*.kt"]),
    srcs_non_android = NON_ANDROID,
    deps = DEPS,
)
```

| Sources                           | Fragment                                    | Refines       |
|-----------------------------------|---------------------------------------------|---------------|
| `COMMON`, the `srcs` of the macro | `common`                                    |               |
| `NON_ANDROID`                     | `non_android`                               | `common`      |
| `apple/`                          | `apple`                                     | `non_android` |
| `jvm/`                            | `jvm`, the leaf of the JVM                  | `non_android` |
| `android/`                        | `android`, the leaf of Android              | `common`      |
| None                              | `ios_arm64` and `macos_arm64`, empty leaves | `apple`       |

`examples/kmp` also lists `linux_arm64` and `linux_x64`, whose `srcs_linux` are the fragment `linux`,
which refines `non_android` too.

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
| `shared`                     | `alias`                             | `shared_native` for a Kotlin/Native consumer, `shared_android` for an Android one (`@rules_kotlin//kotlin/settings:android`), and otherwise `shared_jvm` (or, without `jvm`, `shared_android`, then `shared_native`).   |

A consumer depends on the alias or on the library of a platform. The libraries get their fragments
through an internal attribute, `kmp_fragments`, which only the macro sets.

The alias tells a Kotlin/Native consumer from a JVM one by the Kotlin platform type,
`@rules_kotlin//kotlin/settings:kotlin_platform_type`: `jvm` by default, and `native` for the
Kotlin/Native rules and their deps, which set it with a rule transition. So on a Linux x86_64 or
macOS arm64 host, whose platform is also the one of a konan target, a `kt_jvm_test` gets `shared_jvm`
and a `kt_native_framework` gets `shared_native`. A Kotlin/Native consumer building for a konan
target that `platforms` does not list gets `shared_native` too, which is incompatible with that
target, and so is the consumer: `bazel build //...` skips it, and a build that names it fails with
the incompatibility.

The alias tells an Android consumer from a JVM one by `@rules_kotlin//kotlin/settings:android`,
which matches the JVM and Android rules:

- on an Android platform (`@platforms//os:android`), where an `android_binary` builds its deps (see
  [The Android app](#the-android-app));
- below an `android_local_test` or a `kt_android_local_test`, which build for the host platform:
  their rule turns the host hybrid mode of rules_android on for the test and its deps
  (`@rules_android//rules/flags:android_host_hybrid_mode`, rules_android 0.8.0 and newer).

So a local test gets `shared_android` and the Android variants of `@kmp_maven` with no platform
flag, as the unit tests of the Android target of a Gradle module do, and a `kt_jvm_test` next to it
gets `shared_jvm`. The setting never matches below the Kotlin/Native rules, and a compiler plugin,
a `kt_plugin_cfg` or a `kt_ksp_plugin` of an Android target still gets `shared_jvm`: a tool runs
in the JVM of the compiler, whatever the compilation targets.

The aliases of `@kmp_maven` tell the consumers apart the same way, and so does a dependency written
by hand: see [The Kotlin platform type](kmp_dependencies.md#the-kotlin-platform-type).

`shared_android` builds for any platform, as an `android_library` does: `bazel build //...` on the
host compiles it against the JVM variants of the aliases in its deps. A library that only builds
for Android, e.g. one that depends on a library without a JVM variant, selects its compatibility
on the same setting, which keeps it out of the host build and in the deps of a local test:

```starlark
kt_android_library(  # or android = dict(target_compatible_with = ...) of kt_multiplatform_library
    name = "android_only",
    target_compatible_with = select({
        "@rules_kotlin//kotlin/settings:android": [],
        "//conditions:default": ["@platforms//:incompatible"],
    }),
    ...
)
```

`target_compatible_with = ["@platforms//os:android"]` would make the library incompatible with the
host platform of a local test, which Bazel then skips with it.

A library compiles the sources of its fragments into its own jar or klib, so the aspects of other
rule sets, which follow `deps`, `exports` and `runtime_deps`, e.g. the dexing aspect of
`android_binary` and the mobile-install of rules_android, handle it as any other library.

### Tests, binaries and frameworks

[`kt_multiplatform_test`](kotlin.md#kt_multiplatform_test) declares the tests of a
`kt_multiplatform_library` the way the library declares its sources, as the `test/` and
`test@<platform>/` of a Kotlin Toolchain module or the `commonTest` and `jvmTest` of a Gradle build:
tests written once run on every platform, with the helpers each platform implements. As in
`examples/kmp`:

```starlark
load("@rules_kotlin//kotlin:kmp.bzl", "kt_multiplatform_test")

kt_multiplatform_test(
    name = "shared_test",
    srcs = ["common/SharedTest.kt"],                          # commonTest: kotlin.test, an `expect` helper
    deps_jvm = [
        "@maven//:junit_junit",
        "@rules_kotlin//kotlin/compiler:kotlin-test",
        "@rules_kotlin//kotlin/compiler:kotlin-test-junit",
    ],
    library = "//shared",
    platforms = ["jvm", "android", "linux_x64", "macos_arm64"],
    srcs_android = ["android/PlatformOfTheTest.android.kt"],  # androidUnitTest: its `actual`
    srcs_jvm = ["jvm/PlatformOfTheTest.jvm.kt"],              # jvmTest: its `actual`
    srcs_native = ["native/PlatformOfTheTest.native.kt"],     # nativeTest: its `actual`
    deps_android = [...],                                     # those of deps_jvm
)
```

- **Declaration.** `platforms`, `aliases`, and the `srcs`, `deps` and `plugins` of the macro and of
  a group, a platform or an alias (`srcs_jvm`, `deps_native`, `srcs_non_android`) are those of
  [`kt_multiplatform_library`](#kt_multiplatform_library), for the test: its platforms may be some
  of those of the library, and its aliases are its own. A test has no `exports`. `jvm`, `android`,
  `native` and `ios` are dicts of the other attributes of the test of that platform, e.g.
  `jvm = dict(jvm_flags = ["-Xmx1g"])`, and the other keyword arguments, e.g. `size`, `timeout` or
  `tags`, go to every test. The [checks](#checks) are those of the library, with messages that
  start with `kt_multiplatform_test <name>:`; a platform that no list gives test sources fails too,
  with the lists to add them to, and the iOS targets have [checks of their own](#ios-tests).
- **Fragments.** The test sources of a group or an alias are a [fragment](#fragments) of the tests
  of its platforms, named after it, and those of a platform are the leaf of its test: a common test
  calls an `expect` helper that `srcs_jvm` and `srcs_native` implement with `actual`.
  `bazel run //<pkg>:<name>.fragments` prints the test fragments.
- **Friends.** The test of a platform compiles the test fragments only, with the library of its
  platform as `associates`: `<library>_jvm`, `<library>_android` or `<library>_native`, the
  targets next to the alias `library` names. So every test fragment sees the `internal`
  declarations of every fragment of the library of that platform, as the test compilation of a
  Gradle module sees those of its main one. The library is a dep of the test; the other deps are
  the lists of the test. A dep of the library that the library does not export is not one of the
  test: a test that uses it lists it too, and the library itself is not listed in `deps`.
- **What runs.** The JVM and Android tests use JUnit 4: `kotlin.test` with `kotlin-test-junit`, or
  JUnit itself. The sources of a test are those of several fragments, so no single class names
  its tests: by default the test runs every public class of its own jar that has a method
  annotated with `@Test`, or is annotated with `@RunWith`, and fails when the jar has none. Setting
  `test_class` in `jvm` or `android`, or a `main_class` other than the test runner of Bazel, runs
  that instead. The native test generates its runner, as any `kt_native_test` does, and so does
  the library of the iOS tests, which an XCTest case runs.

With the name `shared_test`, the macro declares:

| Target                            | Rule                                | Content                                                                                                                                                                              |
|-----------------------------------|-------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `shared_test_fragment_<fragment>` | `kt_kmp_fragment` (internal)        | A private, testonly target per test fragment.                                                                                                                                        |
| `shared_test_jvm`                 | `kt_jvm_test`                       | When `platforms` lists `jvm`: the attributes of `jvm`, the test fragments of the JVM and its leaf, with `<library>_jvm` as associate.                                                |
| `shared_test_android`             | `kt_android_local_test`             | When `platforms` lists `android`: the attributes of `android`, e.g. its `manifest`, the test fragments of Android and its leaf, with `<library>_android` as associate.               |
| `shared_test_native`              | `kt_native_test`                    | When `platforms` lists konan targets other than those of iOS: for the konan target of the build's platform, its test fragments and its leaf, with `<library>_native` as associate. It is incompatible with the other platforms. |
| `shared_test_ios_lib`             | `kt_native_xctest_library`          | When `platforms` lists iOS targets: for the iOS target of the test bundle, its test fragments and its leaf, with `<library>_native` as associate, and the `opts`, `link_opts` and `module_name` of `native`. It is incompatible with the other platforms. |
| `shared_test_ios`                 | `ios_test_rule`                     | When `platforms` lists iOS targets: the test of the rule the macro is given, with `shared_test_ios_lib` and then the `deps` of `ios` as its `deps`, and the other attributes of `ios`. See [iOS tests](#ios-tests). |
| `shared_test.fragments`           | `kt_kmp_fragments_graph` (internal) | An executable target that prints the derived test fragments.                                                                                                                         |
| `shared_test`                     | `test_suite`                        | The tests above.                                                                                                                                                                     |

`bazel test //tests:shared_test`, with no platform flag, runs the tests the host can run: on a macOS
arm64 host, `shared_test_jvm`, `shared_test_android`, `shared_test_native` for `macos_arm64` and,
in the simulator, `shared_test_ios`; on a Linux x86_64 host, the first three, the native one for
`linux_x64`. The Android test is a local test: it runs on the JVM of the host, with the Android
library of the module and the Android variants of its deps, against the `android.jar` of the SDK,
whose methods are stubs; a test that calls into the Android framework adds Robolectric, as any
`kt_android_local_test` does. The
native test runs as a `kt_native_test` does, for the konan target of the exec host only (see
[Options, data and inputs](#options-data-and-inputs)): for a konan target of `platforms` that the
host does not run, e.g. `linux_arm64`, it links with `--platforms` but does not run, and for a konan
target that `platforms` does not list it is skipped. The test cannot read the declaration of the
library: a platform of the test that the library does not list is a missing `<library>_jvm` or
`<library>_android`, or a native or iOS test that is skipped as incompatible.

#### iOS tests

A `kt_native_test` of an iOS target links, but nothing runs it. So the iOS targets of `platforms`
have a test of their own, `<name>_ios`, which runs their tests in a test bundle, e.g. in the iOS
simulator, as [`kt_native_xctest_library`](#tests-in-the-ios-simulator) describes. rules_apple
builds and runs the bundle, and rules_kotlin does not depend on it: the `BUILD` file loads
`ios_unit_test` and passes it to the macro as `ios_test_rule`, with the deployment target in `ios`,
as `examples/kmp_app` does for the tests of its `src/commonTest`:

```starlark
load("@rules_apple//apple:ios.bzl", "ios_unit_test")
load("@rules_kotlin//kotlin:kmp.bzl", "kt_multiplatform_test")

kt_multiplatform_test(
    name = "shared_test",
    srcs = glob(["src/commonTest/kotlin/**/*.kt"]),
    ios = dict(minimum_os_version = "15.0"),  # the other attributes of ios_unit_test
    ios_test_rule = ios_unit_test,
    library = ":shared",
    platforms = ["jvm", "android", "ios_simulator_arm64"],
    deps = ["@kmp_maven//:org_jetbrains_kotlinx_kotlinx_coroutines_core"],
    deps_android = [...],                     # kotlin.test with JUnit 4
    deps_jvm = [...],
)
```

The macro links the test fragments of the iOS targets into `shared_test_ios_lib`, with
`<library>_native` as associate and the lists of the qualifiers covering each target (`srcs_ios`,
`deps_apple`), and calls `ios_test_rule(name = "shared_test_ios", deps = [":shared_test_ios_lib"] +
<the deps of ios>, ...)` with the other attributes of `ios` and those of every test. The test is
one of the `test_suite`. The XCTest case is `KotlinNativeTests_<package>_shared_test_ios_lib`, and
the test log has the names and the results of the Kotlin tests.

- **`ios`.** The attributes of `ios_test_rule` other than `name`: `minimum_os_version`, which is
  required, and e.g. `runner`, `env` or `linkopts`. Its `deps` are the other libraries the test
  bundle links, after the library of the Kotlin tests: targets with a `CcInfo`, e.g. the
  `objc_library` or the Swift package of an SDK that a klib of the tests refers to (see
  [Linking](#tests-in-the-ios-simulator)), as a list of labels that may be or end with a
  `select()`:

  ```starlark
  ios = dict(
      minimum_os_version = "16.0",
      linkopts = ["-ObjC"],  # the Objective-C categories of the SDK
      deps = ["@swiftpkg_firebase_ios_sdk//:FirebaseMessaging"],
  ),
  ```

  The deps of the Kotlin tests are `deps_ios` (or those of another qualifier), not `deps` of
  `ios`: a Kotlin library there is not a dep of their compilation. The macro sets
  `collect_code_coverage` to `False` unless `ios` sets it: the Kotlin tests are not instrumented,
  so `bazel coverage` passes a test of them alone in either coverage format (see
  [Coverage](#tests-in-the-ios-simulator)). A coverage build in the default format, gcov, fails
  to link a bundle with an `objc_library`, whatever the test collects: the library disables the
  feature `gcc_coverage_map_format`, or the build sets `--experimental_use_llvm_covmap`, with
  which a test that covers its `deps` sets `collect_code_coverage = True`.
- **`native`.** Its `opts`, `link_opts` and `module_name` are those of the compilation and the link
  of `shared_test_ios_lib` too; its other attributes, e.g. `data`, `args` or
  `target_compatible_with`, are of the `kt_native_test` alone, as the iOS test is no
  `kt_native_test`. When `platforms` lists no konan target other than those of iOS, the macro
  declares no native test, and such an attribute is an error instead of being dropped: the
  attributes of the iOS test are those of `ios`.
- **`ios_test_rule`.** rules_apple's `ios_unit_test`, or a macro that takes its `name`, `deps`,
  `minimum_os_version`, `collect_code_coverage` and the attributes of a test, e.g. one of the
  repository that sets a `runner`. The libraries of the bundle need no such macro: they are the
  `deps` of `ios`. Without iOS targets it is unused, so a wrapper of `kt_multiplatform_test` can
  always pass it.

The macro fails for the iOS tests when it is called, with the first of:

| Declaration                                                            | Message                                                                                                                                                              |
|------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `ios` sets attributes, and `platforms` lists no iOS target             | `ios sets attributes of the iOS test, but platforms lists no ios platform: add ios_arm64 or ios_simulator_arm64, or remove ios`                                      |
| `platforms` lists iOS targets, without `ios_test_rule`                 | `platforms lists ios_simulator_arm64, whose tests need ios_test_rule: pass the ios_unit_test of rules_apple, loaded from @rules_apple//apple:ios.bzl, or remove ios_simulator_arm64 from platforms` |
| `ios` is not set, or sets no `minimum_os_version`                      | `platforms lists ios_simulator_arm64, whose test needs a deployment target, which the macro has no default for: pass it as ios = dict(minimum_os_version = ...), e.g. "15.0"` |
| `ios` sets `associates`                                                | `ios sets associates, which the macro sets to the library of the platform`                                                                                           |
| The `deps` of `ios` are neither a list nor a `select()`                | `the deps of ios must be a list of labels, not a string: they are the other libraries that the test bundle links, e.g. an objc_library; the deps of the Kotlin tests are deps_ios of the macro` |
| `native` sets an attribute other than `opts`, `link_opts` and `module_name`, and the only konan targets of `platforms` are iOS targets | `native sets data, an attribute of the native test, but platforms lists no konan target other than those of iOS, whose tests take only the link_opts, module_name and opts of native: remove data from native, or add a konan target that has a native test, e.g. macos_arm64; the attributes of the iOS test are those of ios` |

**Platforms and flags.** Each test of the macro picks its platform itself, so `bazel test` needs no
platform flag:

| Test                  | Builds for                                                                                                                                                                  |
|-----------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `shared_test_jvm`     | The platform of the build, the host.                                                                                                                                        |
| `shared_test_android` | The platform of the build: a local test runs on the host, and selects the Android variants of its deps through [`//kotlin/settings:android`](#the-declared-targets).        |
| `shared_test_native`  | The platform of the build, when it is that of a listed konan target: the host. It runs on the exec host.                                                                    |
| `shared_test_ios`     | The iOS platform rules_apple picks for the test bundle: the first of `--ios_multi_cpus`, else that of `--cpu`, which is the arm64 simulator on an arm64 Mac and the x86_64 simulator elsewhere. It does not read `--platforms`. |

The iOS test itself is a target of the platform of the build, and only its test bundle, with the
library of the Kotlin tests, builds for iOS. So it is skipped, not failed, in two ways:

- on a host that does not build the listed iOS targets, e.g. Linux or an Intel Mac, the test is
  incompatible with the platform of the build: it is compatible with the platform of a host whose
  Kotlin/Native distribution compiles them, `macos_arm64`, and with their own platforms, for a
  build with `--platforms=@rules_kotlin//kotlin/native/platforms:ios_simulator_arm64`. An
  `ios_unit_test` without that compatibility fails the analysis of a build on Linux, where it
  finds no execution platform;
- where rules_apple picks an iOS platform that `platforms` does not list, the library is
  incompatible with it, and so is the test that depends on it: the x86_64 simulator, which is no
  konan target, with `--ios_multi_cpus=x86_64`, and the arm64 simulator when `platforms` lists
  `ios_arm64` alone, as a default build does not build for the device. List `ios_simulator_arm64`
  to run the tests in the simulator.

`bazel test //shared:shared_test_ios`, which names a skipped test, fails with the dependency chain
and the platform that made it incompatible. A `target_compatible_with` of the macro or of `ios`
follows the compatibility of the test, and is checked against the platform of the build, not
against the iOS platform. The limits of the test bundle are those of
[`kt_native_xctest_library`](#tests-in-the-ios-simulator): XCTest sees one test case, the Kotlin
test runner takes no filter, devices and test host apps are not supported, and a
`minimum_os_version` lower than the one Kotlin/Native compiles for links with warnings.

The other rules, `kt_jvm_binary`, `kt_native_binary` and `kt_native_framework`, and a test of a
single platform, a `kt_jvm_test`, a `kt_android_local_test` or a `kt_native_test`, compile only
their own `srcs`. They get the shared code from the library of their platform: they depend on
`//shared`, which is `shared_jvm` for a `kt_jvm_test` and `shared_native` for a `kt_native_test`,
and a framework exports it (see [The iOS app](#the-ios-app)). `examples/kmp` has both tests next to
its `kt_multiplatform_test`:

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
`srcs` of the macro and those of the groups and aliases above it as fragments.

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
  whose options (and `processor_options`) are passed on. The KSP command line separates options with
  `:` and a key from its value with `=`, without an escape, so the analysis fails on an option whose
  key or value has `:`, `=` or a line break, naming the option and where it comes from. The language
  and API versions, and the JVM target, are those of the Kotlin toolchain unless set on the rule.
- KSP runs in a JVM of the exec platform with a 2 GB heap (`-Xmx2g`), and its action uses the default
  shell environment.

This is a deliberate exception, not inline KSP: it is one KSP run per platform, which does not give the
processors the sources other compiler plugins generate. The compiler plugin still does not work with
the libraries of a `kt_multiplatform_library`, and no generated `.srcjar` is supported by them.
`examples/kmp` shows it with kotlin-inject 0.9.0 components in the `jvm`, `android` and `apple` sources.

### From Gradle to Bazel

| Gradle (the Kotlin Multiplatform plugin)                                                             | Bazel (rules_kotlin)                                                                                                                                             |
|------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `kotlin { androidTarget(); iosArm64(); iosSimulatorArm64(); jvm() }`                                 | `kt_multiplatform_library(platforms = ["android", "ios_arm64", "ios_simulator_arm64", "jvm"], ...)`                                                             |
| The `sourceSets` of the default hierarchy: `commonMain`, `iosMain`, `appleMain`, `nativeMain`, `jvmMain` | `srcs`, `srcs_ios`, `srcs_apple`, `srcs_native`, `srcs_jvm`, with a list per source set, e.g. `COMMON = glob(["src/commonMain/kotlin/**/*.kt"])`: the hierarchy makes the fragments and what they refine (see [Fragments](#fragments)) |
| A source set outside the default hierarchy, e.g. `nonAndroidMain`, and its `dependsOn`               | An alias of the platforms compiling it, e.g. `aliases = {"non_android": [...]}`, with its lists, `srcs_non_android` and `deps_non_android`: the fragment `non_android` |
| `commonMain.dependencies { implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2") }` | `kmp_maven.install(artifacts = [...])` in `MODULE.bazel`, and `"@kmp_maven//:org_jetbrains_kotlinx_kotlinx_coroutines_core"` in the `deps` of the macro; those of `iosMain.dependencies` in `deps_ios` |
| `binaries.framework { baseName = "Shared"; isStatic = true }`                                        | `kt_native_framework(name = "Shared", exports = ["//shared"], transitive_exports = False)`; a library of an `export(...)` in the block is one more label in `exports` |
| The Xcode build phase that embeds the framework (`embedAndSignAppleFrameworkForXcode`)               | `filegroup(output_group = "framework_files")`, `apple_static_framework_import` and `ios_application`; or a build phase of the Xcode project that runs `bazel build` (see [The iOS app](#the-ios-app)) |
| The `androidApp` module                                                                              | `kt_android_library` and `android_binary`, with `--android_platforms`                                                                                            |
| The Android SDK of `local.properties` (`sdk.dir`) or `ANDROID_HOME`                                  | `android.sdk` and `android.ndk` of `hermetic_android_toolchains` in `MODULE.bazel`, their licenses accepted with `--repo_env` in `.bazelrc`                      |
| The test source sets: `commonTest`, `jvmTest`, `nativeTest`, and `commonTest.dependencies { implementation(kotlin("test")) }` | `kt_multiplatform_test(library = "//shared", ...)` with `srcs`, `srcs_jvm`, `srcs_native`, and `kotlin-test`, `kotlin-test-junit` and JUnit in `deps_jvm`; the Kotlin/Native standard library has `kotlin.test` (see [Tests, binaries and frameworks](#tests-binaries-and-frameworks)) |
| `./gradlew :shared:allTests`                                                                         | `bazel test //shared:shared_test`, the `test_suite` of the macro: the tests of the platforms the host runs                                                      |
| `./gradlew :shared:jvmTest`                                                                          | `bazel test //shared:shared_test_jvm`; or a `kt_jvm_test` that depends on `//shared`                                                                             |
| `./gradlew :shared:macosArm64Test`, `:shared:linuxX64Test`                                           | `bazel test //shared:shared_test_native` on a host of that konan target; or a `kt_native_test` that depends on `//shared`                                        |
| `./gradlew :shared:iosSimulatorArm64Test`                                                            | `bazel test //shared:shared_test_ios` on an arm64 Mac, with `ios_simulator_arm64` in the `platforms` of the test and rules_apple's `ios_unit_test` as its `ios_test_rule` (see [iOS tests](#ios-tests)) |

### Limitations of the fragments

- The macro tells the sources of its lists apart by label. It resolves the labels in its package, so
  `"common/Greeting.kt"`, `":common/Greeting.kt"` and `"//shared:common/Greeting.kt"` are one source,
  which it reports in two lists (see [Checks](#checks)). It cannot see a file that a platform
  reaches through two labels, e.g. its path in the `srcs` of the macro and a `filegroup` containing
  it in `srcs_jvm`: the file lands in two fragments, and the analysis of the library of that
  platform fails with `the source <path> is in both fragment '<a>' and '<b>'`. List each file once,
  by one label.
- Aliases that share a platform without one being above the other, e.g. `android_jvm` and
  `jvm_linux`, are fragments that do not refine each other, and the compilation of the platform
  they share gets both: the `jvm` leaf refines both. An `expect` declaration above them with an
  `actual` in each gives the JVM two `actual`s, which the compiler rejects. The same holds for an
  alias and a group that share a platform.
- A library or a test of a single platform whose sources are all in one list, e.g. `srcs`,
  `srcs_native` or `srcs_jvm`, compiles them as the sources of that platform, without fragments:
  `<name>.fragments` prints its leaf alone. The restrictions of the libraries with fragments do not
  apply to it, so on the JVM and Android it can have `.srcjar` sources, kapt and the KSP compiler
  plugin (see [Limitations](#limitations)). Its sources cannot declare `expect` or `actual`, which
  the compiler reports as `'expect' and 'actual' declarations can be used only in multiplatform
  projects`. Sources in a second list, e.g. `srcs` and `srcs_jvm`, or a second platform make the
  lists fragments again, and bring the restrictions back: a target with a `.srcjar`, kapt or the KSP
  compiler plugin then fails with `kmp_fragments cannot be combined with ...`. The platforms of a
  test are its own, not those of its library.
- The lists of sources are plain lists: the macro derives the fragments when it is called, before any
  `select()` is resolved, and fails on a `select()` there. A source of some konan targets only goes
  in the srcs of their group or platform, e.g. `srcs_linux` or `srcs_ios_arm64`.
- The groups are those of the default hierarchy. An alias names a set of platforms beside them and
  takes `srcs`, `deps`, `exports` and `plugins`; the dicts of attributes are per library, not per
  group or alias.

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
registers their toolchains, so the host needs neither installed: the
[`MODULE.bazel` of `examples/kmp_app`](../examples/kmp_app/MODULE.bazel) declares `android.sdk` and
`android.ndk`, overrides the `@androidsdk` of rules_android and the `@androidndk` of
rules_android_ndk with them, and registers `@androidsdk//:all` and `@androidndk//:all`, as
`examples/android` does for the SDK.

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
select their JVM variants. A local test needs no such flag, e.g. `//shared:shared_test_android`
of the example: see [The declared targets](#the-declared-targets).

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

The app itself is a `kt_android_library` whose `deps` list `//shared` and the aliases of
`@kmp_maven`, and the `android_binary` of that library: see
[`androidApp/BUILD.bazel`](../examples/kmp_app/androidApp/BUILD.bazel).

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

The `.bazelrc` of the example sets the flag on macOS only (`build:macos`), where rules_apple has
iOS platforms to build for; the test bundle of `//shared:shared_test_ios` follows it too. Both
targets are in the `kotlin_native.targets(...)` of the example. The four targets between the
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

## Build settings and tags

The build settings of `@rules_kotlin//kotlin/settings` for Kotlin/Native, set on the command line or
in `.bazelrc` as `--@rules_kotlin//kotlin/settings:<name>=<value>`:

| Build setting                         | Default | Effect                                                                                                                                                                                                                 |
|---------------------------------------|---------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `experimental_native_build_tools_api` | `true`  | klib compilations run through the Kotlin Build Tools API; `false` runs the konanc command line. See [The Kotlin/Native Build Tools API](#the-kotlinnative-build-tools-api).                                           |
| `experimental_native_header_klibs`    | `false` | Each `kt_native_library` also writes a header klib, which the compilations of its dependents read instead of its klib. See [Kotlin/Native](../CompileAvoidance.md#kotlinnative) in the compilation avoidance docs.   |
| `kotlin_platform_type`                | `jvm`   | Not for the command line: the Kotlin/Native rules set it to `native` for themselves and their deps, and aliases select on it. See [The Kotlin platform type](kmp_dependencies.md#the-kotlin-platform-type).           |

`@rules_kotlin//kotlin/settings:android` is no build setting but a condition for a `select()`: it
matches the JVM and Android rules on an Android platform and below an Android local test. See
[The declared targets](#the-declared-targets).

The tag `kt_native_header_klib_incompatible` on a `kt_native_library` turns the header klib off for
that library: its dependents compile against its klib.

## Limitations

- Linux x86_64 and macOS arm64 exec hosts only, and the five konan targets above: see
  [Status and prerequisites](#status-and-prerequisites). `ios_x64` has its place in the hierarchy of
  `kt_multiplatform_library`, but the macro rejects it in `platforms`.
- No cinterop rule yet: the code cannot bind a C or Objective-C library of its own. The platform
  libraries of the distribution are available, and the cinterop klibs of a Maven library are imported
  with it.
- No Kotlin/JS or Kotlin/Wasm platform: the platforms of `kt_multiplatform_library` are `jvm`,
  `android` and the konan targets, and `kmp_maven` leaves the `wasmjs` variants out.
- Static frameworks only: no dynamic framework and no XCFramework. A framework is for one konan
  target, which the platform of the app selects.
- `bazel test` runs a `kt_native_test` for the konan target of the exec host only (`linux_x64` or
  `macos_arm64`). For another target the test runner links, but nothing runs it: not the iOS
  simulator, nor an emulator. A `kt_native_xctest_library` runs the tests of an iOS target, in the
  simulator, through rules_apple's `ios_unit_test`, and `kt_multiplatform_test` declares both for
  its iOS targets. Only iOS has such a test: no `macos_unit_test`, tvOS or watchOS.
- XCTest reports one test case for a `kt_native_xctest_library`, not its Kotlin tests, whose test
  runner takes no options. It was run in the iOS simulator of an arm64 Mac only. In a coverage
  build its test needs `--experimental_use_llvm_covmap` or `collect_code_coverage = False`, which
  `kt_multiplatform_test` sets: see [Tests in the iOS simulator](#tests-in-the-ios-simulator).
- A `kt_multiplatform_test` lists its own deps: it gets the library of each platform and what that
  library exports, not its other deps. It takes no `resources` or options per group or alias, only
  the dicts of `jvm`, `android` and `native`, and no KSP of its test sources. Its native test is a
  `kt_native_test`, with the limit above: nothing runs it in the iOS simulator (see
  [Tests, binaries and frameworks](#tests-binaries-and-frameworks)).
- On Bazel 7 and 8, a tool of an Android local test that is not a `kt_compiler_plugin`, a
  `kt_plugin_cfg` or a `kt_ksp_plugin`, e.g. a `java_plugin` annotation processor or a tool of a
  `genrule` among its deps, gets the Android variants of the aliases in its own deps, and such a
  tool of a Kotlin/Native target gets the klibs: those Bazel versions keep the host hybrid mode and
  the Kotlin platform type in the exec configuration, and only the three rules of rules_kotlin
  reset them. Bazel 9 resets both for every tool. Give such a tool the JVM variant by its own label,
  e.g. `//shared:shared_jvm` or `@kmp_maven//:<lib>.jvm`.
- konanc, not the analysis, finds two klibs with the same `unique_name` among the deps of a target
  (see [Options, data and inputs](#options-data-and-inputs)).
- `bazel coverage` instruments the Kotlin code compiled for the JVM and Android, the sources of
  their fragments included; the Kotlin/Native rules do not instrument theirs. A
  `kt_android_local_test` has the coverage provider of rules_android, which does not know
  `kmp_fragments`: its instrumented files are those of the libraries it tests, and not the sources
  of its own test fragments. An `ios_application` does not link the profile runtime of
  instrumented Swift code, so `examples/kmp_app` leaves its Swift app out of
  `--instrumentation_filter`.
- The JVM and Android libraries of a `kt_multiplatform_library`, and the JVM and Android tests of a
  `kt_multiplatform_test`, that compile fragments cannot have `.srcjar` sources, kapt or the KSP
  compiler plugin. Those of a single platform with sources in one list compile no fragment and can
  (see [Limitations of the fragments](#limitations-of-the-fragments)).
  [KSP for a multiplatform library](#ksp-for-a-multiplatform-library) is a separate action with
  declared plain `.kt` outputs, which the libraries compile. KSP of a native target is that action
  too; there is no inline KSP plugin for Kotlin/Native. Generated Java sources, classes and
  resources of that action are not supported.
- The fragments follow from the lists of the groups, the aliases and the platforms, with limits of
  their own: see [Limitations of the fragments](#limitations-of-the-fragments).
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
| [`examples/native`](../examples/native)   | klibs for the host and for every konan target, an executable run end to end, tests, one of them reading a file of its `data`, Linux executables linked for both Linux targets, and a framework and its `framework_files` per Apple target. | Linux x86_64 and macOS arm64, the Apple targets on macOS only.             |
| [`examples/kmp`](../examples/kmp)         | A `kt_multiplatform_library` for the JVM, Android, the Apple and the Linux targets, with sources of the groups `apple` and `linux` and Gradle's `nonAndroidMain` as the alias `non_android`; a `kt_multiplatform_test` whose common test runs on the JVM, as an Android local test and on the konan target of the host, JVM and native tests that depend on `//shared`, `kotlinx-coroutines-core` from `kmp_maven`, and kotlin-inject components generated by KSP for the JVM, Android and Apple sources. | Linux x86_64 and macOS arm64, the Apple klibs on macOS only; Bazel 8.4.2 or newer. |
| [`examples/kmp_app`](../examples/kmp_app) | An Android app and an iOS app that share one `kt_multiplatform_library`, laid out like the project of the Kotlin Multiplatform wizard, and a `kt_multiplatform_test` that runs its common tests on the JVM, as an Android local test and, through rules_apple's `ios_unit_test`, in the iOS simulator. | macOS arm64 builds both apps and runs every test, Linux x86_64 builds the Android app and runs the JVM and Android tests; Bazel 8.4.2 or newer. |

Each builds and tests with `bazel build //...` and `bazel test //...` in its directory.

`examples/native` also has two manual checks, which no Bazel test runs:

- `./repro_check.sh` builds two copies of the example, in directories whose paths differ, and
  compares their klibs, executables and frameworks byte for byte: the outputs do not depend on the
  path of the checkout.
- `./e2e_linux_docker.sh` runs the `linux_x64` `//:hello` in a container without a JRE; it needs
  Docker.
