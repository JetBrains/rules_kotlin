# Kotlin Multiplatform app

Experimental. An Android app and an iOS app that share Kotlin code, laid out like the project of the
Kotlin Multiplatform wizard, with each module a Bazel package. The guide is
[docs/kmp.md](../../docs/kmp.md).

| Package        | Gradle counterpart         | Content                                                                                                                                                                                                                                                                                                              |
|----------------|----------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `//shared`     | The `shared` module        | `kt_multiplatform_library(name = "shared")`: the common code of `src/commonMain/kotlin` (`interface Platform`, `expect fun getPlatform()`, and `Greeting`, with `greet()` and the `suspend` `greetLater()` of kotlinx.coroutines) and its `actual`s in `src/androidMain`, `src/iosMain` (`UIDevice`) and `src/jvmMain`. `kt_multiplatform_test(name = "shared_test")` compiles `src/commonTest/kotlin` with `src/jvmTest`, `src/androidUnitTest` and `src/iosTest` across `shared_test_jvm`, the Android local test `shared_test_android` and, with rules_apple's `ios_unit_test` as `ios_test_rule`, `shared_test_ios` in the iOS simulator. |
| `//androidApp` | The `androidApp` module    | The `kt_android_library` `lib`, whose `MainActivity` shows `Greeting().greet()`, then `greetLater()` from a coroutine, and the `android_binary` `androidApp`. `apk_test` checks the APK and its deploy jar: the Android `actual` of `//shared` and kotlinx.coroutines are in it, the JVM `actual` is not.                 |
| `//iosApp`     | The `iosApp` Xcode project | The `kt_native_framework` `Shared`, which exports `//shared`; the `filegroup` `Shared_files` of its `framework_files`; the `apple_static_framework_import` `Shared_import`; the `swift_library` `iosApp_lib`, a SwiftUI view that calls `Greeting().greet()` and `try await Greeting().greetLater()`; and the `ios_application` `iosApp`. `ipa_test` checks that the binary of the IPA is an arm64 iOS simulator one with the Kotlin class `SharedGreeting`, and the bundle id. |

## Building and testing

On a macOS arm64 host with Xcode, both apps build:

```shell
bazel build //...
bazel test //...
```

`bazel test //...` runs the three tests of `//shared:shared_test`, `//androidApp:apk_test` and
`//iosApp:ipa_test`, with no platform flag:

| Test                           | Runs                                                                                                                                         |
|--------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------|
| `//shared:shared_test_jvm`     | On the JVM of the host, with `commonTest` + `jvmTest`, the JVM `actual`, classpath `resources`, rule `env` and the JVM variant of kotlinx.coroutines. |
| `//shared:shared_test_android` | On the JVM of the host, as a local test, with `commonTest` + `androidUnitTest`, the Android `actual` and kotlinx.coroutines against the SDK `android.jar` (note: `kt_android_local_test` does not propagate rule `env`). |
| `//shared:shared_test_ios`     | In the iOS simulator, in the `.xctest` bundle of `ios_unit_test`, with `commonTest` + `iosTest`, bundle `resources` (`NSBundle`), simulator `env` (`NSProcessInfo`), the iOS `actual` and the klib of kotlinx.coroutines. |

`bazel test //shared:shared_test` runs those three alone. `bazel coverage //...` instruments the
Kotlin code of `//shared` and `//androidApp` that runs on the JVM
(`coverage --instrumentation_filter` in `.bazelrc`), not the Kotlin/Native code of the iOS test, nor
the Swift code of the iOS app: `ios_application` does not link the profile runtime that
instrumented Swift code needs.

On a Linux x86_64 host, `.bazelrc` deletes the `iosApp` package
(`common:linux --deleted_packages=iosApp`), and `shared_test_ios` is incompatible with the host, so
the same commands build the Android app and run `shared_test_jvm`, `shared_test_android` and
`apk_test`.

Bazel downloads the Android SDK and NDK, the JDK and the Kotlin/Native distribution: no local SDK or
NDK is needed. The actions run without network access (`--sandbox_default_allow_network=false`).

The example needs Bazel 8.4.2 or newer (`exclude/7.x`): `hermetic_android_toolchains` requires it,
and rules_apple 5.x dropped Bazel 7. Windows has no Kotlin/Native toolchain.

## Running the apps

- iOS: `bazel run //iosApp` builds the app for the simulator and launches it there.
- Android: `bazel build //androidApp`, then `adb install bazel-bin/androidApp/androidApp.apk` on a
  device or an emulator; or `bazel mobile-install //androidApp` (`--adb=<path>` when adb is not on
  the PATH), which installs incrementally.

## How it fits together

- [The Android app](../../docs/kmp.md#the-android-app): the Android SDK and NDK of
  `hermetic_android_toolchains` and their licenses, and `--android_platforms=@@//:android_arm64`,
  which makes `//shared` and the alias of kotlinx.coroutines resolve to their Android variants.
- [The iOS app](../../docs/kmp.md#the-ios-app): the framework follows the iOS platform of
  `--ios_multi_cpus` (`sim_arm64` in `.bazelrc`, on macOS; `arm64` is a device build, which needs
  a provisioning profile), and the targets between it and the app are compatible with iOS only, so
  `bazel build //...` skips them in the host configuration.
- [The tests](../../docs/kmp.md#ios-tests): each test of `shared_test` picks its platform itself.
  The local test selects the Android variants on the host platform, and the test bundle of the iOS
  test builds for the simulator of `--ios_multi_cpus`. The device target `ios_arm64` of `//shared`
  is not a platform of the test: a test bundle for a device needs signing.
- `kotlin_native.targets(...)` in `MODULE.bazel` stages the link dependencies of `ios_arm64` and
  `ios_simulator_arm64` only.
- `kmp_manifest.json` pins kotlinx-coroutines-core 1.10.2 for every platform. After changing
  `kmp_maven.install`, pin it again with `bazel run @kmp_maven//pin` and commit it (see
  [Pinning the manifest](../../docs/kmp_dependencies.md#pinning-the-manifest)).
