package io.bazel.kotlin.integration

import io.bazel.kotlin.test.BazelIntegrationTestBase
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.charset.StandardCharsets.UTF_8
import kotlin.io.path.createDirectories
import kotlin.io.path.writeText

/**
 * Runs Kotlin/Native tests in the iOS simulator: a `kt_native_xctest_library` in the `deps` of
 * rules_apple's `ios_unit_test`, with no `--platforms` and no `--ios_multi_cpus`, so the test picks
 * the simulator of the host. A passing Kotlin test passes the test, a failing assertion fails it
 * with the name of the Kotlin test in the log, and the tests see an `internal` declaration of
 * their associate. One test bundle runs the tests of two libraries, which have the same name in two
 * packages: the test case of the one passes and that of the other fails.
 *
 * A `kt_multiplatform_test` of the JVM and of the iOS simulator, with `ios_unit_test` as its
 * `ios_test_rule`, runs both tests through its `test_suite`, with no platform flag. With
 * `--ios_multi_cpus=x86_64`, the simulator rules_apple picks on a Linux or an Intel host, which is
 * no konan target, the iOS test is skipped and the suite still passes. `bazel coverage` of the
 * suite, which instruments the package of the tests, links the test bundle and passes both tests.
 */
class NativeXctestTest : BazelIntegrationTestBase() {
  @Test
  fun kotlinTestsRunInTheSimulator() {
    val release = unpackRelease(env("RULES_KOTLIN_RELEASE"))
    val workspace = root.resolve("workspace").createDirectories()

    // A persistent repository cache keeps the Kotlin/Native distribution.
    val repositoryCache = System.getenv("RULES_KOTLIN_REPOSITORY_CACHE")

    workspace.resolve("MODULE.bazel").writeText(
      """
      module(name = "native_xctest")
      bazel_dep(name = "rules_kotlin", version = "2.2.0")
      bazel_dep(name = "rules_apple", version = "5.4.0")
      bazel_dep(name = "platforms", version = "1.0.0")
      kotlin_native = use_extension("@rules_kotlin//src/main/starlark/core/repositories:native.bzl", "kotlin_native")
      kotlin_native.targets(targets = ["ios_simulator_arm64"])
      """.trimIndent(),
    )
    workspace.resolve("BUILD.bazel").writeText(
      """
      load("@rules_apple//apple:ios.bzl", "ios_unit_test")
      load("@rules_kotlin//kotlin:native.bzl", "kt_native_library")

      kt_native_library(
          name = "greeter",
          srcs = ["Greeter.kt"],
          visibility = ["//:__subpackages__"],
      )

      ios_unit_test(
          name = "passing",
          minimum_os_version = "15.0",
          deps = ["//passing:tests"],
      )

      ios_unit_test(
          name = "failing",
          minimum_os_version = "15.0",
          deps = ["//failing:tests"],
      )

      ios_unit_test(
          name = "both",
          minimum_os_version = "15.0",
          deps = [
              "//failing:tests",
              "//passing:tests",
          ],
      )
      """.trimIndent(),
    )

    // The libraries have the same name, in two packages. decorate is internal to greeter.
    for ((pkg, source) in mapOf("passing" to "PassingTest.kt", "failing" to "FailingTest.kt")) {
      workspace.resolve(pkg).createDirectories().resolve("BUILD.bazel").writeText(
        """
        load("@rules_kotlin//kotlin:native.bzl", "kt_native_xctest_library")

        kt_native_xctest_library(
            name = "tests",
            testonly = True,
            srcs = ["$source"],
            associates = ["//:greeter"],
            target_compatible_with = ["@platforms//os:ios"],
            visibility = ["//:__pkg__"],
        )
        """.trimIndent(),
      )
    }
    // The common test calls an internal declaration of the library, on the JVM and on iOS. The
    // JVM test compiles against the JUnit 4 of the test runner of Bazel, which it runs with.
    val shared = workspace.resolve("shared").createDirectories()
    shared.resolve("BUILD.bazel").writeText(
      """
      load("@rules_apple//apple:ios.bzl", "ios_unit_test")
      load("@rules_kotlin//kotlin:jvm.bzl", "kt_jvm_import")
      load("@rules_kotlin//kotlin:kmp.bzl", "kt_multiplatform_library", "kt_multiplatform_test")

      kt_multiplatform_library(
          name = "shared",
          srcs = ["Greeting.kt"],
          platforms = [
              "jvm",
              "ios_simulator_arm64",
          ],
          srcs_ios = ["Platform.ios.kt"],
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
          ios = dict(minimum_os_version = "15.0"),
          ios_test_rule = ios_unit_test,
          library = ":shared",
          platforms = [
              "jvm",
              "ios_simulator_arm64",
          ],
          deps_jvm = [
              ":junit",
              "@rules_kotlin//kotlin/compiler:kotlin-test",
              "@rules_kotlin//kotlin/compiler:kotlin-test-junit",
          ],
      )
      """.trimIndent(),
    )
    shared.resolve("Greeting.kt").writeText(
      """
      package shared

      expect fun platform(): String

      fun greeting(): String = "Hello from " + decorate(platform()) + "!"

      internal fun decorate(name: String): String = name.uppercase()
      """.trimIndent(),
    )
    for (platform in listOf("ios", "jvm")) {
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
              assertEquals("Hello from " + platform().uppercase() + "!", greeting())
          }

          @Test
          fun decorates() {
              assertEquals("SHARED", decorate("shared"))
          }
      }
      """.trimIndent(),
    )
    workspace.resolve("Greeter.kt").writeText(
      """
      package greeter

