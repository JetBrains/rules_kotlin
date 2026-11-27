# Examples

These are series of code samples useful for configuring a variety of use cases. They also serve as integration tests.

## Kotlin/Native and Kotlin Multiplatform (experimental)
See [docs/kmp.md](../docs/kmp.md#examples). Kotlin/Native builds on Linux x86_64 and macOS arm64 hosts only, so these examples are skipped on Windows.
- [native](native): the Kotlin/Native rules: klibs for every konan target, an executable, tests, Linux cross links and Apple frameworks.
- [kmp](kmp): a `kt_multiplatform_library` for the JVM, Android, the Apple and the Linux targets, with `kt_multiplatform_test` suites (including Robolectric on Android and `kotlinx-coroutines-test`), JVM and native tests, KSP and `kmp_maven` dependencies. Bazel 8.4.2 or newer.
- [kmp_app](kmp_app): an Android app and an iOS app sharing one `kt_multiplatform_library`, whose `kt_multiplatform_test` runs on the JVM, as an Android local test and in the iOS simulator. macOS arm64 builds both apps and runs every test, Linux x86_64 builds the Android app and runs the JVM and Android tests; Bazel 8.4.2 or newer.

## Adding a new integration test
1. Create a new workspace in the `examples` directory
1. Ensure that the `rules_kotlin` repository is named `rules_kotlin`
1. If the example will not work on a bazel version, add an `exclude` directory with a file of that version. See examples/multiplex/exclude.
1. Update the bazel excluded packages via `bazel run @rules_bazel_integration_test//tools:update_deleted_packages`
