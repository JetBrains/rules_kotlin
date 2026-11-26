package io.bazel.kotlin.integration

import io.bazel.kotlin.test.BazelIntegrationTestBase
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.charset.StandardCharsets.UTF_8
import kotlin.io.path.createDirectories
import kotlin.io.path.writeText

/**
 * Analyses the Android local test of a `kt_multiplatform_test` for coverage, on Bazel 8.
 *
 * Bazel 8 registers the baseline coverage action of a target in every call of
 * `coverage_common.instrumented_files_info`. rules_android makes the call whose provider
 * `kt_android_local_test` returns: a second call of the Kotlin compilation, over the sources of
 * the `kmp_fragments` too, was a conflict of two actions that write `baseline_coverage.dat`, which
 * failed the analysis of the test in a coverage build.
 *
 * The test still instruments the library it tests: the instrumented files of the local test are
 * the sources of the Android library, common ones included, and not those of the JVM library.
 */
class AndroidLocalTestCoverageTest : BazelIntegrationTestBase() {
  @Test
  fun localTestOfFragmentsAnalysesForCoverage() {
    val release = unpackRelease(env("RULES_KOTLIN_RELEASE"))
    val workspace = root.resolve("workspace").createDirectories()

    // A persistent repository cache keeps the Android SDK.
    val repositoryCache = System.getenv("RULES_KOTLIN_REPOSITORY_CACHE")

    // The Android SDK and the mirror of Maven Central are those of examples/kmp.
    workspace.resolve("MODULE.bazel").writeText(
      """
      module(name = "android_local_test_coverage")
      bazel_dep(name = "rules_kotlin", version = "2.2.0")
      bazel_dep(name = "rules_android", version = "0.8.1")
      bazel_dep(name = "rules_jvm_external", version = "7.1")
      bazel_dep(name = "hermetic_android_toolchains", version = "0.5.0", dev_dependency = True)

      android = use_extension("@hermetic_android_toolchains//:extensions.bzl", "android", dev_dependency = True)
      android.sdk(
          build_tools_version = "35.0.0",
          version = "35",
      )
      use_repo(android, "androidsdk")

      android_sdk_repository_extension = use_extension(
          "@rules_android//rules/android_sdk_repository:rule.bzl",
          "android_sdk_repository_extension",
          dev_dependency = True,
      )
      override_repo(android_sdk_repository_extension, "androidsdk")
      register_toolchains("@androidsdk//:all", dev_dependency = True)

      maven = use_extension("@rules_jvm_external//:extensions.bzl", "maven")
      maven.install(
          name = "rules_android_maven",
          aar_import_bzl_label = "@rules_android//rules:rules.bzl",
          known_contributing_modules = ["rules_android"],
          repositories = [
              "https://maven-central.storage-download.googleapis.com/maven2",
              "https://maven.google.com",
              "https://repo1.maven.org/maven2",
          ],
          use_starlark_android_rules = True,
      )
      """.trimIndent(),
    )
    workspace.resolve("BUILD.bazel").writeText("")

    val shared = workspace.resolve("shared").createDirectories()
    shared.resolve("BUILD.bazel").writeText(
      """
      load("@rules_kotlin//kotlin:jvm.bzl", "kt_jvm_import")
      load("@rules_kotlin//kotlin:kmp.bzl", "kt_multiplatform_library", "kt_multiplatform_test")

      kt_multiplatform_library(
          name = "shared",
          srcs = ["Greeting.kt"],
          android = dict(
              custom_package = "shared",
              manifest = "AndroidManifest.xml",
          ),
          platforms = [
              "jvm",
              "android",
          ],
          srcs_android = ["Platform.android.kt"],
          srcs_jvm = ["Platform.jvm.kt"],
      )

      kt_jvm_import(
          name = "junit",
          jars = ["@bazel_tools//tools/jdk:TestRunner_deploy.jar"],
          neverlink = True,
      )

      kt_multiplatform_test(
          name = "shared_test",
          srcs = ["GreetingTest.kt"],
          library = ":shared",
          platforms = ["android"],
          deps = [
              ":junit",
              "@rules_kotlin//kotlin/compiler:kotlin-test",
              "@rules_kotlin//kotlin/compiler:kotlin-test-junit",
          ],
      )
      """.trimIndent(),
    )
    shared.resolve("AndroidManifest.xml").writeText(
      """
      <?xml version="1.0" encoding="utf-8"?>
      <manifest xmlns:android="http://schemas.android.com/apk/res/android" package="shared">
          <uses-sdk android:minSdkVersion="23" />
      </manifest>
      """.trimIndent(),
    )
    shared.resolve("Greeting.kt").writeText(
      """
      package shared

      expect fun platform(): String

      fun greeting(): String = "Hello from " + platform() + "!"
      """.trimIndent(),
    )
    for (platform in listOf("android", "jvm")) {
      shared.resolve("Platform.$platform.kt").writeText(
        """
        package shared

        actual fun platform(): String = "$platform"
        """.trimIndent(),
      )
    }
    shared.resolve("GreetingTest.kt").writeText(
      """
      package shared

      import kotlin.test.Test
      import kotlin.test.assertEquals

      class GreetingTest {
          @Test
          fun greets() {
              assertEquals("Hello from android!", greeting())
          }
      }
      """.trimIndent(),
    )
    // Analysis only: the conflict of the actions fails the analysis of the test, and the query
    // prints the files its coverage provider instruments.
    val instrumented =
      bazel
        .run(
          workspace,
          "--batch",
          "--ignore_all_rc_files",
          "--host_jvm_args=-Djava.net.preferIPv6Addresses=system",
          "--output_user_root=${root.resolve("bazel")}",
          "--output_base=${root.resolve("output")}",
          "cquery",
          "--noshow_progress",
          "--color=no",
          "--override_module=rules_kotlin=$release",
          "--java_runtime_version=remotejdk_21",
          "--tool_java_runtime_version=remotejdk_21",
          // As in examples/kmp: the Android build tools use Java 17 language features.
          "--tool_java_language_version=17",
          "--repo_env=ACCEPTED_ANDROID_SDK_LICENSE_VERSION=35",
          *listOfNotNull(repositoryCache?.let { "--repository_cache=$it" }).toTypedArray(),
          "--collect_code_coverage",
          "--instrumentation_filter=^//shared[/:]",
          "--output=starlark",
          "--starlark:expr=\"\\n\".join([file.path for file in " +
            "providers(target)[\"InstrumentedFilesInfo\"].instrumented_files.to_list()])",
          "//shared:shared_test_android",
        ).getOrThrow()
        .stdOut
        .toString(UTF_8)
        .lines()

    for (source in listOf("shared/Greeting.kt", "shared/Platform.android.kt")) {
      assertTrue("the local test should instrument $source: $instrumented", source in instrumented)
    }
    assertFalse(
      "the local test should not instrument the JVM library: $instrumented",
      "shared/Platform.jvm.kt" in instrumented,
    )
  }
}
