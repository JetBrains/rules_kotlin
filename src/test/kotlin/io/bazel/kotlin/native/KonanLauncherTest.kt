/*
 * Copyright 2026 The Bazel Authors. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package io.bazel.kotlin.native

import com.google.common.truth.Truth.assertThat
import com.google.devtools.build.runfiles.Runfiles
import org.jetbrains.kotlin.buildtools.api.CompilationResult
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.junit.runners.JUnit4
import java.io.ByteArrayOutputStream
import java.io.PrintStream
import java.nio.charset.StandardCharsets.UTF_8
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths

/**
 * Runs [KonanLauncher] in a fake execroot with a fake compiler jar (fake/MainKt.java), which
 * writes a report of what it gets and sees to report.txt, and a [KlibCompiler] that records the
 * klib compilations it gets in place of the Build Tools API.
 */
@RunWith(JUnit4::class)
class KonanLauncherTest {
  @get:Rule
  val temp = TemporaryFolder()

  private lateinit var execroot: Path

  private class Result(
    val exitCode: Int,
    val stderr: String,
  )

  /** Records the compilations it gets and whether they see the scratch directories. */
  private inner class RecordingKlibCompiler(
    val exitCode: Int = KonanLauncher.EXIT_OK,
  ) : KlibCompiler {
    val compilations = mutableListOf<Pair<KlibCompilation, List<Path>>>()
    var scratchDirectories = false

    override fun compile(
      compilation: KlibCompilation,
      runtimeClasspath: List<Path>,
      err: PrintStream,
    ): Int {
      compilations += compilation to runtimeClasspath
      scratchDirectories =
        Files.isDirectory(execroot.resolve(DATA_DIR)) &&
        Files.isDirectory(execroot.resolve(AUTO_CACHE_DIR))
      err.println("compiled with the Build Tools API")
      return exitCode
    }
  }

  @Before
  fun setUp() {
    execroot = temp.newFolder("execroot").toPath()
    val compilerJar = execroot.resolve("dist").resolve(KonanLauncher.COMPILER_JAR)
    Files.createDirectories(compilerJar.parent)
    Files.copy(fakeCompiler(), compilerJar)
    for (dependency in listOf("gcc-fixture/sysroot", "llvm-fixture/bin")) {
      val dir = Files.createDirectories(execroot.resolve("bundle/dependencies/$dependency"))
      Files.write(dir.resolve("marker"), listOf(dependency), UTF_8)
    }
  }

  @Test
  fun runsTheToolInProcessWithTheDistributionAsKonanHome() {
    val result = launch("-produce", "library", "-Xdebug-prefix-map=__EXECROOT__=.")

    assertThat(result.exitCode).isEqualTo(KonanLauncher.EXIT_OK)
    assertThat(report())
      .containsAtLeast(
        "tool=konanc",
        "konan.home=${execroot.resolve("dist")}",
        "arg=-Xkonan-data-dir=${execroot.resolve(DATA_DIR)}",
        "arg=-Xauto-cache-dir=${execroot.resolve(AUTO_CACHE_DIR)}",
        "arg=-produce",
        "arg=library",
        "arg=-Xdebug-prefix-map=$execroot=.",
        "arg=-o",
        "arg=${execroot.resolve("report.txt")}",
      ).inOrder()
  }

