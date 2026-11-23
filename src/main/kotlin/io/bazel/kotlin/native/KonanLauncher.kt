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

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.OutputStream
import java.io.PrintStream
import java.lang.reflect.InvocationTargetException
import java.net.URLClassLoader
import java.nio.charset.StandardCharsets.UTF_8
import java.nio.file.FileVisitResult
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.SimpleFileVisitor
import java.nio.file.attribute.BasicFileAttributes
import kotlin.system.exitProcess

/**
 * Runs a tool of a Kotlin/Native distribution (konanc, cinterop or klib) for one Bazel action.
 *
 * The Kotlin/Native rules (kotlin/internal/native/klib.bzl) run it with a params file of
 *
 * ```
 * --tool konanc|cinterop|klib --konan-home <dir> --data-dir <dir> --auto-cache-dir <dir>
 *   [--staged-deps <dir>]...
 *   [--klib-output <file> [--source <file>]... [--btapi-classpath <jar>]...]
 *   -- <tool arguments>
 * ```
 *
 * It recreates the action-local konan data and auto-cache directories and links every staged
 * dependency directory into `<data-dir>/dependencies`, listed in the `.extracted` marker there, so
 * the tool finds the link dependencies instead of downloading them. It replaces
 * [EXECROOT_PLACEHOLDER] in the tool arguments with the absolute working directory, and runs the
 * tool in-process: `MainKt.daemonMain` of the compiler jar of the distribution, the entry point
 * the Kotlin Gradle plugin uses too, in a class loader isolated from the launcher, with
 * `konan.home` set to the distribution in the sandbox. It deletes the scratch directories when the
 * tool is done. What the tool prints to `System.err`, such as its diagnostics, goes to the error
 * stream with the paths under the working directory relative to it, as in the sandbox they would
 * name the sandbox.
 *
 * A klib compilation gives its output (`--klib-output`, with `--tool konanc` only) and its sources
 * apart from the konanc flags, and both entry points get the absolute paths of a [KlibCompilation].
 * With the jars of a Kotlin/Native Build Tools API implementation (`--btapi-classpath`), it runs a
 * `NativeKlibCompilationOperation` of the Build Tools API in-process ([BtapiKlibCompiler]);
 * otherwise `daemonMain` compiles it with `-produce library`, the flags, `-o` and the sources.
 *
 * It exits with [EXIT_OK] when the tool succeeds, [EXIT_COMPILATION_ERROR] when the tool reports
 * errors in its input, and [EXIT_INTERNAL_ERROR] for a usage error or a failure of the tool.
 */
object KonanLauncher {
  /** Replaced in the tool arguments with the absolute working directory of the action. */
  const val EXECROOT_PLACEHOLDER = "__EXECROOT__"

  const val EXIT_OK = 0
  const val EXIT_COMPILATION_ERROR = 1
  const val EXIT_INTERNAL_ERROR = 2

  const val COMPILER_JAR = "konan/lib/kotlin-native-compiler-embeddable.jar"

  private const val KONANC = "konanc"
  private val TOOLS = listOf("cinterop", "klib", KONANC)
  private const val MAIN_CLASS = "org.jetbrains.kotlin.cli.utilities.MainKt"
  private const val ENTRY_POINT = "daemonMain"
  private const val FRAGMENT_SOURCES = "-Xfragment-sources="

  // The exceptions the tools throw for errors in their input, which they have reported already.
  private val COMPILATION_ERRORS =
    setOf(
      "org.jetbrains.kotlin.analyzer.CompilationErrorException",
      "org.jetbrains.kotlin.backend.konan.KonanCompilationException",
    )

  private const val USAGE =
    "usage: konan_launcher --tool konanc|cinterop|klib --konan-home <dir> --data-dir <dir> " +
      "--auto-cache-dir <dir> [--staged-deps <dir>]... " +
      "[--klib-output <file> [--source <file>]... [--btapi-classpath <jar>]...] -- <tool arguments>"

  @JvmStatic
  fun main(args: Array<String>) {
    exitProcess(run(expandParamFiles(args.asList()), Paths.get("").toAbsolutePath(), System.err))
  }

  /** The arguments, with every `@<file>` replaced by the lines of the (multiline) params file. */
  fun expandParamFiles(args: List<String>): List<String> =
    args.flatMap { arg ->
      if (arg.startsWith("@")) {
        Files.readAllLines(Paths.get(arg.substring(1)), UTF_8)
      } else {
        listOf(arg)
      }
    }

