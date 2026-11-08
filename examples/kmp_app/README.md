# Kotlin Multiplatform app

Experimental. An Android app and an iOS app that share Kotlin code, laid out like the project of the
Kotlin Multiplatform wizard, with each module a Bazel package. The guide is
[docs/kmp.md](../../docs/kmp.md).

| Package        | Gradle counterpart         | Content                                                                                                                                                                                                                                                                                                              |
|----------------|----------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `//shared`     | The `shared` module        | `kt_multiplatform_library(name = "shared")`: the common code of `src/commonMain/kotlin` (`interface Platform`, `expect fun getPlatform()`, and `Greeting`, with `greet()` and the `suspend` `greetLater()` of kotlinx.coroutines) and its `actual`s in `src/androidMain`, `src/iosMain` (`UIDevice`) and `src/jvmMain`. `GreetingTest`, a `kt_jvm_test` of `src/commonTest/kotlin`, runs the common code on the JVM of the host. |
| `//androidApp` | The `androidApp` module    | The `kt_android_library` `lib`, whose `MainActivity` shows `Greeting().greet()`, then `greetLater()` from a coroutine, and the `android_binary` `androidApp`. `apk_test` checks the APK and its deploy jar: the Android `actual` of `//shared` and kotlinx.coroutines are in it, the JVM `actual` is not.                 |
| `//iosApp`     | The `iosApp` Xcode project | The `kt_native_framework` `Shared`, which exports `//shared`; the `filegroup` `Shared_files` of its `framework_files`; the `apple_static_framework_import` `Shared_import`; the `swift_library` `iosApp_lib`, a SwiftUI view that calls `Greeting().greet()` and `try await Greeting().greetLater()`; and the `ios_application` `iosApp`. `ipa_test` checks that the binary of the IPA is an arm64 iOS simulator one with the Kotlin class `SharedGreeting`, and the bundle id. |

## Building and testing

On a macOS arm64 host with Xcode, both apps build:

```shell
bazel build //...
bazel test //...
```

`bazel test //...` runs `//shared:GreetingTest`, `//androidApp:apk_test` and `//iosApp:ipa_test`.
`bazel coverage //...` instruments the Kotlin code of `//shared` and `//androidApp`
(`coverage --instrumentation_filter` in `.bazelrc`), not the Swift code of the iOS app:
`ios_application` does not link the profile runtime that instrumented Swift code needs.

On a Linux x86_64 host, `.bazelrc` deletes the `iosApp` package
(`common:linux --deleted_packages=iosApp`), so the same commands build the Android app and run
`GreetingTest` and `apk_test`.

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

- `MODULE.bazel` gets the Android SDK (35, build tools 35.0.0) and the NDK r29 from
  `hermetic_android_toolchains` and registers their toolchains: `android_binary` needs the NDK's C++
  toolchain for the Android platform even without native code. `.bazelrc` accepts their licenses with
  `--repo_env=ACCEPTED_ANDROID_SDK_LICENSE_VERSION=35` and `--repo_env=ACCEPTED_ANDROID_NDK_LICENSE_VERSION=r29`.
- `--android_platforms=@@//:android_arm64` (`.bazelrc`, the platform is in `BUILD.bazel`) makes
  `android_binary` build its deps for Android, so `//shared` and the alias of kotlinx.coroutines
  resolve to their Android variants. The label is canonical: on Bazel 9, rules_android makes
  `--android_platforms` an alias of its own flag, which would read `//:android_arm64` in its repository.
- `ios_application` builds its deps for the iOS platform of `--ios_multi_cpus`, and the framework
  follows it: `sim_arm64`, the value of `.bazelrc`, links it for `ios_simulator_arm64`, and
  `--ios_multi_cpus=arm64` for `ios_arm64`: a device build, which needs a provisioning profile.
- The four targets between the framework and the app are
  `target_compatible_with = ["@platforms//os:ios"]`: `bazel build //...` skips them in the host
  configuration and builds them in the configuration of the app. The framework alone builds with
  `bazel build //iosApp:Shared --platforms=@rules_kotlin//kotlin/native/platforms:ios_simulator_arm64`.
- `kotlin_native.targets(...)` in `MODULE.bazel` stages the link dependencies of `ios_arm64` and
  `ios_simulator_arm64` only.
- `kmp_manifest.json` pins kotlinx-coroutines-core 1.10.2 for every platform; it is the manifest of
  `examples/kmp`. After changing `kmp_maven.install`, pin it again with `bazel run @kmp_maven//pin`
  and commit it (see [Pinning the manifest](../../docs/kmp_dependencies.md#pinning-the-manifest)):
  until then, the targets of `@kmp_maven` fail with that command.