  @Test
  fun compilesAKlibWithKonancWithoutABuildToolsApi() {
    val result =
      compileKlib(
        "-Xfragment-sources=common:src/common.kt",
        "-Xdebug-prefix-map=__EXECROOT__=.",
        sources = listOf("src/common.kt", "src/hello.kt"),
        klibCompiler = { _, _, _ -> throw AssertionError("not a Build Tools API compilation") },
      )

    // -produce library first, then the flags, the output and the sources, with the same absolute
    // paths as with the Build Tools API: konanc matches the sources against -Xfragment-sources.
    assertThat(result.exitCode).isEqualTo(KonanLauncher.EXIT_OK)
    assertThat(report().filter { it.startsWith("arg=") })
      .containsExactly(
        "arg=-produce",
        "arg=library",
        "arg=-Xkonan-data-dir=${execroot.resolve(DATA_DIR)}",
        "arg=-Xauto-cache-dir=${execroot.resolve(AUTO_CACHE_DIR)}",
        "arg=-Xfragment-sources=common:${execroot.resolve("src/common.kt")}",
        "arg=-Xdebug-prefix-map=$execroot=.",
        "arg=-o",
        "arg=${execroot.resolve("report.txt")}",
        "arg=${execroot.resolve("src/common.kt")}",
        "arg=${execroot.resolve("src/hello.kt")}",
      ).inOrder()
    assertThat(report()).contains("tool=konanc")
  }

  @Test
  fun compilesAKlibWithTheBuildToolsApiGivenItsImplementation() {
    val compiler = RecordingKlibCompiler()

    val result =
      compileKlib(
        "-Xfragment-sources=common:src/common.kt",
        "-Xfragment-sources=no-path",
        "-Xdebug-prefix-map=__EXECROOT__=.",
        sources = listOf("src/common.kt", "src/hello.kt"),
        btapiClasspath =
          listOf("btapi/kotlin-build-tools-impl.jar", "btapi/kotlin-daemon-client.jar"),
        klibCompiler = compiler,
      )

    assertThat(result.exitCode).isEqualTo(KonanLauncher.EXIT_OK)
    assertThat(result.stderr).contains("compiled with the Build Tools API")
    val (compilation, runtimeClasspath) = compiler.compilations.single()
    assertThat(compilation.workingDir).isEqualTo(execroot)
    assertThat(compilation.konanHome).isEqualTo(execroot.resolve("dist"))
    assertThat(compilation.compilerJar)
      .isEqualTo(execroot.resolve("dist").resolve(KonanLauncher.COMPILER_JAR))
    assertThat(compilation.sources)
      .containsExactly(execroot.resolve("src/common.kt"), execroot.resolve("src/hello.kt"))
      .inOrder()
    assertThat(compilation.output).isEqualTo(execroot.resolve("report.txt"))
    // The flags without -produce, -o and the sources, with the placeholder replaced and the paths of
    // the fragment sources as absolute as the sources.
    assertThat(compilation.flags)
      .containsExactly(
        "-Xkonan-data-dir=${execroot.resolve(DATA_DIR)}",
        "-Xauto-cache-dir=${execroot.resolve(AUTO_CACHE_DIR)}",
        "-Xfragment-sources=common:${execroot.resolve("src/common.kt")}",
        "-Xfragment-sources=no-path",
        "-Xdebug-prefix-map=$execroot=.",
      ).inOrder()
    assertThat(runtimeClasspath)
      .containsExactly(
        execroot.resolve("btapi/kotlin-build-tools-impl.jar"),
        execroot.resolve("btapi/kotlin-daemon-client.jar"),
      ).inOrder()

    // The compilation sees the scratch directories, which are deleted after it; konanc does not run.
    assertThat(compiler.scratchDirectories).isTrue()
    assertThat(Files.exists(execroot.resolve(DATA_DIR))).isFalse()
    assertThat(Files.exists(execroot.resolve("report.txt"))).isFalse()
  }

  @Test
  fun exitsWithTheExitCodeOfTheBuildToolsApiCompilation() {
    val result =
      compileKlib(
        btapiClasspath = listOf("btapi/kotlin-build-tools-impl.jar"),
        klibCompiler = RecordingKlibCompiler(KonanLauncher.EXIT_COMPILATION_ERROR),
      )

    assertThat(result.exitCode).isEqualTo(KonanLauncher.EXIT_COMPILATION_ERROR)
    assertThat(Files.exists(execroot.resolve(DATA_DIR))).isFalse()
  }