  /**
   * Runs the tool of [args] as the action in [workingDir] would, and returns the exit code.
   *
   * Relative paths in the launcher arguments are relative to [workingDir]; the tool arguments go
   * to the tool as they are, but for [EXECROOT_PLACEHOLDER] and, in a klib compilation, the paths
   * of `-Xfragment-sources`, which become absolute like the sources. [klibCompiler] compiles a klib
   * with a Build Tools API implementation.
   */
  fun run(
    args: List<String>,
    workingDir: Path,
    err: PrintStream,
    klibCompiler: KlibCompiler = BtapiKlibCompiler,
  ): Int {
    val root = workingDir.toAbsolutePath().normalize()
    val invocation =
      try {
        Invocation.parse(args)
      } catch (e: IllegalArgumentException) {
        err.println("konan_launcher: ${e.message}")
        err.println(USAGE)
        return EXIT_INTERNAL_ERROR
      }
    var scratch = emptyList<Path>()
    try {
      val konanHome = root.resolve(invocation.konanHome).normalize()
      val compilerJar = konanHome.resolve(COMPILER_JAR)
      require(Files.isRegularFile(compilerJar)) { "no Kotlin/Native compiler at $compilerJar" }
      scratch = listOf(invocation.dataDir, invocation.autoCacheDir).map { scratchDir(root, it) }
      scratch.forEach { dir ->
        deleteRecursively(dir)
        Files.createDirectories(dir)
      }
      if (invocation.stagedDeps.isNotEmpty()) {
        stage(root, scratch[0], invocation.stagedDeps)
      }
      val toolArgs = invocation.toolArgs.map { it.replace(EXECROOT_PLACEHOLDER, root.toString()) }
      val output = invocation.klibOutput
      if (output == null) {
        return withRelativeErr(root, err) {
          runTool(invocation.tool, toolArgs, konanHome, compilerJar, err)
        }
      }
      val compilation =
        KlibCompilation(
          workingDir = root,
          konanHome = konanHome,
          compilerJar = compilerJar,
          sources = invocation.sources.map { root.resolve(it).normalize() },
          output = root.resolve(output).normalize(),
          flags = absoluteFragmentSources(toolArgs, root),
        )
      if (invocation.btapiClasspath.isEmpty()) {
        val konancArgs =
          listOf("-produce", "library") + compilation.flags +
            listOf("-o", compilation.output.toString()) + compilation.sources.map { it.toString() }
        return withRelativeErr(root, err) {
          runTool(KONANC, konancArgs, konanHome, compilerJar, err)
        }
      }
      System.setProperty("konan.home", konanHome.toString())
      val runtimeClasspath = invocation.btapiClasspath.map { root.resolve(it).normalize() }
      return withRelativeErr(root, err) { klibCompiler.compile(compilation, runtimeClasspath, err) }
    } catch (e: IllegalArgumentException) {
      err.println("konan_launcher: ${e.message}")
      return EXIT_INTERNAL_ERROR
    } catch (e: IOException) {
      err.println("konan_launcher: $e")
      return EXIT_INTERNAL_ERROR
    } finally {
      scratch.forEach(::deleteRecursively)
    }
  }

  /**
   * The [flags] with the path of every `-Xfragment-sources=<fragment>:<path>` resolved against
   * [root], as the sources of a [KlibCompilation] are.
   *
   * The compiler assigns a source to the K2 fragment whose -Xfragment-sources names the same path.
   * The rules pass the sources of the fragments of a multiplatform compilation relative to the
   * working directory, and the Build Tools API passes the sources to the compiler as absolute paths.
   * Relative paths do not work on the command line either: konanc 2.5.20 dev builds then compile no
   * source of the fragments, without a diagnostic. Other flags are unchanged.
   */
  fun absoluteFragmentSources(
    flags: List<String>,
    root: Path,
  ): List<String> =
    flags.map { flag ->
      val fragmentSource = flag.removePrefix(FRAGMENT_SOURCES)
      val separator = fragmentSource.indexOf(':')
      if (fragmentSource.length == flag.length || separator < 0) {
        flag
      } else {
        val path = root.resolve(fragmentSource.substring(separator + 1)).normalize()
        "$FRAGMENT_SOURCES${fragmentSource.substring(0, separator)}:$path"
      }
    }

