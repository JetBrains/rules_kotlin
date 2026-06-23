package io.bazel.kotlin.builder.tasks.jvm

import com.google.common.truth.Truth.assertThat
import io.bazel.kotlin.builder.Deps
import io.bazel.kotlin.builder.toolchain.BtapiRuntimeSpec
import io.bazel.kotlin.builder.toolchain.BtapiToolchainsCache
import io.bazel.kotlin.builder.toolchain.CompilationStatusException
import io.bazel.kotlin.builder.toolchain.CompilationTaskContext
import io.bazel.kotlin.model.JvmCompilationTask
import io.bazel.kotlin.model.Platform
import io.bazel.kotlin.model.RuleKind
import org.jetbrains.kotlin.buildtools.api.ExperimentalBuildToolsApi
import org.jetbrains.kotlin.buildtools.api.KotlinToolchains
import org.jetbrains.kotlin.buildtools.api.arguments.CommonCompilerArguments
import org.jetbrains.kotlin.buildtools.api.arguments.ExperimentalCompilerArgument
import org.jetbrains.kotlin.buildtools.api.arguments.JvmCompilerArguments
import org.jetbrains.kotlin.buildtools.api.arguments.enums.JvmTarget
import org.jetbrains.kotlin.buildtools.api.jvm.JvmPlatformToolchain.Companion.jvm
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.JUnit4
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.PrintStream
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import kotlin.test.assertEquals
import kotlin.test.assertNull

// NOTE: this test target is compiled at the default toolchain jvm_target (1.8) with the auto-derived
// -Xjdk-release=1.8, so its own sources must stick to JDK 8 APIs (Paths.get / Files.write, not the
// Java 11 Path.of / Files.writeString).

/**
 * Pins the JvmCompilerArguments.Builder behaviors configureCompilerArguments relies on, and verifies
 * end-to-end that:
 *  - a toolchain -jvm-target is NOT wiped by an unrelated passthrough flag (passthrough is applied
 *    first, then toolchain defaults fill what the user left unset), and
 *  - -Xjdk-release is auto-derived from the effective -jvm-target, so an API newer than the target is
 *    rejected (and admitted once the target is raised).
 */
@OptIn(ExperimentalBuildToolsApi::class, ExperimentalCompilerArgument::class)
@RunWith(JUnit4::class)
class BtapiArgsReadbackTest {

  private val runtime by lazy {
    BtapiRuntimeSpec(
      Paths.get(Deps.Dep.fromLabel("@kotlin_rules_maven//:org_jetbrains_kotlin_kotlin_build_tools_impl").singleCompileJar()),
      Paths.get(Deps.Dep.fromLabel("@kotlin_rules_maven//:org_jetbrains_kotlin_kotlin_compiler_embeddable").singleCompileJar()),
      Paths.get(Deps.Dep.fromLabel("@kotlin_rules_maven//:org_jetbrains_kotlin_kotlin_daemon_client").singleCompileJar()),
      Paths.get(Deps.Dep.fromLabel("//kotlin/compiler:kotlin-stdlib").singleCompileJar()),
      Paths.get(Deps.Dep.fromLabel("//kotlin/compiler:kotlin-reflect").singleCompileJar()),
      Paths.get(Deps.Dep.fromLabel("//kotlin/compiler:kotlinx-coroutines-core-jvm").singleCompileJar()),
      Paths.get(Deps.Dep.fromLabel("//kotlin/compiler:annotations").singleCompileJar()),
    )
  }

  private val toolchains: KotlinToolchains by lazy { BtapiToolchainsCache().get(runtime) }

  private val jvmTaskExecutor by lazy {
    val plugins = InternalCompilerPlugins.fromPaths(
      jvmAbiGenJar = Deps.Dep.fromLabel("//kotlin/compiler:jvm-abi-gen").singleCompileJar(),
      skipCodeGenJar = Deps.Dep.fromLabel("//src/main/kotlin:skip-code-gen").singleCompileJar(),
      kaptJar = Deps.Dep.fromLabel("@kotlin_rules_maven//:org_jetbrains_kotlin_kotlin_annotation_processing_embeddable").singleCompileJar(),
      jdepsJar = Deps.Dep.fromLabel("//src/main/kotlin:jdeps-gen").singleCompileJar(),
    )
    KotlinJvmTaskExecutor(runtime, plugins)
  }

  private lateinit var testDir: Path
  private lateinit var classesDir: Path

  @Before
  fun setUp() {
    val base = Paths.get(System.getenv("TEST_TMPDIR"))
    testDir = Files.createTempDirectory(base, "args-readback")
    classesDir = testDir.resolve("classes")
    Files.createDirectories(classesDir)
  }

  private fun freshArgs(): JvmCompilerArguments.Builder =
    toolchains.jvm.jvmCompilationOperationBuilder(emptyList(), testDir).compilerArguments

  // ---- Builder behaviors configureCompilerArguments depends on ----

  /** Unset options read back as null -- so `get(key) == null` is a valid "user did not set it" test. */
  @Test
  fun `unset toolchain-managed options default to null`() {
    val args = freshArgs()
    assertNull(args[JvmCompilerArguments.JVM_TARGET])
    assertNull(args[JvmCompilerArguments.X_JDK_RELEASE])
    assertNull(args[CommonCompilerArguments.API_VERSION])
    assertNull(args[CommonCompilerArguments.LANGUAGE_VERSION])
  }