  @Test
  fun loadsTheImplementationWithTheCompilerJarOfTheDistribution() {
    val compiler = RecordingKlibCompiler()
    compileKlib(btapiClasspath = listOf("btapi/impl.jar", "btapi/cri.jar"), klibCompiler = compiler)
    val (compilation, runtimeClasspath) = compiler.compilations.single()

    assertThat(BtapiKlibCompiler.classpath(compilation, runtimeClasspath))
      .containsExactly(
        execroot.resolve("btapi/impl.jar"),
        execroot.resolve("btapi/cri.jar"),
        execroot.resolve("dist").resolve(KonanLauncher.COMPILER_JAR),
      ).inOrder()
  }

  @Test
  fun mapsTheResultsOfTheBuildToolsApiToExitCodes() {
    assertThat(BtapiKlibCompiler.exitCode(CompilationResult.COMPILATION_SUCCESS))
      .isEqualTo(KonanLauncher.EXIT_OK)
    assertThat(BtapiKlibCompiler.exitCode(CompilationResult.COMPILATION_ERROR))
      .isEqualTo(KonanLauncher.EXIT_COMPILATION_ERROR)
    assertThat(BtapiKlibCompiler.exitCode(CompilationResult.COMPILATION_OOM_ERROR))
      .isEqualTo(KonanLauncher.EXIT_INTERNAL_ERROR)
    assertThat(BtapiKlibCompiler.exitCode(CompilationResult.COMPILER_INTERNAL_ERROR))
      .isEqualTo(KonanLauncher.EXIT_INTERNAL_ERROR)
  }

  @Test
  fun reportsTheDiagnosticsOfTheToolRelativeToTheWorkingDirectory() {
    val processErr = System.err

    val result = launch("-Xfake-diagnostic=e: file://__EXECROOT__/src/bad.kt:3:5 unresolved")

    assertThat(result.exitCode).isEqualTo(KonanLauncher.EXIT_OK)
    assertThat(result.stderr).contains("e: src/bad.kt:3:5 unresolved\n")
    assertThat(result.stderr).doesNotContain(execroot.toString())
    // The launcher restores the error stream of the process.
    assertThat(System.err).isSameInstanceAs(processErr)
  }

  @Test
  fun reportsTheMessagesOfTheBuildToolsApiAsKonancDoes() {
    val out = ByteArrayOutputStream()
    val logger = BtapiKlibCompiler.logger(PrintStream(out, true, "UTF-8"), execroot)

    logger.error("file://$execroot/src/bad.kt:3:5 Unresolved reference 'x'.", null)
    logger.warn("$execroot/src/bad.kt:1:1 unused", null)
    logger.info("progress")
    logger.lifecycle("progress")

    assertThat(out.toString("UTF-8"))
      .isEqualTo("e: src/bad.kt:3:5 Unresolved reference 'x'.\nw: src/bad.kt:1:1 unused\n")
  }

  @Test
  fun reportsPathsRelativeToTheWorkingDirectory() {
    assertThat(KonanLauncher.relativeTo("e: file://$execroot/src/bad.kt:3:5 unresolved", execroot))
      .isEqualTo("e: src/bad.kt:3:5 unresolved")
    assertThat(KonanLauncher.relativeTo("w: $execroot/src/bad.kt:1:1 unused", execroot))
      .isEqualTo("w: src/bad.kt:1:1 unused")
    assertThat(KonanLauncher.relativeTo("e: file:///elsewhere/bad.kt:3:5 error", execroot))
      .isEqualTo("e: file:///elsewhere/bad.kt:3:5 error")
  }

  @Test
  fun isolatesTheCompilerFromTheLauncher() {
    assertThat(launch().exitCode).isEqualTo(KonanLauncher.EXIT_OK)

    assertThat(report())
      .containsAtLeast(
        "context-loader-is-compiler-loader=true",
        "launcher-visible=false",
        "kotlin-stdlib-visible=false",
      )
  }

