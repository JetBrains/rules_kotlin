package io.bazel.kotlin.plugin.jdeps.k2

import io.bazel.kotlin.builder.utils.jars.SourceDependencies
import io.bazel.kotlin.builder.utils.jars.SourceDependenciesFile
import io.bazel.kotlin.plugin.jdeps.JdepsGenConfigurationKeys
import org.jetbrains.kotlin.codegen.ClassFileFactory
import org.jetbrains.kotlin.codegen.extensions.ClassFileFactoryFinalizerExtension
import org.jetbrains.kotlin.config.CompilerConfiguration
import java.nio.file.Paths

internal class JdepsGenExtension2(
  private val classUsageRecorder: ClassUsageRecorder,
  private val configuration: CompilerConfiguration,
) : ClassFileFactoryFinalizerExtension {
  /**
   * Appends the dependencies of the analyzed sources to the output, without reading it.
   * Incremental compilation analyzes only the recompiled sources, possibly over several rounds:
   * the builder merges the records of every round.
   */
  override fun finalizeClassFactory(factory: ClassFileFactory) {
    val output = configuration.getNotNull(JdepsGenConfigurationKeys.OUTPUT)
    SourceDependenciesFile.append(
      Paths.get(output),
      classUsageRecorder.jarsBySource.mapValues { (_, jars) ->
        SourceDependencies(jars.explicit, jars.implicit)
      },
    )
  }
}