  @Test
  fun `set then get returns the set value`() {
    val args = freshArgs()
    args[JvmCompilerArguments.JVM_TARGET] = JvmTarget.JVM_17
    assertEquals(JvmTarget.JVM_17, args[JvmCompilerArguments.JVM_TARGET])
  }

  @Test
  fun `applyArgumentStrings then get returns the parsed value`() {
    val args = freshArgs()
    args.applyArgumentStrings(listOf("-jvm-target=11"))
    assertEquals(JvmTarget.JVM_11, args[JvmCompilerArguments.JVM_TARGET])
  }

  @Test
  fun `applyArgumentStrings RESETS values not named in the parsed flags`() {
    val args = freshArgs()
    args[JvmCompilerArguments.JVM_TARGET] = JvmTarget.JVM_17
    args.applyArgumentStrings(listOf("-Xlambdas=class"))
    assertNull(args[JvmCompilerArguments.JVM_TARGET])
  }

  // ---- End-to-end ----

  @Test
  fun `toolchain jvm-target is applied even when an unrelated passthrough flag is present`() {
    val exit = compile(jvmTarget = "17", source = "package test\nclass A", passthroughFlags = listOf("-Xlambdas=class"))
    assertThat(exit).isEqualTo(0)
    // Java 17 bytecode == class-file major version 61. If the passthrough had wiped the toolchain
    // -jvm-target, kotlinc would fall back to its own default (1.8 / major 52).
    assertThat(classFileMajorVersion(classesDir.resolve("test").resolve("A.class"))).isEqualTo(61)
  }

  @Test
  fun `auto-derived -Xjdk-release rejects an API newer than the jvm-target`() {
    // jvm-target 1.8 -> -Xjdk-release=1.8; Path.of (Java 11) must not resolve.
    val exit = compile(jvmTarget = "1.8", source = USES_JAVA_11_API)
    assertThat(exit).isNotEqualTo(0)
  }

  @Test
  fun `raising the jvm-target admits the newer API`() {
    // jvm-target 17 -> -Xjdk-release=17; Path.of resolves.
    val exit = compile(jvmTarget = "17", source = USES_JAVA_11_API)
    assertThat(exit).isEqualTo(0)
  }

  private fun classFileMajorVersion(classFile: Path): Int {
    val bytes = Files.readAllBytes(classFile)
    return ((bytes[6].toInt() and 0xFF) shl 8) or (bytes[7].toInt() and 0xFF)
  }

  /** Compiles [source] as test/A.kt and returns the worker exit code (0 on success). */
  private fun compile(jvmTarget: String, source: String, passthroughFlags: List<String> = emptyList()): Int {
    val srcFile = testDir.resolve("A.kt")
    Files.write(srcFile, source.toByteArray())

    fun dir(name: String): String {
      val p = testDir.resolve(name)
      Files.createDirectories(p)
      return p.toAbsolutePath().toString()
    }

    val task = JvmCompilationTask.newBuilder().apply {
      infoBuilder.apply {
        label = "//test:a"
        moduleName = "test_module"
        platform = Platform.JVM
        ruleKind = RuleKind.LIBRARY
        addAllPassthroughFlags(passthroughFlags)
        toolchainInfoBuilder.apply {
          commonBuilder.apply {
            apiVersion = "2.0"
            languageVersion = "2.0"
            coroutines = "enabled"
          }
          jvmBuilder.jvmTarget = jvmTarget
        }
      }
      directoriesBuilder.apply {
        classes = classesDir.toAbsolutePath().toString()
        javaClasses = dir("java_classes")
        abiClasses = dir("abi_classes")
        generatedSources = dir("generated_sources")
        generatedJavaSources = dir("generated_java_sources")
        generatedStubClasses = dir("stubs")
        temp = dir("temp")
        generatedClasses = dir("generated_classes")
        coverageMetadataClasses = dir("coverage_metadata")
      }
      inputsBuilder.apply {
        addKotlinSources(srcFile.toAbsolutePath().toString())
        addClasspath(Deps.Dep.fromLabel("//kotlin/compiler:kotlin-stdlib").singleCompileJar())
        addClasspath(Deps.Dep.fromLabel("//kotlin/compiler:kotlin-stdlib-jdk7").singleCompileJar())
        addClasspath(Deps.Dep.fromLabel("//kotlin/compiler:kotlin-stdlib-jdk8").singleCompileJar())
      }
      outputsBuilder.apply {
        jar = testDir.resolve("output.jar").toAbsolutePath().toString()
        srcjar = testDir.resolve("output-sources.jar").toAbsolutePath().toString()
        jdeps = testDir.resolve("output.jdeps").toAbsolutePath().toString()
      }
      compileKotlin = true
      instrumentCoverage = false
    }.build()

    val context = CompilationTaskContext(
      task.info,
      PrintStream(ByteArrayOutputStream()),
      testDir.toAbsolutePath().toString() + File.separator,
    )
    return try {
      jvmTaskExecutor.execute(context, task)
      0
    } catch (e: CompilationStatusException) {
      e.status
    }
  }

  private companion object {
    val USES_JAVA_11_API = """
      package test
      import java.nio.file.Path
      class A {
        fun p(): Path = Path.of("x")
      }
    """.trimIndent()
  }
}