  @Test
  fun runsTheGivenTool() {
    assertThat(launch(tool = "cinterop").exitCode).isEqualTo(KonanLauncher.EXIT_OK)

    assertThat(report()).contains("tool=cinterop")
  }

  @Test
  fun createsEmptyScratchDirectoriesWithoutStagedDependencies() {
    assertThat(launch().exitCode).isEqualTo(KonanLauncher.EXIT_OK)

    assertThat(report()).containsAtLeast("data-dir=0 entries", "auto-cache-dir=0 entries")
  }

  @Test
  fun stagesTheLinkDependenciesIntoTheDataDirectory() {
    val result =
      launch(
        stagedDeps = listOf("bundle/dependencies/llvm-fixture", "bundle/dependencies/gcc-fixture"),
      )

    assertThat(result.exitCode).isEqualTo(KonanLauncher.EXIT_OK)
    val dependencies = execroot.resolve("bundle/dependencies")
    assertThat(report())
      .containsAtLeast(
        "data-dir=1 entries",
        "dependency=gcc-fixture -> ${dependencies.resolve("gcc-fixture")}",
        "dependency=llvm-fixture -> ${dependencies.resolve("llvm-fixture")}",
        // In the order of the arguments, one name per line.
        "extracted=llvm-fixture\\ngcc-fixture\\n",
      ).inOrder()
  }

  @Test
  fun replacesStaleScratchDirectories() {
    val staleDependencies = Files.createDirectories(execroot.resolve("$DATA_DIR/dependencies/stale"))
    Files.write(staleDependencies.resolveSibling(".extracted"), listOf("stale"), UTF_8)
    val staleCache = Files.createDirectories(execroot.resolve("$AUTO_CACHE_DIR/stale-cache"))

    val result = launch(stagedDeps = listOf("bundle/dependencies/gcc-fixture"))

    assertThat(result.exitCode).isEqualTo(KonanLauncher.EXIT_OK)
    assertThat(report()).containsAtLeast("extracted=gcc-fixture\\n", "auto-cache-dir=0 entries")
    assertThat(report()).doesNotContain("not-a-link=stale")
    assertThat(Files.exists(staleCache)).isFalse()
  }

  @Test
  fun deletesTheScratchDirectoriesButNotTheStagedDependencies() {
    val result = launch(stagedDeps = listOf("bundle/dependencies/llvm-fixture"))

    assertThat(result.exitCode).isEqualTo(KonanLauncher.EXIT_OK)
    assertThat(Files.exists(execroot.resolve(DATA_DIR))).isFalse()
    assertThat(Files.exists(execroot.resolve(AUTO_CACHE_DIR))).isFalse()
    assertThat(Files.exists(execroot.resolve("bundle/dependencies/llvm-fixture/bin/marker")))
      .isTrue()
  }

  @Test
  fun exitsWithACompilationErrorWhenTheToolReportsErrors() {
    val result = launch("-fail", stagedDeps = listOf("bundle/dependencies/llvm-fixture"))

    assertThat(result.exitCode).isEqualTo(KonanLauncher.EXIT_COMPILATION_ERROR)
    assertThat(result.stderr).contains("konanc: Compilation finished with errors")
    // The tool has reported the errors already: no stack trace.
    assertThat(result.stderr).doesNotContain("\tat ")
    assertThat(Files.exists(execroot.resolve(DATA_DIR))).isFalse()
    assertThat(Files.exists(execroot.resolve("bundle/dependencies/llvm-fixture/bin/marker")))
      .isTrue()
  }

  @Test
  fun exitsWithAnInternalErrorWhenTheToolFails() {
    val result = launch("-crash")

    assertThat(result.exitCode).isEqualTo(KonanLauncher.EXIT_INTERNAL_ERROR)
    assertThat(result.stderr).contains("konan_launcher: konanc failed")
    assertThat(result.stderr).contains("the fake compiler crashed")
    assertThat(result.stderr).contains("\tat ")
  }