      fun greet(name: String): String = "Hello, " + decorate(name) + "!"

      internal fun decorate(name: String): String = name.uppercase()
      """.trimIndent(),
    )
    workspace.resolve("passing/PassingTest.kt").writeText(
      """
      package greeter

      import kotlin.test.Test
      import kotlin.test.assertEquals

      class PassingTest {
          @Test
          fun greets() {
              assertEquals("Hello, NATIVE!", greet("native"))
          }

          @Test
          fun decorates() {
              assertEquals("NATIVE", decorate("native"))
          }
      }
      """.trimIndent(),
    )
    workspace.resolve("failing/FailingTest.kt").writeText(
      """
      package greeter

      import kotlin.test.Test
      import kotlin.test.assertEquals

      class FailingTest {
          @Test
          fun greetsWrongly() {
              assertEquals("Hello, native!", greet("native"))
          }
      }
      """.trimIndent(),
    )

    fun bazelTest(
      vararg targets: String,
      command: String = "test",
    ): Result<ProcessResult> =
      bazel.run(
        workspace,
        "--batch",
        "--ignore_all_rc_files",
        "--host_jvm_args=-Djava.net.preferIPv6Addresses=system",
        "--output_user_root=${root.resolve("bazel")}",
        "--output_base=${root.resolve("output")}",
        command,
        "--jobs=2",
        "--noshow_progress",
        "--color=no",
        "--override_module=rules_kotlin=$release",
        // The KonanLauncher runs on Java 17 or later, as in examples/native.
        "--java_runtime_version=remotejdk_21",
        "--tool_java_runtime_version=remotejdk_21",
        *listOfNotNull(repositoryCache?.let { "--repository_cache=$it" }).toTypedArray(),
        "--test_output=all",
        *targets,
      )

    // What XCTest logs for the test case of a library, and the Kotlin test runner for its tests.
    val passed =
      listOf("Test Case '-[KotlinNativeTests_passing_tests testKotlin]' passed (") +
        listOf("greets", "decorates").map { "[       OK ] greeter.PassingTest.$it" }
    val failed =
      listOf(
        "Test Case '-[KotlinNativeTests_failing_tests testKotlin]' failed (",
        "[  FAILED  ] greeter.FailingTest.greetsWrongly",
      )

    fun assertLogs(
      target: String,
      log: String,
      lines: List<String>,
    ) {
      for (line in lines) {
        assertTrue("$target should log $line: $log", line in log)
      }
    }

    assertLogs("//:passing", bazelTest("//:passing").getOrThrow().stdOut.toString(UTF_8), passed)

    // 3 is the exit code of a build that succeeded with a failing test: a build error, such as the
    // duplicate symbols of two libraries, exits with 1.
    fun failureOf(target: String): String {
      val failure = bazelTest(target).exceptionOrNull()?.message
      assertNotNull("$target should fail", failure)
      assertTrue("$target should exit with 3: $failure", " exited 3:" in failure!!)
      assertLogs(target, failure, failed)
      return failure
    }
    failureOf("//:failing")

    // The bundle links both libraries, and the test case of each runs its own tests: the one of the
    // failing library fails, the other still passes.
    assertLogs("//:both", failureOf("//:both"), passed)

    // The test_suite of the macro runs the JVM test and, in the simulator, the iOS test, whose
    // test case is named after the library of the Kotlin tests the macro declares.
    fun suite(
      vararg flags: String,
      command: String = "test",
    ): String {
      val result = bazelTest(*flags, "//shared:shared_test", command = command).getOrThrow()
      return result.stdOut.toString(UTF_8) + result.stdErr.toString(UTF_8)
    }

    fun assertResult(
      log: String,
      test: String,
      result: String,
    ) {
      val line = Regex("""(?m)^${Regex.escape(test)}\s+(\(cached\) )?$result\b""")
      assertTrue("$test should be $result: $log", line in log)
    }
    val ran = suite()
    assertLogs(
      "//shared:shared_test",
      ran,
      listOf("Test Case '-[KotlinNativeTests_shared_shared_test_ios_lib testKotlin]' passed (") +
        listOf("greets", "decorates").map { "[       OK ] shared.GreetingTest.$it" },
    )
    assertResult(ran, "//shared:shared_test_ios", "PASSED")
    assertResult(ran, "//shared:shared_test_jvm", "PASSED")

    // The test bundle builds for the x86_64 simulator, which the library of the Kotlin tests is
    // incompatible with: the build skips the iOS test, and does not fail.
    val skipped = suite("--ios_multi_cpus=x86_64")
    assertResult(skipped, "//shared:shared_test_ios", "SKIPPED")
    assertResult(skipped, "//shared:shared_test_jvm", "PASSED")

    // A coverage build instruments what the C++ toolchain compiles, but not the XCTest case of
    // the library: the test bundle links no profile runtime. The iOS test of the macro collects
    // no coverage, so its runner does not fail it for the profile its process did not write.
    val covered = suite(command = "coverage")
    assertResult(covered, "//shared:shared_test_ios", "PASSED")
    assertResult(covered, "//shared:shared_test_jvm", "PASSED")
  }
}
