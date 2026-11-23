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

import org.jetbrains.kotlin.buildtools.api.CompilationResult
import org.jetbrains.kotlin.buildtools.api.DelicateBuildToolsApi
import org.jetbrains.kotlin.buildtools.api.ExperimentalBuildToolsApi
import org.jetbrains.kotlin.buildtools.api.KotlinLogger
import org.jetbrains.kotlin.buildtools.api.KotlinToolchains
import org.jetbrains.kotlin.buildtools.api.SharedApiClassesClassLoader
import org.jetbrains.kotlin.buildtools.api.arguments.CommonCompilerArguments
import org.jetbrains.kotlin.buildtools.api.konan.NativePlatformToolchain
import java.io.PrintStream
import java.net.URLClassLoader
import java.nio.file.Path

/**
 * Compiles a klib with a `NativeKlibCompilationOperation` of the Kotlin Build Tools API, in-process.
 *
 * It loads the implementation of the runtime class path, with the compiler jar of the distribution,
 * in a class loader that shares only the API classes with the launcher. The operation gets the
 * konanc flags of the compilation as command-line arguments and the distribution as `KOTLIN_HOME`,
 * and adds `-produce library`, `-o` and the sources itself. The messages of the compiler go to the
 * error stream as the konanc command line prints them, after `e: ` or `w: `, with the paths under
 * the working directory relative to it.
 */
@OptIn(ExperimentalBuildToolsApi::class, DelicateBuildToolsApi::class)
object BtapiKlibCompiler : KlibCompiler {
  override fun compile(
    compilation: KlibCompilation,
    runtimeClasspath: List<Path>,
    err: PrintStream,
  ): Int {
    // The loader stays open: the compiler may still load classes, e.g. in shutdown hooks, until the
    // process exits.
    val loader =
      URLClassLoader(
        classpath(compilation, runtimeClasspath).map { it.toUri().toURL() }.toTypedArray(),
        SharedApiClassesClassLoader(), // only the Build Tools API classes come from the launcher
      )
    val thread = Thread.currentThread()
    val contextLoader = thread.contextClassLoader
    thread.contextClassLoader = loader
    try {
      val toolchains = KotlinToolchains.loadImplementation(loader)
      val native =
        try {
          toolchains.getToolchain(NativePlatformToolchain::class.java)
        } catch (e: Exception) {
          return noNativeToolchain(toolchains, e, err)
        } catch (e: LinkageError) {
          return noNativeToolchain(toolchains, e, err)
        }
      val operation =
        native.nativeKlibCompilationOperationBuilder(compilation.sources, compilation.output)
      operation.compilerArguments.applyCommandLineArguments(compilation.flags)
      operation.compilerArguments[CommonCompilerArguments.KOTLIN_HOME] = compilation.konanHome
      val result =
        toolchains.createBuildSession().use { session ->
          session.executeOperation(
            operation.build(),
            toolchains.createInProcessExecutionPolicy(),
            logger(err, compilation.workingDir),
          )
        }
      return exitCode(result)
    } catch (e: Exception) {
      return failed(e, err)
    } catch (e: LinkageError) {
      return failed(e, err)
    } finally {
      thread.contextClassLoader = contextLoader
    }
  }

  /** The class path of the implementation: the runtime jars, then the compiler jar. */
  fun classpath(
    compilation: KlibCompilation,
    runtimeClasspath: List<Path>,
  ): List<Path> =
    // Not `runtimeClasspath + compilation.compilerJar`: a Path is an Iterable of its names.
    runtimeClasspath + listOf(compilation.compilerJar)

  /** The exit code of the launcher for the [result] of a compilation. */
  fun exitCode(result: CompilationResult): Int =
    when (result) {
      CompilationResult.COMPILATION_SUCCESS -> KonanLauncher.EXIT_OK
      CompilationResult.COMPILATION_ERROR -> KonanLauncher.EXIT_COMPILATION_ERROR
      else -> KonanLauncher.EXIT_INTERNAL_ERROR
    }

  private fun noNativeToolchain(
    toolchains: KotlinToolchains,
    failure: Throwable,
    err: PrintStream,
  ): Int {
    err.println(
      "konan_launcher: the Build Tools API implementation of Kotlin " +
        "${toolchains.getCompilerVersion()} has no Kotlin/Native toolchain " +
        "(it needs 2.5.20-dev-4986 or newer): $failure",
    )
    return KonanLauncher.EXIT_INTERNAL_ERROR
  }

  private fun failed(
    failure: Throwable,
    err: PrintStream,
  ): Int {
    err.println("konan_launcher: the Build Tools API klib compilation failed")
    failure.printStackTrace(err)
    return KonanLauncher.EXIT_INTERNAL_ERROR
  }

  /**
   * Prints the errors and warnings of the compiler to [err] as the konanc command line does, with
   * the paths under [workingDir] relative to it; the other messages are progress.
   */
  fun logger(
    err: PrintStream,
    workingDir: Path,
  ): KotlinLogger =
    object : KotlinLogger {
      override val isDebugEnabled: Boolean = false

      override fun error(
        msg: String,
        throwable: Throwable?,
      ) {
        err.println("e: ${KonanLauncher.relativeTo(msg, workingDir)}")
        throwable?.printStackTrace(err)
      }

      override fun warn(
        msg: String,
        throwable: Throwable?,
      ) {
        err.println("w: ${KonanLauncher.relativeTo(msg, workingDir)}")
        throwable?.printStackTrace(err)
      }

      override fun info(msg: String) {}

      override fun debug(msg: String) {}

      override fun lifecycle(msg: String) {}
    }
}
