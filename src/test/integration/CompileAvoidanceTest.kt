package io.bazel.kotlin.integration

import com.google.protobuf.Struct
import com.google.protobuf.util.JsonFormat
import io.bazel.kotlin.test.BazelIntegrationTestBase
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.URI
import java.nio.file.Path
import java.nio.file.Paths
import kotlin.io.path.createDirectories
import kotlin.io.path.exists
import kotlin.io.path.readBytes
import kotlin.io.path.useLines
import kotlin.io.path.writeText

/**
 * Builds a Kotlin Multiplatform library and its JVM and Kotlin/Native dependents with
 * `experimental_use_abi_jars` on the Kotlin toolchain and `experimental_native_header_klibs`
 * enabled, edits the library and builds them again. An edit to a private body leaves the ABI jar
 * and the header klib of the library unchanged, so the compilations of the dependents stay cached;
 * a public signature edit changes both, and the dependents recompile.
 */
class CompileAvoidanceTest : BazelIntegrationTestBase() {
  /** The actions a build ran, as (mnemonic, label), and the files of its targets by name. */
  private class Build(
    private val actions: Set<Pair<String, String>>,
    private val files: Map<String, Path>,
  ) {
    fun ran(action: Pair<String, String>): Boolean = action in actions

    fun file(name: String): Path =
      requireNotNull(files[name]) { "No file $name among the outputs: ${files.keys}" }

    override fun toString(): String =
      actions.sortedBy { it.second }.joinToString { "${it.first} ${it.second}" }
  }

  private fun Struct.struct(name: String): Struct? = fieldsMap[name]?.structValue

  private fun Struct.string(name: String): String? = fieldsMap[name]?.stringValue

  /**
   * Reads the build event log of a build. With --build_event_publish_all_actions, it lists every
   * action that ran, and none whose result came from the action cache.
   */
  private fun read(log: Path): Build {
    val actions = mutableSetOf<Pair<String, String>>()
    val files = mutableMapOf<String, Path>()
    var complete = false
    log.useLines { lines ->
      lines.forEach { line ->
        val event = Struct.newBuilder().also { JsonFormat.parser().merge(line, it) }.build()
        complete = complete || event.fieldsMap["lastMessage"]?.boolValue == true
        event.struct("action")?.let { action ->
          val label =
            event.struct("id")?.struct("actionCompleted")?.string("label")
              ?: action.string("label")
          val mnemonic = action.string("type")
          if (label != null && mnemonic != null) {
            actions.add(mnemonic to label.removePrefix("@@").removePrefix("@"))
          }
        }
        val namedSet = event.struct("namedSetOfFiles")
        namedSet?.fieldsMap?.get("files")?.listValue?.valuesList?.forEach { file ->
          file.structValue.string("uri")?.let { uri ->
            val path = Paths.get(URI.create(uri))
            files[path.fileName.toString()] = path
          }
        }
      }
    }
    assertTrue("Missing final BEP event in $log", complete)
    return Build(actions, files)
  }