  /** [message] with the paths under [root], also as `file://` URIs, relative to it. */
  fun relativeTo(
    message: String,
    root: Path,
  ): String = message.replace("file://$root/", "").replace("$root/", "")

  /** Runs [tool] with `System.err` writing to [err], with the paths under [root] relative to it. */
  private fun <T> withRelativeErr(
    root: Path,
    err: PrintStream,
    tool: () -> T,
  ): T {
    val original = System.err
    val lines = RelativeLines(err, root)
    System.setErr(PrintStream(lines, true, "UTF-8"))
    try {
      return tool()
    } finally {
      System.err.flush()
      lines.finish()
      System.setErr(original)
    }
  }

  /** Writes to [out] line by line, with the paths under [root] relative to it (see [relativeTo]). */
  private class RelativeLines(
    private val out: PrintStream,
    private val root: Path,
  ) : OutputStream() {
    private val line = ByteArrayOutputStream()

    @Synchronized
    override fun write(b: Int) {
      line.write(b)
      if (b == '\n'.code) {
        emit()
      }
    }

    @Synchronized
    override fun flush() {
      out.flush()
    }

    /** Writes the last line, also without a line break. */
    @Synchronized
    fun finish() {
      emit()
      out.flush()
    }

    private fun emit() {
      if (line.size() > 0) {
        out.print(relativeTo(String(line.toByteArray(), UTF_8), root))
        line.reset()
      }
    }
  }

  /** A scratch directory of the action, which must be under (and not be) the working directory. */
  private fun scratchDir(
    root: Path,
    path: String,
  ): Path {
    val dir = root.resolve(path).normalize()
    require(dir.startsWith(root) && dir != root) {
      "the scratch directory $path is not under the working directory $root"
    }
    return dir
  }

  /**
   * Links each dependency directory into `<dataDir>/dependencies` under its name, and lists the
   * names in the `.extracted` marker there, which tells konan the dependencies are in place.
   */
  private fun stage(
    root: Path,
    dataDir: Path,
    dependencies: List<String>,
  ) {
    val staged = Files.createDirectories(dataDir.resolve("dependencies"))
    val names =
      dependencies.map { dependency ->
        val dir = root.resolve(dependency).normalize()
        require(Files.isDirectory(dir)) { "the staged dependency $dependency is not a directory" }
        val name = dir.fileName.toString()
        val link = staged.resolve(name)
        require(!Files.exists(link, NOFOLLOW_LINKS)) {
          "more than one staged dependency is named $name"
        }
        Files.createSymbolicLink(link, dir)
        name
      }
    Files.write(staged.resolve(".extracted"), names.joinToString("") { "$it\n" }.toByteArray(UTF_8))
  }

  private fun runTool(
    tool: String,
    toolArgs: List<String>,
    konanHome: Path,
    compilerJar: Path,
    err: PrintStream,
  ): Int {
    System.setProperty("konan.home", konanHome.toString())

    // The platform class loader as the parent keeps the classes of the launcher, e.g. its Kotlin
    // standard library, from the compiler, which bundles its own. The loader stays open: the tool
    // may still load classes, e.g. in shutdown hooks, until the process exits.
    val loader =
      URLClassLoader(arrayOf(compilerJar.toUri().toURL()), ClassLoader.getPlatformClassLoader())
    val entryPoint =
      try {
        loader.loadClass(MAIN_CLASS).getMethod(ENTRY_POINT, Array<String>::class.java)
      } catch (e: ReflectiveOperationException) {
        err.println("konan_launcher: $compilerJar has no $MAIN_CLASS.$ENTRY_POINT: $e")
        return EXIT_INTERNAL_ERROR
      }

    val thread = Thread.currentThread()
    val contextLoader = thread.contextClassLoader
    thread.contextClassLoader = loader
    try {
      entryPoint.invoke(null, (listOf(tool) + toolArgs).toTypedArray())
      return EXIT_OK
    } catch (e: InvocationTargetException) {
      val failure = e.targetException
      if (failure.isCompilationError()) {
        err.println("$tool: ${failure.message ?: "compilation failed"}")
        return EXIT_COMPILATION_ERROR
      }
      err.println("konan_launcher: $tool failed")
      failure.printStackTrace(err)
      return EXIT_INTERNAL_ERROR
    } finally {
      thread.contextClassLoader = contextLoader
    }
  }

