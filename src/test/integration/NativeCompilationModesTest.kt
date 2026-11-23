package io.bazel.kotlin.integration

import io.bazel.kotlin.test.BazelIntegrationTestBase
import org.junit.Assert.assertEquals
import org.junit.Test
import java.nio.charset.StandardCharsets.UTF_8
import kotlin.io.path.createDirectories
import kotlin.io.path.writeText

/**
 * Compiles Kotlin/Native klibs, links a binary and a test runner from them and runs both, once for
 * each way the Kotlin/Native rules compile a klib: by default (the Build Tools API, no header
 * klibs), with `experimental_native_build_tools_api=false` (the konanc command line) and with
 * `experimental_native_header_klibs=true` (dependents compile against header klibs). The build
 * settings choose how a klib is compiled, not what the program does, so every mode has to print
 * the same line and pass the same tests.
 */
class NativeCompilationModesTest : BazelIntegrationTestBase() {
  private class Mode(
    val name: String,
    val flags: List<String>,
    val buildToolsApi: Boolean,
    val headerKlibs: Boolean,
  )

  @Test
  fun everyModeBuildsTheSameProgram() {
    val release = unpackRelease(env("RULES_KOTLIN_RELEASE"))
    val workspace = root.resolve("workspace").createDirectories()

    // A persistent repository cache keeps the Kotlin/Native distribution.
    val repositoryCache = System.getenv("RULES_KOTLIN_REPOSITORY_CACHE")

    // Link dependencies are staged for the konan target of the host only.
    val hostTarget =
      if (System.getProperty("os.name").lowercase().contains("mac")) "macos_arm64" else "linux_x64"
    workspace.resolve("MODULE.bazel").writeText(
      """
      module(name = "native_compilation_modes")
      bazel_dep(name = "rules_kotlin", version = "2.2.0")
      kotlin_native = use_extension("@rules_kotlin//src/main/starlark/core/repositories:native.bzl", "kotlin_native")
      kotlin_native.targets(targets = ["$hostTarget"])
      """.trimIndent(),
    )
    workspace.resolve("BUILD.bazel").writeText(
      """
      load("@rules_kotlin//kotlin:native.bzl", "kt_native_binary", "kt_native_library", "kt_native_test")

      kt_native_library(
          name = "greeter",
          srcs = ["Greeter.kt"],
      )

      # With header klibs, app compiles against the header klib of greeter.
      kt_native_library(
          name = "app",
          srcs = ["App.kt"],
          deps = [":greeter"],
      )

      kt_native_binary(
          name = "hello",
          srcs = ["Hello.kt"],
          deps = [":app"],
      )

      # decorate is internal to greeter: with header klibs, the test reads it from a header klib.
      kt_native_test(
          name = "greeter_test",
          srcs = ["GreeterTest.kt"],
          associates = [":greeter"],
      )
      """.trimIndent(),
    )
    workspace.resolve("Greeter.kt").writeText(
      """
      package greeter

      fun greet(name: String): String = "Hello, " + decorate(name) + "!"

      internal fun decorate(name: String): String = name.uppercase()
      """.trimIndent(),
    )
    workspace.resolve("App.kt").writeText(
      """
      package app

      import greeter.greet

      fun conversation(name: String): String = greet(name) + " Goodbye."
      """.trimIndent(),
    )
    workspace.resolve("Hello.kt").writeText(
      """
      import app.conversation

      fun main() {
          println(conversation("native"))
      }
      """.trimIndent(),
    )
    workspace.resolve("GreeterTest.kt").writeText(
      """
      package greeter

      import kotlin.test.Test
      import kotlin.test.assertEquals

      class GreeterTest {
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

    fun bazel(
      command: String,
      vararg args: String,
    ): String =
      bazel
        .run(
          workspace,
          "--batch",
          "--ignore_all_rc_files",
          "--host_jvm_args=-Djava.net.preferIPv6Addresses=system",
          "--output_user_root=${root.resolve("bazel")}",
          "--output_base=${root.resolve("output")}",
          command,
          *args,
        ).getOrThrow()
        .stdOut
        .toString(UTF_8)

    for (mode in MODES) {
      val flags =
        arrayOf(
          "--jobs=2",
          "--noshow_progress",
          "--color=no",
          "--override_module=rules_kotlin=$release",
          // The KonanLauncher runs on Java 17 or later, as in examples/native.
          "--java_runtime_version=remotejdk_21",
          "--tool_java_runtime_version=remotejdk_21",
          *listOfNotNull(repositoryCache?.let { "--repository_cache=$it" }).toTypedArray(),
          *mode.flags.toTypedArray(),
        )

      // Klibs are reproducible, so without this the links of a later mode could be action cache
      // hits of an earlier one. A clean output tree makes every mode compile and link on its own.
      bazel("clean")

      val compilation =
        bazel("aquery", *flags, "mnemonic(\"KotlinNativeKlibCompile\", //:greeter)")
      assertEquals(
        "${mode.name}: greeter compiled with the Build Tools API: $compilation",
        mode.buildToolsApi,
        "--btapi-classpath" in compilation,
      )
      assertEquals(
        "${mode.name}: greeter writes a header klib: $compilation",
        mode.headerKlibs,
        "greeter.header.klib" in compilation,
      )

      assertEquals(
        "${mode.name}: the output of //:hello",
        "Hello, NATIVE! Goodbye.",
        bazel("run", *flags, "//:hello").trim(),
      )
      bazel("test", *flags, "--test_output=errors", "//:greeter_test")
    }
  }

  companion object {
    private const val SETTINGS = "--@rules_kotlin//kotlin/settings"

    private val MODES =
      listOf(
        Mode("default", emptyList(), buildToolsApi = true, headerKlibs = false),
        Mode(
          "konanc command line",
          listOf("$SETTINGS:experimental_native_build_tools_api=false"),
          buildToolsApi = false,
          headerKlibs = false,
        ),
        Mode(
          "header klibs",
          listOf("$SETTINGS:experimental_native_header_klibs=true"),
          buildToolsApi = true,
          headerKlibs = true,
        ),
      )
  }
}