  @Test
  fun privateEditsDoNotRecompileDependents() {
    val release = unpackRelease(env("RULES_KOTLIN_RELEASE"))
    val workspace = root.resolve("workspace").createDirectories()
    val output = root.resolve("output")
    val logs = Paths.get(env("TEST_UNDECLARED_OUTPUTS_DIR"), "nested_bazel").createDirectories()

    // A persistent repository cache keeps the compilers and the Kotlin/Native distribution.
    val repositoryCache = System.getenv("RULES_KOTLIN_REPOSITORY_CACHE")

    workspace.resolve("MODULE.bazel").writeText(
      """
      module(name = "compile_avoidance")
      bazel_dep(name = "rules_kotlin", version = "2.2.0")
      register_toolchains("//:kotlin_toolchain")
      """.trimIndent(),
    )
    workspace.resolve("BUILD.bazel").writeText(
      """
      load("@rules_kotlin//kotlin:core.bzl", "define_kt_toolchain")
      load("@rules_kotlin//kotlin:jvm.bzl", "kt_jvm_library")
      load("@rules_kotlin//kotlin:kmp.bzl", "kt_multiplatform_library")
      load("@rules_kotlin//kotlin:native.bzl", "kt_native_library")

      define_kt_toolchain(
          name = "kotlin_toolchain",
          experimental_use_abi_jars = True,
      )

      # Greeter.kt is a fragment of the JVM and of the konan targets of the exec hosts: lib_jvm
      # compiles it with kmp_fragments, and lib_native for the konan target of the host.
      kt_multiplatform_library(
          name = "lib",
          jvm = dict(srcs = ["Greeter.kt"]),
          native = {
              "native": dict(
                  srcs = ["Greeter.kt"],
                  targets = [
                      "linux_x64",
                      "macos_arm64",
                  ],
              ),
          },
      )

      kt_jvm_library(
          name = "app_jvm",
          srcs = ["App.kt"],
          deps = [":lib"],
      )

      kt_native_library(
          name = "app_native",
          srcs = ["App.kt"],
          deps = [":lib"],
      )
      """.trimIndent(),
    )
    workspace.resolve("App.kt").writeText(
      """
      package app

      import lib.farewell
      import lib.greet

      fun conversation(name: String): String = greet(name) + " " + farewell(name)
      """.trimIndent(),
    )
    val greeter = workspace.resolve("Greeter.kt")
    var source = GREETER
    greeter.writeText(source)

    fun build(
      phase: String,
      vararg flags: String,
    ): Build {
      val log = logs.resolve("$phase.json")
      bazel
        .run(
          workspace,
          "--batch",
          "--ignore_all_rc_files",
          "--host_jvm_args=-Djava.net.preferIPv6Addresses=system",
          "--output_user_root=${root.resolve("bazel")}",
          "--output_base=$output",
          "build",
          "--jobs=2",
          "--noshow_progress",
          "--color=no",
          "--override_module=rules_kotlin=$release",
          // The KonanLauncher runs on Java 17 or later, as in examples/native.
          "--java_runtime_version=remotejdk_21",
          "--tool_java_runtime_version=remotejdk_21",
          *listOfNotNull(repositoryCache?.let { "--repository_cache=$it" }).toTypedArray(),
          "--@rules_kotlin//kotlin/settings:experimental_native_header_klibs=true",
          "--build_event_json_file=$log",
          "--build_event_publish_all_actions",
          *flags,
          *TARGETS,
        ).getOrThrow()
      return read(log).also { println("$phase ran: $it") }
    }

    val baseline = build("baseline")
    for (action in LIBRARY_COMPILES + DEPENDENT_COMPILES) {
      assertTrue("The baseline should run $action: $baseline", baseline.ran(action))
    }
    val klib = baseline.file("lib_native.klib")
    val header = klib.resolveSibling("lib_native.header.klib")
    val jar = baseline.file("lib_jvm.jar")
    val abiJar = jar.resolveSibling("lib_jvm.abi.jar")
    assertTrue(
      "lib_jvm should write an ABI jar",
      jar.resolveSibling("lib_jvm-kt.abi.jar").exists(),
    )
    val baselineKlib = klib.readBytes()
    val baselineHeader = header.readBytes()
    val baselineAbiJar = abiJar.readBytes()

    // A longer body of a private function: the library recompiles, its dependents do not. Its
    // Kotlin/Native compilation runs outside the sandbox this time, which must not change the
    // header klib either.
    source = source.replace("name.uppercase()", "name.trim().uppercase()")
    greeter.writeText(source)
    val privateEdit = build("private_body", "--strategy=KotlinNativeKlibCompile=local")
    for (action in LIBRARY_COMPILES) {
      assertTrue(
        "An edit to a private body should rerun $action: $privateEdit",
        privateEdit.ran(action),
      )
    }
    for (action in DEPENDENT_COMPILES) {
      assertFalse(
        "An edit to a private body should not rerun $action: $privateEdit",
        privateEdit.ran(action),
      )
    }
    assertFalse(
      "An edit to a private body should change lib_native.klib",
      baselineKlib.contentEquals(klib.readBytes()),
    )
    assertTrue(
      "An edit to a private body should not change lib_native.header.klib",
      baselineHeader.contentEquals(header.readBytes()),
    )
    assertTrue(
      "An edit to a private body should not change lib_jvm.abi.jar",
      baselineAbiJar.contentEquals(abiJar.readBytes()),
    )

    // A public signature: the header klib and the ABI jar change, and the dependents recompile.
    source =
      source.replace(
        "fun farewell(name: String): String = \"Goodbye, \" + name + \".\"",
        "fun farewell(name: String, mark: String = \".\"): String = \"Goodbye, \" + name + mark",
      )
    greeter.writeText(source)
    val publicEdit = build("public_signature")
    for (action in LIBRARY_COMPILES + DEPENDENT_COMPILES) {
      assertTrue(
        "A public signature edit should rerun $action: $publicEdit",
        publicEdit.ran(action),
      )
    }
    assertFalse(
      "A public signature edit should change lib_native.header.klib",
      baselineHeader.contentEquals(header.readBytes()),
    )
    assertFalse(
      "A public signature edit should change lib_jvm.abi.jar",
      baselineAbiJar.contentEquals(abiJar.readBytes()),
    )
  }

  companion object {
    private val GREETER =
      """
      package lib

      fun greet(name: String): String = "Hello, " + decorate(name) + "!"

      private fun decorate(name: String): String = name.uppercase()

      fun farewell(name: String): String = "Goodbye, " + name + "."
      """.trimIndent() + "\n"

    private val TARGETS = arrayOf("//:lib_jvm", "//:lib_native", "//:app_jvm", "//:app_native")

    private val LIBRARY_COMPILES =
      listOf(
        "KotlinCompile" to "//:lib_jvm",
        "KotlinNativeKlibCompile" to "//:lib_native",
      )

    private val DEPENDENT_COMPILES =
      listOf(
        "KotlinCompile" to "//:app_jvm",
        "KotlinNativeKlibCompile" to "//:app_native",
      )
  }
}
