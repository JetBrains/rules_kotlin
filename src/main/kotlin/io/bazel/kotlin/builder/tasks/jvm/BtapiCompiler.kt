/*
 * Copyright 2025 The Bazel Authors. All rights reserved.
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
import io.bazel.kotlin.model.JvmCompilationTask
import org.jetbrains.kotlin.buildtools.api.BaseIncrementalCompilationConfiguration.Companion.FORCE_RECOMPILATION
import org.jetbrains.kotlin.buildtools.api.BaseIncrementalCompilationConfiguration.Companion.MODULE_BUILD_DIR
import org.jetbrains.kotlin.buildtools.api.BaseIncrementalCompilationConfiguration.Companion.OUTPUT_DIRS
import org.jetbrains.kotlin.buildtools.api.BaseIncrementalCompilationConfiguration.Companion.ROOT_PROJECT_DIR
import org.jetbrains.kotlin.buildtools.api.CompilationResult
import org.jetbrains.kotlin.buildtools.api.CompilerArgumentsParseException
import org.jetbrains.kotlin.buildtools.api.ExperimentalBuildToolsApi
import org.jetbrains.kotlin.buildtools.api.KotlinLogger
import org.jetbrains.kotlin.buildtools.api.KotlinToolchains
import org.jetbrains.kotlin.buildtools.api.SourcesChanges
import org.jetbrains.kotlin.buildtools.api.arguments.CommonCompilerArguments
import org.jetbrains.kotlin.buildtools.api.arguments.CompilerPlugin
import org.jetbrains.kotlin.buildtools.api.arguments.CompilerPluginOption
import org.jetbrains.kotlin.buildtools.api.arguments.ExperimentalCompilerArgument
import org.jetbrains.kotlin.buildtools.api.arguments.JvmCompilerArguments
import org.jetbrains.kotlin.buildtools.api.arguments.enums.JvmTarget
import org.jetbrains.kotlin.buildtools.api.jvm.JvmPlatformToolchain.Companion.jvm
import org.jetbrains.kotlin.buildtools.api.jvm.operations.JvmCompilationOperation
import org.jetbrains.kotlin.buildtools.api.jvm.operations.JvmCompilationOperation.Companion.INCREMENTAL_COMPILATION
import java.io.BufferedInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.ObjectOutputStream
import java.io.PrintStream
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import java.security.MessageDigest
import java.util.Base64
import org.jetbrains.kotlin.buildtools.api.arguments.enums.KotlinVersion as BtapiKotlinVersion

/**
 * Compiler that uses the Kotlin Build Tools API directly from protobuf task data.
 *
 * Constructs typed BTAPI arguments directly from the JvmCompilationTask protobuf.
 */