  @Test
  fun rejectsInvalidArguments() {
    val valid =
      listOf("--konan-home", "dist", "--data-dir", DATA_DIR, "--auto-cache-dir", AUTO_CACHE_DIR)
    mapOf(
      listOf("--tool", "konanc") + valid to "missing -- before the tool arguments",
      listOf("--tool", "kotlinc") + valid + "--" to "unknown tool kotlinc",
      listOf("--tool", "konanc", "--target", "linux_x64") + valid + "--" to
        "unknown flag --target",
      listOf("--tool", "konanc", "--tool", "klib") + valid + "--" to "--tool is given twice",
      listOf("--tool", "konanc", "--data-dir", DATA_DIR, "--") to
        "missing --konan-home, --auto-cache-dir",
      valid + "--tool" + "--" to "--tool needs a value",
      listOf("--tool", "konanc") + valid + listOf("--source", "src/hello.kt", "--") to
        "--source needs --klib-output",
      listOf("--tool", "konanc") + valid + listOf("--btapi-classpath", "impl.jar", "--") to
        "--btapi-classpath needs --klib-output",
      listOf("--tool", "klib") + valid + listOf("--klib-output", "out/hello.klib", "--") to
        "--klib-output needs --tool konanc",
      listOf("--tool", "konanc") + valid +
        listOf("--klib-output", "a.klib", "--klib-output", "b.klib", "--") to
        "--klib-output is given twice",
    ).forEach { (args, message) ->
      val result = launchWith(args)

      assertThat(result.exitCode).isEqualTo(KonanLauncher.EXIT_INTERNAL_ERROR)
      assertThat(result.stderr).contains("konan_launcher: $message")
      assertThat(result.stderr).contains("usage: konan_launcher")
    }
  }

  @Test
  fun keepsTheScratchDirectoriesUnderTheWorkingDirectory() {
    val outside = Files.createDirectories(temp.root.toPath().resolve("outside"))
    Files.write(outside.resolve("keep"), listOf("keep"), UTF_8)

    val result =
      launchWith(
        listOf(
          "--tool",
          "konanc",
          "--konan-home",
          "dist",
          "--data-dir",
          "../outside",
          "--auto-cache-dir",
          AUTO_CACHE_DIR,
          "--",
        ),
      )

    assertThat(result.exitCode).isEqualTo(KonanLauncher.EXIT_INTERNAL_ERROR)
    assertThat(result.stderr)
      .contains("the scratch directory ../outside is not under the working directory")
    assertThat(Files.exists(outside.resolve("keep"))).isTrue()
  }

  @Test
  fun rejectsAMissingCompiler() {
    val result =
      launchWith(
        listOf(
          "--tool",
          "konanc",
          "--konan-home",
          "nowhere",
          "--data-dir",
          DATA_DIR,
          "--auto-cache-dir",
          AUTO_CACHE_DIR,
          "--",
        ),
      )

    assertThat(result.exitCode).isEqualTo(KonanLauncher.EXIT_INTERNAL_ERROR)
    assertThat(result.stderr).contains("konan_launcher: no Kotlin/Native compiler at")
  }

  @Test
  fun rejectsAStagedDependencyThatIsNotADirectory() {
    val result = launch(stagedDeps = listOf("bundle/dependencies/missing"))

    assertThat(result.exitCode).isEqualTo(KonanLauncher.EXIT_INTERNAL_ERROR)
    assertThat(result.stderr)
      .contains("the staged dependency bundle/dependencies/missing is not a directory")
  }

