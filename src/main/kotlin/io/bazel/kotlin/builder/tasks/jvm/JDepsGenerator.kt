/*
 * Copyright 2018 The Bazel Authors. All rights reserved.
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
package io.bazel.kotlin.builder.tasks.jvm

import com.google.devtools.build.lib.view.proto.Deps
import io.bazel.kotlin.builder.toolchain.CompilationStatusException
import io.bazel.kotlin.builder.toolchain.CompilationTaskContext
import io.bazel.kotlin.builder.utils.jars.JarOwner
import io.bazel.kotlin.builder.utils.jars.SourceDependencies
import io.bazel.kotlin.model.JvmCompilationTask
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths

object JDepsGenerator {
  internal fun writeJdeps(
    path: String,
    jdepsContent: Deps.Dependencies,
  ) {
    Paths.get(path).also {
      Files.deleteIfExists(it)
      FileOutputStream(Files.createFile(it).toFile()).use(jdepsContent::writeTo)
    }
  }

  internal fun emptyJdeps(label: String): Deps.Dependencies =
    Deps.Dependencies.newBuilder().let {
      it.ruleLabel = label
      it.build()
    }

  /**
   * The file the jdeps plugin records the dependencies of each source in, see
   * [io.bazel.kotlin.builder.utils.jars.SourceDependenciesFile]. The plugin appends to it, so the
   * file is deleted: the compilation analyzes every source.
   */
  internal fun newSourceDependencies(task: JvmCompilationTask): Path =
    Paths.get(task.directories.temp, "source_dependencies").also(Files::deleteIfExists)

  /**
   * Writes the jdeps of [task] from the dependencies of each of its sources, which the jdeps plugin
   * records, and checks them against the strict deps level.
   *
   * @throws CompilationStatusException on strict deps violations at the `error` level.
   */
  internal fun writeJdeps(
    context: CompilationTaskContext,
    task: JvmCompilationTask,
    sourceDependencies: Collection<SourceDependencies>,
  ) {
    val explicitJars = sourceDependencies.flatMapTo(LinkedHashSet()) { it.explicitJars }
    writeJdeps(
      task.outputs.jdeps,
      jdepsOf(
        task.info.label,
        task.inputs.directDependenciesList,
        explicitJars,
        sourceDependencies.flatMapTo(LinkedHashSet()) { it.implicitJars },
      ),
    )
    when (task.info.strictKotlinDeps) {
      "warn" -> {
        checkStrictDeps(context, task, explicitJars)
      }

      "error" -> {
        if (checkStrictDeps(context, task, explicitJars)) {
          throw CompilationStatusException("Strict Deps Violations - please fix", 1)
        }
      }
    }
  }

  /**
   * Prints strict deps warnings and returns true if violations were found.
   */
  private fun checkStrictDeps(
    context: CompilationTaskContext,
    task: JvmCompilationTask,
    explicitJars: Set<String>,
  ): Boolean {
    val targetLabel = task.info.label
    val missingStrictDeps =
      explicitJars
        .filter { !task.inputs.directDependenciesList.contains(it) }
        .map { JarOwner.readJarOwnerFromManifest(Paths.get(it)) }

    if (missingStrictDeps.isNotEmpty()) {
      val missingStrictLabels = missingStrictDeps.mapNotNull { it.label }

      val open = "\u001b[35m\u001b[1m"
      val close = "\u001b[0m"

      var command =
        """
        $open ** Please add the following dependencies:$close
        ${
          missingStrictDeps.map { it.label ?: it.jar }.joinToString(" ")
        } to $targetLabel
        """

      if (missingStrictLabels.isNotEmpty()) {
        command += """$open ** You can use the following buildozer command:$close
        buildozer 'add deps ${
          missingStrictLabels.joinToString(" ")
        }' $targetLabel
        """
      }

      context.printCompilerOutput(command.trimIndent().lines())
      return true
    }
    return false
  }
}

/**
 * The jdeps of a compilation: the direct dependencies no source uses, the jars the sources use
 * explicitly, and the ones they need only implicitly, e.g. for a supertype. The builder writes
 * them from the dependencies of each source, see
 * [io.bazel.kotlin.builder.utils.jars.SourceDependenciesFile], so that a compilation of some of
 * the sources writes the bytes a compilation of all of them writes.
 */
fun jdepsOf(
  label: String,
  directDependencies: List<String>,
  explicitJars: Collection<String>,
  implicitJars: Collection<String>,
): Deps.Dependencies {
  val explicit = explicitJars.toSet()

  fun dependency(
    kind: Deps.Dependency.Kind,
    jar: String,
  ) = Deps.Dependency
    .newBuilder()
    .setKind(kind)
    .setPath(jar)
    .build()
  val dependencies =
    directDependencies.distinct().filterNot(explicit::contains).map {
      dependency(Deps.Dependency.Kind.UNUSED, it)
    } +
      explicit.map { dependency(Deps.Dependency.Kind.EXPLICIT, it) } +
      implicitJars.distinct().filterNot(explicit::contains).map {
        dependency(Deps.Dependency.Kind.IMPLICIT, it)
      }
  return Deps.Dependencies
    .newBuilder()
    .setSuccess(true)
    .setRuleLabel(label)
    // A stable sort: a direct dependency only used implicitly lists as unused, then implicit.
    .addAllDependency(dependencies.sortedBy { it.path })
    .build()
}