@OptIn(ExperimentalBuildToolsApi::class)
class BtapiCompiler(
  private val toolchains: KotlinToolchains,
) : AutoCloseable {
  private val lazyBuildSession = lazy { toolchains.createBuildSession() }
  private val buildSession by lazyBuildSession

  override fun close() {
    if (lazyBuildSession.isInitialized()) {
      buildSession.close()
    }
  }

  /**
   * Compiles Kotlin sources using the Build Tools API.
   *
   * @param task The compilation task protobuf containing all compilation info
   * @param plugins Internal compiler plugins (jdeps, jvm-abi-gen, etc.)
   * @return CompilationResult indicating success or failure
   */
  fun compile(
    task: JvmCompilationTask,
    plugins: InternalCompilerPlugins,
    out: PrintStream,
  ): CompilationResult {
    val compilerPlugins = buildCompilerPlugins(task, plugins)
    val logger = createCompilerLogger(out, verbose = task.info.icEnableLogging)
    var hashUpdate: IncrementalArgsHashUpdate? = null

    val result =
      executeCompilation(
        task = task,
        outputDir = Path.of(task.directories.classes),
        compilerPlugins = compilerPlugins,
        logger = logger,
      ) { operation, _ ->
        // Configure incremental compilation if enabled
        if (task.info.incrementalCompilation && task.directories.incrementalBaseDir.isNotEmpty()) {
          hashUpdate = configureIncrementalCompilation(operation, task, compilerPlugins)
        }
      }

    if (result == CompilationResult.COMPILATION_SUCCESS) {
      hashUpdate?.also { storeArgsHash(it.icBaseDir, it.currentHash) }
    }

    return result
  }

  /**
   * Common compilation execution logic shared by compile and compileKapt.
   */
  private fun executeCompilation(
    task: JvmCompilationTask,
    outputDir: Path,
    compilerPlugins: List<CompilerPlugin>,
    logger: KotlinLogger,
    additionalConfiguration: (
      JvmCompilationOperation.Builder,
      JvmCompilerArguments.Builder,
    ) -> Unit = { _, _ -> },
  ): CompilationResult {
    // Collect sources from protobuf
    val sources =
      (task.inputs.kotlinSourcesList + task.inputs.javaSourcesList)
        .map { Path.of(it) }

    // Create BTAPI compilation operation builder
    val operation = toolchains.jvm.jvmCompilationOperationBuilder(sources, outputDir)
    val compilerArgs = operation.compilerArguments

    // Configure compiler arguments directly from protobuf
    configureCompilerArguments(compilerArgs, task)

    // Configure compiler plugins
    if (compilerPlugins.isNotEmpty()) {
      compilerArgs[CommonCompilerArguments.COMPILER_PLUGINS] = compilerPlugins
    }

    // Allow caller to do additional configuration
    additionalConfiguration(operation, compilerArgs)

    // Execute the compilation
    return buildSession.executeOperation(operation.build(), logger = logger)
  }

  /**
   * Configures compiler arguments from protobuf fields using typed BTAPI setters.
   */
  @OptIn(ExperimentalCompilerArgument::class)
  private fun configureCompilerArguments(
    args: JvmCompilerArguments.Builder,
    task: JvmCompilationTask,
  ) {
    // Precedence is encoded by application order: toolchain defaults < user options < rules-managed.

    // 1. Toolchain defaults -- applied first so user-specified options below can override them.
    args[JvmCompilerArguments.JVM_TARGET] =
      requireJvmTarget(task.info.toolchainInfo.jvm.jvmTarget)
    args[CommonCompilerArguments.API_VERSION] =
      requireKotlinVersion(
        version = task.info.toolchainInfo.common.apiVersion,
        fieldName = "kotlin_api_version",
      )
    args[CommonCompilerArguments.LANGUAGE_VERSION] =
      requireKotlinVersion(
        version = task.info.toolchainInfo.common.languageVersion,
        fieldName = "kotlin_language_version",
      )

    // 2. User-specified options (kt_kotlinc_options + kotlin_passthrough_flags) -- may override the
    //    toolchain defaults above; the rules-managed settings below still win.
    if (task.info.passthroughFlagsList.isNotEmpty()) {
      try {
        args.applyArgumentStrings(task.info.passthroughFlagsList)
      } catch (e: CompilerArgumentsParseException) {
        throw IllegalArgumentException(
          "Invalid passthrough flag in kotlin_passthrough_flags: ${e.message}",
          e,
        )
      }
    }

    // 3. Rules-managed settings -- applied last so user options cannot clobber them.
    args[JvmCompilerArguments.MODULE_NAME] = task.info.moduleName
    args[JvmCompilerArguments.NO_STDLIB] = true
    args[JvmCompilerArguments.NO_REFLECT] = true

    // Classpath - convert to absolute paths
    val classpath = computeClasspath(task).map { Path.of(File(it).absolutePath) }
    if (classpath.isNotEmpty()) {
      args[JvmCompilerArguments.CLASSPATH] = classpath
    }

    // Friend paths (for internal visibility)
    if (task.info.friendPathsList.isNotEmpty()) {
      args[JvmCompilerArguments.X_FRIEND_PATHS] =
        task.info.friendPathsList
          .map { Path.of(File(it).absolutePath) }
    }
  }

  /**
   * Computes the classpath for compilation.
   * Handles reduced classpath mode when enabled.
   *
   * IMPORTANT: Friend paths (associate jars) are placed FIRST on the classpath.
   * This ensures that when the same class exists in both a friend jar and a regular dep
   * (split package scenario), the friend's version is found first. This is critical for
   * internal visibility to work correctly - the compiler must find the class from the
   * friend module to allow access to internal members.
   */
  private fun computeClasspath(task: JvmCompilationTask): List<String> {
    val baseClasspath =
      when (task.info.reducedClasspathMode) {
        "KOTLINBUILDER_REDUCED" -> {
          val transitiveDepsForCompile = mutableSetOf<String>()
          task.inputs.depsArtifactsList.forEach { jdepsPath ->
            BufferedInputStream(Files.newInputStream(Paths.get(jdepsPath))).use {
              val deps = Deps.Dependencies.parseFrom(it)
              deps.dependencyList.forEach { dep ->
                if (dep.kind == Deps.Dependency.Kind.EXPLICIT) {
                  transitiveDepsForCompile.add(dep.path)
                }
              }
            }
          }
          task.inputs.directDependenciesList + transitiveDepsForCompile
        }
        else -> task.inputs.classpathList
      }

    // Put friend paths FIRST on the classpath, then the rest (excluding duplicates).
    // This ensures associate jars shadow any conflicting classes from regular deps.
    val friendPathsSet = task.info.friendPathsList.toSet()
    val classpathWithoutFriends = baseClasspath.filter { it !in friendPathsSet }

    // Add generated classes directory to classpath
    return task.info.friendPathsList + classpathWithoutFriends + task.directories.generatedClasses
  }

  /**
   * Builds compiler plugins for BTAPI using the typed CompilerPlugin API.
   */
  private fun buildCompilerPlugins(
    task: JvmCompilationTask,
    plugins: InternalCompilerPlugins,
  ): List<CompilerPlugin> {
    val result = mutableListOf<CompilerPlugin>()

    // JDeps plugin
    if (task.outputs.jdeps.isNotEmpty()) {
      result.add(buildJdepsPlugin(task, plugins.jdeps))
    }

    // JVM ABI Gen plugin
    if (task.outputs.abijar.isNotEmpty()) {
      result.add(buildAbiGenPlugin(task, plugins.jvmAbiGen))

      // Skip code gen if only generating ABI jar (no main output jar)
      if (task.outputs.jar.isEmpty()) {
        result.add(buildSkipCodeGenPlugin(plugins.skipCodeGen))
      }
    }

    // User plugins from protobuf
    result.addAll(buildUserPlugins(task))

    return result
  }

  /**
   * Builds the skip-code-gen plugin (has no options, just classpath).
   */
  private fun buildSkipCodeGenPlugin(skipCodeGen: InternalCompilerPlugin): CompilerPlugin =
    CompilerPlugin(
      pluginId = skipCodeGen.id,
      classpath = listOf(Path.of(skipCodeGen.jarPath)),
      rawArguments = emptyList(),
      orderingRequirements = emptySet(),
    )

  /**
   * Builds user-specified compiler plugins from protobuf options.
   */
  private fun buildUserPlugins(task: JvmCompilationTask): List<CompilerPlugin> =
    task.inputs.pluginsList
      .filter { hasPhase(it, JvmCompilationTask.Inputs.PluginPhase.PLUGIN_PHASE_COMPILE) }
      .map(::toBtapiPlugin)

  /**
   * Builds jdeps plugin using the typed CompilerPlugin API.
   */
  private fun buildJdepsPlugin(
    task: JvmCompilationTask,
    jdeps: InternalCompilerPlugin,
  ): CompilerPlugin {
    val options = mutableListOf<CompilerPluginOption>()

    options.add(CompilerPluginOption("output", task.outputs.jdeps))
    options.add(CompilerPluginOption("target_label", task.info.label))

    task.inputs.directDependenciesList.forEach {
      options.add(CompilerPluginOption("direct_dependencies", it))
    }

    task.inputs.classpathList.forEach {
      options.add(CompilerPluginOption("full_classpath", it))
    }

    options.add(CompilerPluginOption("strict_kotlin_deps", task.info.strictKotlinDeps))

    return CompilerPlugin(
      pluginId = jdeps.id,
      classpath = listOf(Path.of(jdeps.jarPath)),
      rawArguments = options,
      orderingRequirements = emptySet(),
    )
  }

  /**
   * Builds jvm-abi-gen plugin using the typed CompilerPlugin API.
   */
  private fun buildAbiGenPlugin(
    task: JvmCompilationTask,
    abiGen: InternalCompilerPlugin,
  ): CompilerPlugin {
    val options = mutableListOf<CompilerPluginOption>()

    options.add(CompilerPluginOption("outputDir", task.directories.abiClasses))

    if (task.info.treatInternalAsPrivateInAbiJar) {
      options.add(CompilerPluginOption("treatInternalAsPrivate", "true"))
    }
    if (task.info.removePrivateClassesInAbiJar) {
      options.add(CompilerPluginOption("removePrivateClasses", "true"))
    }
    if (task.info.removeDebugInfo) {
      options.add(CompilerPluginOption("removeDebugInfo", "true"))
    }
    // Upstream rules_kotlin does not expose these options via toolchain attributes or rule attrs,
    // so they are hard-coded here. The remaining JvmAbiCommandLineProcessor
    // options (removePrivateClasses, removeDebugInfo, treatInternalAsPrivate) are configured at the Starlark level
    // via the corresponding `experimental_*` toolchain attributes.
    options.add(CompilerPluginOption("removeDataClassCopyIfConstructorIsPrivate", "true"))
    options.add(CompilerPluginOption("preserveDeclarationOrder", "true"))

    return CompilerPlugin(
      pluginId = abiGen.id,
      classpath = listOf(Path.of(abiGen.jarPath)),
      rawArguments = options,
      orderingRequirements = emptySet(),
    )
  }

  /**
   * Configures incremental compilation for the operation.
   *
   * Dependency classpath snapshots are now explicit inputs (from the proto),
   * passed from Starlark as declared Bazel outputs of upstream snapshot actions.
   * BTAPI automatically forces full recompilation when the shrunk snapshot is missing.
   */
  private fun configureIncrementalCompilation(
    operation: JvmCompilationOperation.Builder,
    task: JvmCompilationTask,
    compilerPlugins: List<CompilerPlugin>,
  ): IncrementalArgsHashUpdate {
    val icBaseDir = Path.of(task.directories.incrementalBaseDir)
    val icWorkingDir = icBaseDir.resolve("ic-caches")

    // Compute force recompilation based on args hash
    val currentArgsHash = computeArgsHash(task, compilerPlugins)
    val previousArgsHash = loadArgsHash(icBaseDir)
    val argsChanged = previousArgsHash != null && previousArgsHash != currentArgsHash
    val forceRecompilation = argsChanged

    // Ensure IC directories exist before executing BTAPI operation.
    Files.createDirectories(icBaseDir)

    // Use explicit classpath snapshots from proto (passed by Starlark action)
    val classpathSnapshots = task.inputs.classpathSnapshotsList.map { Path.of(it) }

    val icConfig =
      operation
        .snapshotBasedIcConfigurationBuilder(
          workingDirectory = icWorkingDir,
          sourcesChanges = SourcesChanges.ToBeCalculated,
          dependenciesSnapshotFiles = classpathSnapshots,
        ).apply {
          this[ROOT_PROJECT_DIR] = Path.of(ROOT)
          this[MODULE_BUILD_DIR] =
            Path.of(task.directories.classes).parent ?: Path.of(task.directories.classes)
          this[FORCE_RECOMPILATION] = forceRecompilation
          this[OUTPUT_DIRS] = setOf(Path.of(task.directories.classes), icWorkingDir)
        }.build()

    operation[INCREMENTAL_COMPILATION] = icConfig

    return IncrementalArgsHashUpdate(icBaseDir = icBaseDir, currentHash = currentArgsHash)
  }

  /**
   * Computes a hash of the effective compiler-flag set, used to force a full recompilation when it
   * changes. Sources and the dependency classpath content are handled separately (by IC source
   * diffing and by dependency classpath snapshots), so they are intentionally not hashed here.
   *
   * SHA-256 is used (rather than a 32-bit hashCode accumulation) so that a collision -- which would
   * silently reuse a stale IC cache -- is negligibly unlikely. Each field and each list length is
   * length-prefixed so the fed byte stream is unambiguous.
   */
  private fun computeArgsHash(
    task: JvmCompilationTask,
    compilerPlugins: List<CompilerPlugin>,
  ): String {
    val digest = MessageDigest.getInstance("SHA-256")
    fun putInt(n: Int) =
      digest.update(
        byteArrayOf((n ushr 24).toByte(), (n ushr 16).toByte(), (n ushr 8).toByte(), n.toByte()),
      )
    fun put(value: String) {
      val bytes = value.toByteArray(StandardCharsets.UTF_8)
      putInt(bytes.size)
      digest.update(bytes)
    }
    fun putAll(values: List<String>) {
      putInt(values.size)
      values.forEach(::put)
    }

    // The Kotlin compiler version: codegen, ABI-gen output, and the IC cache format are all
    // version-specific, and the on-disk IC cache persists across a compiler bump (it is keyed on
    // the output path, not the compiler), so a change here must force a full recompile.
    put(toolchains.getCompilerVersion())
    put(task.info.moduleName)
    put(task.info.toolchainInfo.jvm.jvmTarget)
    put(task.info.toolchainInfo.common.apiVersion)
    put(task.info.toolchainInfo.common.languageVersion)
    putAll(task.info.passthroughFlagsList.sorted())
    // Fingerprint the full effective compiler-plugin set (internal jdeps / jvm-abi-gen /
    // skip-code-gen + user plugins) uniformly by their option lists, so e.g. the jvm-abi-gen
    // options take part in IC invalidation. The jdeps plugin encodes the compile classpath as
    // ordered options, so a change in classpath entries or order also forces a full recompile.
    // This list is already phase-filtered to the compile operation, so a plugin entering or
    // leaving the compile phase changes the fingerprint via membership; the plugin phase itself
    // is therefore not part of the per-plugin fingerprint (stubs-phase changes are reflected
    // through the KAPT-generated sources, handled by source-change detection).
    putAll(compilerPlugins.map(::compilerPluginFingerprint).sorted())

    return digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xFF) }
  }

  /** Uniform fingerprint of an effective compiler plugin, regardless of how it was assembled. */
  private fun compilerPluginFingerprint(plugin: CompilerPlugin): String {
    // Stable sort by key: distinct options become order-insensitive (no spurious invalidation if
    // their emission order changes), while repeated same-key options keep their relative order.
    // The jdeps plugin passes the compile classpath as repeated, ordered `full_classpath` options,
    // so a change in classpath order or entry count still changes this fingerprint.
    val options =
      plugin.rawArguments
        .sortedBy { it.key }
        .joinToString("\u0001") { "${it.key}\u0000${it.value}" }
    val classpath =
      plugin.classpath
        .map { it.toString() }
        .joinToString("\u0001")
    return "${plugin.pluginId}\u0002${classpath}\u0002$options"
  }

  private fun hasPhase(
    plugin: JvmCompilationTask.Inputs.Plugin,
    phase: JvmCompilationTask.Inputs.PluginPhase,
  ): Boolean = plugin.phasesList.contains(phase)

  private fun toBtapiPlugin(plugin: JvmCompilationTask.Inputs.Plugin): CompilerPlugin =
    CompilerPlugin(
      pluginId = plugin.id,
      classpath = plugin.classpathList.map { Path.of(it) },
      rawArguments =
        plugin.optionsList.map { option ->
          CompilerPluginOption(option.key, option.value)
        },
      orderingRequirements = emptySet(),
    )

  private fun storeArgsHash(
    icBaseDir: Path,
    hash: String,
  ) {
    val hashFile = icBaseDir.resolve("args-hash.txt")
    Files.writeString(hashFile, hash)
  }

  private fun loadArgsHash(icBaseDir: Path): String? {
    val hashFile = icBaseDir.resolve("args-hash.txt")
    return if (Files.exists(hashFile)) {
      Files.readString(hashFile).trim().ifEmpty { null }
    } else {
      null
    }
  }

  private data class IncrementalArgsHashUpdate(
    val icBaseDir: Path,
    val currentHash: String,
  )

  /**
   * Parse JVM target string to BTAPI enum and fail fast for unsupported values.
   */
  private fun requireJvmTarget(target: String): JvmTarget {
    val normalizedTarget = normalizeJvmTarget(target.trim())
    return JvmTarget.entries.firstOrNull { it.stringValue == normalizedTarget }
      ?: throw IllegalArgumentException(
        "Unsupported kotlin_jvm_target '$target'. Supported values: " +
          JvmTarget.entries.joinToString(", ") { it.stringValue },
      )
  }

  private fun normalizeJvmTarget(target: String): String =
    when (target) {
      "6" -> "1.6"
      "8" -> "1.8"
      else -> target
    }

  /**
   * Parse Kotlin version string to BTAPI enum and fail fast for unsupported values.
   */
  private fun requireKotlinVersion(
    version: String,
    fieldName: String,
  ): BtapiKotlinVersion =
    BtapiKotlinVersion.entries.firstOrNull { it.stringValue == version.trim() }
      ?: throw IllegalArgumentException(
        "Unsupported $fieldName '$version'. Supported values: " +
          BtapiKotlinVersion.entries.joinToString(", ") { it.stringValue },
      )

  /**
   * Creates a logger for compiler diagnostics.
   * Errors and warnings are always emitted; info/debug logs are emitted in verbose mode.
   */
  private fun createCompilerLogger(
    out: PrintStream,
    verbose: Boolean,
  ): KotlinLogger =
    object : KotlinLogger {
      override val isDebugEnabled: Boolean = verbose

      override fun error(
        msg: String,
        throwable: Throwable?,
      ) {
        out.println("[IC ERROR] $msg")
        throwable?.printStackTrace(out)
      }

      override fun warn(
        msg: String,
        throwable: Throwable?,
      ) {
        out.println("[IC WARN] $msg")
        throwable?.printStackTrace(out)
      }

      override fun info(msg: String) {
        if (verbose) {
          out.println("[IC INFO] $msg")
        }
      }

      override fun debug(msg: String) {
        if (verbose) {
          out.println("[IC DEBUG] $msg")
        }
      }

      override fun lifecycle(msg: String) {
        if (verbose) {
          out.println("[IC] $msg")
        }
      }
    }

  /**
   * Compiles Kotlin sources with KAPT (annotation processing) using the Build Tools API.
   *
   * This runs KAPT as a separate compilation phase before main compilation.
   * KAPT generates stubs and processes annotations, producing:
   * - Generated Java sources in directories.generatedJavaSources
   * - Generated classes in directories.generatedClasses
   * - Stubs in directories.stubs
   *
   * @param task The compilation task protobuf containing all compilation info
   * @param plugins Internal compiler plugins (must include kapt)
   * @param aptMode KAPT mode: "stubsAndApt" (default), "stubs", or "apt"
   * @param verbose Whether to enable verbose KAPT output
   * @return CompilationResult indicating success or failure
   */
  fun compileKapt(
    task: JvmCompilationTask,
    plugins: InternalCompilerPlugins,
    aptMode: String = "stubsAndApt",
    verbose: Boolean = false,
    out: PrintStream,
  ): CompilationResult {
    // Build KAPT plugin and stubs plugins
    val kaptPlugin = buildKaptCompilerPlugin(task, plugins, aptMode, verbose)
    val stubsPlugins = buildStubsPlugins(task, plugins)
    val compilerPlugins = listOf(kaptPlugin) + stubsPlugins

    val logger = createCompilerLogger(out, verbose = verbose)

    return executeCompilation(
      task = task,
      outputDir = Path.of(task.directories.generatedClasses),
      compilerPlugins = compilerPlugins,
      logger = logger,
    )
  }

  /**
   * Builds the KAPT compiler plugin using the typed CompilerPlugin API.
   */
  private fun buildKaptCompilerPlugin(
    task: JvmCompilationTask,
    plugins: InternalCompilerPlugins,
    aptMode: String,
    verbose: Boolean,
  ): CompilerPlugin {
    val pluginId = plugins.kapt.id

    // Create temp subdirectories for stubs and incremental data
    val stubsDir = Files.createDirectories(Paths.get(task.directories.temp).resolve("stubs"))
    val incrementalDataDir =
      Files.createDirectories(
        Paths.get(task.directories.temp).resolve("incrementalData"),
      )

    val options = mutableListOf<CompilerPluginOption>()

    // Core KAPT directories
    options.add(CompilerPluginOption("sources", task.directories.generatedJavaSources))
    options.add(CompilerPluginOption("classes", task.directories.generatedClasses))
    options.add(CompilerPluginOption("stubs", stubsDir.toString()))
    options.add(CompilerPluginOption("incrementalData", incrementalDataDir.toString()))

    // Javac arguments (encoded as Base64)
    val javacArgs =
      mapOf(
        "-target" to task.info.toolchainInfo.jvm.jvmTarget,
        "-source" to task.info.toolchainInfo.jvm.jvmTarget,
      )
    options.add(CompilerPluginOption("javacArguments", encodeMapForKapt(javacArgs)))

    // Other options
    options.add(CompilerPluginOption("correctErrorTypes", "false"))
    options.add(CompilerPluginOption("verbose", verbose.toString()))
    options.add(CompilerPluginOption("aptMode", aptMode))

    // Annotation processor classpath - one option per entry
    task.inputs.processorpathsList.forEach { processorPath ->
      options.add(CompilerPluginOption("apclasspath", processorPath))
    }

    // Processors list - one option per processor
    task.inputs.processorsList.forEach { processor ->
      options.add(CompilerPluginOption("processors", processor))
    }

    // Read kapt apoptions from structured plugin options.
    val apOptions =
      task.inputs.pluginsList
        .asSequence()
        .filter { it.id == pluginId }
        .flatMap { it.optionsList.asSequence() }
        .associate { option -> option.key to option.value }

    if (apOptions.isNotEmpty()) {
      options.add(CompilerPluginOption("apoptions", encodeMapForKapt(apOptions)))
    }

    return CompilerPlugin(
      pluginId = pluginId,
      classpath = listOf(Path.of(plugins.kapt.jarPath)),
      rawArguments = options,
      orderingRequirements = emptySet(),
    )
  }

  /**
   * Builds CompilerPlugin objects for non-KAPT stubs plugins that should run during KAPT phase.
   */
  private fun buildStubsPlugins(
    task: JvmCompilationTask,
    plugins: InternalCompilerPlugins,
  ): List<CompilerPlugin> =
    task.inputs.pluginsList
      .filter { hasPhase(it, JvmCompilationTask.Inputs.PluginPhase.PLUGIN_PHASE_STUBS) }
      .filterNot { it.id == plugins.kapt.id }
      .map(::toBtapiPlugin)

  /**
   * Encodes a map to Base64 in the format expected by KAPT.
   * Uses Java serialization (ObjectOutputStream) compatible with KAPT's decodeMap.
   */
  private fun encodeMapForKapt(options: Map<String, String>): String {
    val os = ByteArrayOutputStream()
    val oos = ObjectOutputStream(os)

    oos.writeInt(options.size)
    for ((key, value) in options.entries) {
      oos.writeUTF(key)
      oos.writeUTF(value)
    }

    oos.flush()
    return Base64.getEncoder().encodeToString(os.toByteArray())
  }
}