  private fun Throwable.isCompilationError(): Boolean =
    generateSequence<Class<*>>(javaClass) { it.superclass }.any { it.name in COMPILATION_ERRORS }

  /** Deletes [path] and, unless it is a link, everything under it. Links are not followed. */
  private fun deleteRecursively(path: Path) {
    if (!Files.exists(path, NOFOLLOW_LINKS)) {
      return
    }
    Files.walkFileTree(
      path,
      object : SimpleFileVisitor<Path>() {
        override fun visitFile(
          file: Path,
          attrs: BasicFileAttributes,
        ): FileVisitResult {
          Files.delete(file)
          return FileVisitResult.CONTINUE
        }

        override fun postVisitDirectory(
          dir: Path,
          exc: IOException?,
        ): FileVisitResult {
          if (exc != null) {
            throw exc
          }
          Files.delete(dir)
          return FileVisitResult.CONTINUE
        }
      },
    )
  }

  /** The parsed launcher arguments. */
  internal class Invocation(
    val tool: String,
    val konanHome: String,
    val dataDir: String,
    val autoCacheDir: String,
    val stagedDeps: List<String>,
    val klibOutput: String?,
    val sources: List<String>,
    val btapiClasspath: List<String>,
    val toolArgs: List<String>,
  ) {
    companion object {
      private val REQUIRED = listOf("--tool", "--konan-home", "--data-dir", "--auto-cache-dir")
      private val SINGLE_VALUED = REQUIRED + "--klib-output"

      fun parse(args: List<String>): Invocation {
        val separator = args.indexOf("--")
        require(separator >= 0) { "missing -- before the tool arguments" }
        val values = mutableMapOf<String, String>()
        val stagedDeps = mutableListOf<String>()
        val sources = mutableListOf<String>()
        val btapiClasspath = mutableListOf<String>()
        var index = 0
        while (index < separator) {
          val flag = args[index]
          require(index + 1 < separator) { "$flag needs a value" }
          val value = args[index + 1]
          when (flag) {
            "--staged-deps" -> stagedDeps += value
            "--source" -> sources += value
            "--btapi-classpath" -> btapiClasspath += value
            in SINGLE_VALUED -> require(values.put(flag, value) == null) { "$flag is given twice" }
            else -> throw IllegalArgumentException("unknown flag $flag")
          }
          index += 2
        }
        val missing = REQUIRED.filter { it !in values }
        require(missing.isEmpty()) { "missing ${missing.joinToString()}" }
        val tool = values.getValue("--tool")
        require(tool in TOOLS) { "unknown tool $tool, expected one of ${TOOLS.joinToString()}" }
        val klibOutput = values["--klib-output"]
        require(klibOutput == null || tool == KONANC) { "--klib-output needs --tool $KONANC" }
        require(klibOutput != null || sources.isEmpty()) { "--source needs --klib-output" }
        require(klibOutput != null || btapiClasspath.isEmpty()) {
          "--btapi-classpath needs --klib-output"
        }
        return Invocation(
          tool = tool,
          konanHome = values.getValue("--konan-home"),
          dataDir = values.getValue("--data-dir"),
          autoCacheDir = values.getValue("--auto-cache-dir"),
          stagedDeps = stagedDeps,
          klibOutput = klibOutput,
          sources = sources,
          btapiClasspath = btapiClasspath,
          toolArgs = args.subList(separator + 1, args.size),
        )
      }
    }
  }
}

/** One klib compilation; every path is absolute, from the working directory of the launcher. */
class KlibCompilation(
  /** The working directory of the action, which the paths the compiler reports are relative to. */
  val workingDir: Path,
  /** The Kotlin/Native distribution. */
  val konanHome: Path,
  /** The compiler jar of the distribution, [KonanLauncher.COMPILER_JAR] under [konanHome]. */
  val compilerJar: Path,
  val sources: List<Path>,
  /** The klib the compilation writes. */
  val output: Path,
  /** The konanc flags, without `-produce`, `-o` and the sources. */
  val flags: List<String>,
)

/** Compiles a klib with the Kotlin/Native Build Tools API implementation of a runtime class path. */
fun interface KlibCompiler {
  /**
   * Compiles [compilation] with the implementation jars of [runtimeClasspath], reporting to [err],
   * and returns the exit code of the launcher.
   */
  fun compile(
    compilation: KlibCompilation,
    runtimeClasspath: List<Path>,
    err: PrintStream,
  ): Int
}