  @Test
  fun rejectsStagedDependenciesOfTheSameName() {
    Files.createDirectories(execroot.resolve("other/llvm-fixture"))

    val result =
      launch(stagedDeps = listOf("bundle/dependencies/llvm-fixture", "other/llvm-fixture"))

    assertThat(result.exitCode).isEqualTo(KonanLauncher.EXIT_INTERNAL_ERROR)
    assertThat(result.stderr).contains("more than one staged dependency is named llvm-fixture")
    assertThat(Files.exists(execroot.resolve(DATA_DIR))).isFalse()
  }

  @Test
  fun expandsParamFiles() {
    val params = temp.newFile("launcher.params").toPath()
    Files.write(params, listOf("--tool", "konanc", "", "a path/with spaces"), UTF_8)

    assertThat(KonanLauncher.expandParamFiles(listOf("@$params", "-v")))
      .containsExactly("--tool", "konanc", "", "a path/with spaces", "-v")
      .inOrder()
  }

  private fun fakeCompiler(): Path =
    Paths.get(Runfiles.preload().unmapped().rlocation(System.getProperty("fake_konan_compiler")))

  private fun report(): List<String> = Files.readAllLines(execroot.resolve("report.txt"), UTF_8)

  /** Launches [tool] with the tool arguments of a konanc action and [toolArgs]. */
  private fun launch(
    vararg toolArgs: String,
    tool: String = "konanc",
    stagedDeps: List<String> = emptyList(),
  ): Result =
    launchWith(
      listOf("--tool", tool, "--konan-home", "dist") +
        listOf("--data-dir", DATA_DIR, "--auto-cache-dir", AUTO_CACHE_DIR) +
        stagedDeps.flatMap { listOf("--staged-deps", it) } +
        "--" +
        listOf(
          "-Xkonan-data-dir=${KonanLauncher.EXECROOT_PLACEHOLDER}/$DATA_DIR",
          "-Xauto-cache-dir=${KonanLauncher.EXECROOT_PLACEHOLDER}/$AUTO_CACHE_DIR",
        ) +
        toolArgs +
        listOf("-o", "${KonanLauncher.EXECROOT_PLACEHOLDER}/report.txt"),
    )

  /**
   * Compiles [sources] into a klib, report.txt, with the tool arguments of a konanc action and
   * [toolArgs], through [klibCompiler] with a [btapiClasspath]. The output is absolute, so the fake
   * compiler writes it into the execroot.
   */
  private fun compileKlib(
    vararg toolArgs: String,
    sources: List<String> = listOf("src/hello.kt"),
    btapiClasspath: List<String> = emptyList(),
    klibCompiler: KlibCompiler,
  ): Result =
    launchWith(
      listOf("--tool", "konanc", "--konan-home", "dist") +
        listOf("--data-dir", DATA_DIR, "--auto-cache-dir", AUTO_CACHE_DIR) +
        listOf("--klib-output", execroot.resolve("report.txt").toString()) +
        sources.flatMap { listOf("--source", it) } +
        btapiClasspath.flatMap { listOf("--btapi-classpath", it) } +
        "--" +
        listOf(
          "-Xkonan-data-dir=${KonanLauncher.EXECROOT_PLACEHOLDER}/$DATA_DIR",
          "-Xauto-cache-dir=${KonanLauncher.EXECROOT_PLACEHOLDER}/$AUTO_CACHE_DIR",
        ) +
        toolArgs,
      klibCompiler,
    )

  private fun launchWith(
    args: List<String>,
    klibCompiler: KlibCompiler = KlibCompiler { _, _, _ -> throw AssertionError("no klib") },
  ): Result {
    val stderr = ByteArrayOutputStream()
    val exitCode =
      KonanLauncher.run(args, execroot, PrintStream(stderr, true, "UTF-8"), klibCompiler)
    return Result(exitCode, stderr.toString("UTF-8"))
  }

  private companion object {
    const val DATA_DIR = "out/hello.klib.konan_data"
    const val AUTO_CACHE_DIR = "out/hello.klib.konan_cache"
  }
}
