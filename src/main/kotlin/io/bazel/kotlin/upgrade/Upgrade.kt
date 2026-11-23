package io.bazel.kotlin.upgrade

import java.io.IOException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors

/**
 * Upgrades the JVM compiler, the Build Tools API and Kotlin/Native of the rules_kotlin checkout at
 * [workspace], or Kotlin/Native alone. Everything is fetched and validated before anything is
 * written; [log] reports what an upgrade leaves as it is.
 */
class Upgrade(
  private val workspace: Path,
  private val source: ReleaseSource,
  private val log: (String) -> Unit = {},
  private val replacer: FileReplacer = FileReplacer.ATOMIC,
) {
  /**
   * The new content of each changed file, by workspace-relative path, for the release train of
   * [version]: the JVM compiler, the Build Tools API, and Kotlin/Native unless rules_kotlin pins a
   * newer one (see [planNative]), which stays as it is.
   *
   * @param keep the older releases that stay pinned for Kotlin/Native and in the docs; by default
   *   the current release.
   */
  fun plan(
    version: String,
    keep: List<String> = emptyList(),
  ): Map<String, String> {
    val files = Checkout(workspace)
    val current = Rewrites.currentRelease(files.versions)
    val releases = (listOf(version) + keep.ifEmpty { listOf(current) }).distinct()
    releases.forEach(::checkRelease)
    val pinnedNative = Rewrites.nativeVersion(files.native)
    val movesNative = Rewrites.VERSION_ORDER.compare(version, pinnedNative) >= 0
    if (movesNative) checkNativeDefault(version)

    val konanHosts = Rewrites.konanHosts(files.targets)
    val metadata = releases.associateWith { source.release(it, konanHosts.keys) }
    val native =
      if (movesNative) {
        planNativeFiles(files, version, releases, konanHosts).files
      } else {
        log(
          "Kotlin/Native stays on $pinnedNative, which is newer than $version: " +
            "scripts/upgrade_kotlin.sh upgrade-native moves it",
        )
        emptyMap()
      }
    val nativePinned =
      if (movesNative) releases.toSet() else Rewrites.nativePrebuilt(files.native).keys

    val target = metadata.getValue(version)
    val level = Rewrites.languageLevel(version)
    val older = releases.filter { it != version }.sortedWith(Rewrites.VERSION_ORDER.reversed())
    var doc =
      Rewrites.rewriteDocRegion(
        files.read(KMP_DOC),
        older.joinToString("\n") {
          docSection(version, metadata.getValue(it), it in nativePinned)
        },
      )
    // Kotlin/Native follows the release train again: the sections above cover the kept releases.
    if (movesNative) {
      doc = Rewrites.rewriteDocRegion(doc, "", Rewrites.NATIVE_DOC_BEGIN, Rewrites.NATIVE_DOC_END)
    }
    val updated =
      mapOf(
        VERSIONS to Rewrites.rewriteVersions(files.versions, target),
        TOOLCHAINS to Rewrites.rewriteToolchains(files.read(TOOLCHAINS), level),
        KOTLINC_OPTIONS_TEST to
          Rewrites.rewriteKotlincOptionsTest(files.read(KOTLINC_OPTIONS_TEST), level),
        KMP_DOC to doc,
      ) + native +
        files.kotlinModules().associateWith {
          Rewrites.rewriteKotlinArtifacts(files.read(it), version)
        }
    return updated.filter { (path, content) -> files.read(path) != content }
  }

  /**
   * The new content of each changed file, by workspace-relative path, for Kotlin/Native [version]
   * alone, a release or a dev build: the Kotlin/Native tables of native_compiler.bzl, the
   * konan.properties excerpts of the tests, and the Kotlin/Native region of docs/kmp.md. [version]
   * must have a Kotlin/Native Build Tools API, which is checked before anything is downloaded.
   *
   * @param keep the older Kotlin/Native releases that stay pinned and documented; by default the
   *   current release of the JVM compiler.
   */
  fun planNative(
    version: String,
    keep: List<String> = emptyList(),
  ): Map<String, String> {
    val files = Checkout(workspace)
    val releases =
      (listOf(version) + keep.ifEmpty { listOf(Rewrites.currentRelease(files.versions)) })
        .distinct()
    releases.forEach(::checkRelease)
    checkNativeDefault(version)

    val plan = planNativeFiles(files, version, releases, Rewrites.konanHosts(files.targets))
    val older = releases.filter { it != version }.sortedWith(Rewrites.VERSION_ORDER.reversed())
    val doc =
      Rewrites.rewriteDocRegion(
        files.read(KMP_DOC),
        older.joinToString("\n") { nativeDocSection(version, plan.releases.getValue(it)) },
        Rewrites.NATIVE_DOC_BEGIN,
        Rewrites.NATIVE_DOC_END,
      )
    return (plan.files + (KMP_DOC to doc)).filter { (path, content) -> files.read(path) != content }
  }

  /** The new Kotlin/Native files, and the metadata of [releases] they pin. */
  private class NativePlan(
    val files: Map<String, String>,
    val releases: Map<String, NativeRelease>,
  )

  /**
   * Pins exactly [releases] in the Kotlin/Native tables, [default] as KOTLIN_NATIVE_VERSION, after
   * checking the published checksums against the pinned ones and the `konan.properties` of every
   * distribution against KOTLIN_NATIVE_DEPS.
   */
  private fun planNativeFiles(
    files: Checkout,
    default: String,
    releases: List<String>,
    konanHosts: Map<String, String>,
  ): NativePlan {
    val deps = Rewrites.nativeDeps(files.native)
    if (deps.keys != konanHosts.keys) {
      throw UpgradeException(
        "KOTLIN_NATIVE_DEPS has exec hosts ${deps.keys}, EXEC_HOSTS has ${konanHosts.keys}",
      )
    }
    val pinned = Rewrites.nativePrebuilt(files.native)
    val pinnedBtapi = Rewrites.nativeBtapi(files.native)
    val archives = Rewrites.nativeArchives(files.native)

    val metadata = releases.associateWith { source.nativeRelease(it, konanHosts.keys) }
    val problems = mutableListOf<String>()
    for ((release, data) in metadata) {
      for ((host, sha256) in pinned[release].orEmpty()) {
        val published = data.prebuiltSha256[host]
        if (published != sha256) {
          problems += "KOTLIN_NATIVE_PREBUILT pins $sha256 for $release $host, " +
            "the release publishes $published"
        }
      }
      pinnedBtapi[release]?.let {
        if (it != data.btapiSha256) {
          problems += "KOTLIN_NATIVE_BTAPI pins $it for $release, published: ${data.btapiSha256}"
        }
      }
    }
    if (metadata.getValue(default).btapiSha256 == null) {
      problems += "Kotlin/Native $default publishes no Build Tools API"
    }
    fail(problems)

    // Each distribution is a large download: read them in parallel.
    val pool = Executors.newFixedThreadPool(metadata.size * konanHosts.size)
    val properties =
      try {
        metadata
          .mapValues { (release, data) ->
            konanHosts.keys.associateWith { host ->
              CompletableFuture.supplyAsync({
                source.konanProperties(release, host, data.prebuiltSha256.getValue(host))
              }, pool)
            }
          }.mapValues { (_, hosts) -> hosts.mapValues { KonanProperties.parse(await(it.value)) } }
      } finally {
        pool.shutdownNow()
      }
    val llvm =
      properties.mapValues { (_, hosts) ->
        hosts.mapValues { (host, props) -> props.userLlvm(konanHosts.getValue(host)) }
      }
    for ((release, hosts) in properties) {
      for ((host, props) in hosts) {
        val hostDeps = deps.getValue(host)
        for ((target, targetDeps) in hostDeps.targets) {
          val staged =
            (hostDeps.host + llvm.getValue(release).getValue(host) + targetDeps).sorted()
          val required = props.linkDependencies(konanHosts.getValue(host), target)
          (required - staged.toSet()).forEach {
            problems += "$release $host $target: konan.properties requires $it, which " +
              "KOTLIN_NATIVE_DEPS does not stage"
          }
          (staged - required.toSet()).forEach {
            problems += "$release $host $target: KOTLIN_NATIVE_DEPS stages $it, which " +
              "konan.properties does not require"
          }
        }
      }
    }
    if (problems.isNotEmpty()) {
      problems += "update KOTLIN_NATIVE_DEPS and KOTLIN_NATIVE_ARCHIVES of native_compiler.bzl " +
        "by hand; the tool does not rewrite them"
    }
    fail(problems)

    val newArchives = archives.filterKeys { !it.startsWith("llvm-") }.toMutableMap()
    for (name in llvm.values.flatMap { it.values }.toSortedSet()) {
      val path = Rewrites.llvmPath(name)
      val sha256 = source.dependencySha256(path)
      val existing = archives[name]
      if (existing != null && existing != NativeArchive(path, sha256)) {
        problems += "KOTLIN_NATIVE_ARCHIVES pins $existing for $name, published: $path $sha256"
      }
      newArchives[name] = NativeArchive(path, sha256)
    }
    val used = deps.values.flatMap { it.host + it.targets.values.flatten() }.toSet()
    for (name in newArchives.keys.filter { !it.startsWith("llvm-") }) {
      if (name !in used) {
        problems += "KOTLIN_NATIVE_ARCHIVES pins $name, which KOTLIN_NATIVE_DEPS does not use"
      }
    }
    fail(problems)

    val excerptHosts =
      deps.entries.associate { (host, hostDeps) ->
        konanHosts.getValue(host) to hostDeps.targets.keys.toList()
      }
    val excerpts =
      properties.mapValues { (_, hosts) -> hosts.mapValues { it.value.excerpt(excerptHosts) } }
    val btapi =
      metadata.entries
        .mapNotNull { (release, data) -> data.btapiSha256?.let { release to it } }
        .toMap()
    return NativePlan(
      files =
        mapOf(
          NATIVE to
            Rewrites.rewriteNative(
              files.native,
              default,
              metadata.mapValues { it.value.prebuiltSha256 },
              llvm,
              btapi,
              newArchives,
            ),
          KONAN_TESTDATA to Rewrites.rewriteKonanTestdata(files.read(KONAN_TESTDATA), excerpts),
        ),
      releases = metadata,
    )
  }

  /**
   * The Maven lock files that pin `org.jetbrains.kotlin` artifacts, as `<module directory>
   * <repository>` lines: `REPIN=1 bazel run @<repository>//:pin` in the directory moves them to
   * the artifacts [plan] wrote.
   */
  fun repins(): List<String> {
    val files = Checkout(workspace)
    return files.kotlinModules().flatMap { module ->
      Rewrites.lockedKotlinRepositories(files.read(module)).map {
        "${module.removeSuffix("/$MODULE_BAZEL")} $it"
      }
    }
  }

  /**
   * The root MODULE.bazel snippet that selects [version], with every checksum. A release this
   * checkout pins must match the published checksums.
   */
  fun overrides(version: String): String {
    checkRelease(version)
    val files = Checkout(workspace)
    val hosts = Rewrites.konanHosts(files.targets).keys
    val release = source.release(version, hosts)
    val problems = mutableListOf<String>()
    if (Rewrites.currentRelease(files.versions) == version) {
      val pins = Rewrites.currentPins(files.versions)
      if (pins.copy(nativePrebuiltSha256 = release.nativePrebuiltSha256) != release) {
        problems += "versions.bzl pins other checksums for $version than the release publishes"
      }
    }
    Rewrites.nativePrebuilt(files.native)[version]?.let {
      if (it != release.nativePrebuiltSha256) {
        problems += "KOTLIN_NATIVE_PREBUILT pins $it for $version, published: " +
          "${release.nativePrebuiltSha256}"
      }
    }
    fail(problems)
    return overridesSnippet(release)
  }

  /**
   * Writes [changes] as one unit: the new content and a backup of each file are staged next to it,
   * then each file is replaced atomically. On a failure the files already replaced are restored;
   * only the backup of a file that could not be restored is left behind.
   */
  fun write(changes: Map<String, String>) {
    val temporaries = mutableListOf<Path>()
    val staged = mutableListOf<Staged>()
    try {
      for ((path, content) in changes.toSortedMap()) {
        val file = workspace.resolve(path)
        val update = stage(file, content.toByteArray(Charsets.UTF_8)).also(temporaries::add)
        val backup = stage(file, Files.readAllBytes(file)).also(temporaries::add)
        staged += Staged(path, file, update, backup)
      }
    } catch (e: Exception) {
      temporaries.forEach(::deleteQuietly)
      throw UpgradeException("cannot stage the changes next to their files: ${describe(e)}")
    }

    val replaced = mutableListOf<Staged>()
    for (change in staged) {
      try {
        replacer.replace(change.update, change.file)
        replaced += change
      } catch (e: Exception) {
        val unrestored =
          replaced.asReversed().filter { done ->
            try {
              replacer.replace(done.backup, done.file)
              false
            } catch (restoreFailure: Exception) {
              true
            }
          }
        val kept = unrestored.map { it.backup }.toSet()
        temporaries.filter { it !in kept }.forEach(::deleteQuietly)
        val failure = "cannot replace ${change.path}: ${describe(e)}"
        if (unrestored.isEmpty()) {
          throw UpgradeException("$failure; the files already replaced were restored")
        }
        throw UpgradeException(
          "$failure; could not restore " +
            unrestored
              .sortedBy {
                it.path
              }.joinToString { "${it.path} (original at ${it.backup})" },
          partial = true,
        )
      }
    }
    staged.forEach { deleteQuietly(it.backup) }
  }

  /** Replaceable so that tests can make [write] fail midway. */
  fun interface FileReplacer {
    @Throws(IOException::class)
    fun replace(
      staged: Path,
      file: Path,
    )

    companion object {
      val ATOMIC =
        FileReplacer { staged, file ->
          Files.move(
            staged,
            file,
            StandardCopyOption.REPLACE_EXISTING,
            StandardCopyOption.ATOMIC_MOVE,
          )
        }
    }
  }

  private class Staged(
    val path: String,
    val file: Path,
    val update: Path,
    val backup: Path,
  )

  private class Checkout(
    private val workspace: Path,
  ) {
    val versions = read(VERSIONS)
    val native = read(NATIVE)
    val targets = read(TARGETS)

    /**
     * The `examples/<name>/MODULE.bazel` files that pin an `org.jetbrains.kotlin` artifact. They
     * are found, not listed, so that an example that adds one follows the release too.
     */
    fun kotlinModules(): List<String> {
      val examples = workspace.resolve(EXAMPLES)
      val modules =
        try {
          Files.list(examples).use { entries ->
            entries
              .map { "$EXAMPLES/${it.fileName}/$MODULE_BAZEL" }
              .filter { Files.isRegularFile(workspace.resolve(it)) }
              .sorted()
              .toList()
          }
        } catch (e: IOException) {
          throw UpgradeException("cannot list $examples: ${describe(e)}")
        }.filter { Rewrites.kotlinArtifacts(read(it)).isNotEmpty() }
      if (modules.isEmpty()) {
        throw UpgradeException("$EXAMPLES: no $MODULE_BAZEL pins an org.jetbrains.kotlin artifact")
      }
      return modules
    }

    fun read(path: String): String {
      val file = workspace.resolve(path)
      if (!Files.isRegularFile(file)) {
        throw UpgradeException("$file does not exist: run the tool in a rules_kotlin checkout")
      }
      return try {
        Files.readString(file)
      } catch (e: IOException) {
        throw UpgradeException("cannot read $file: ${describe(e)}")
      }
    }
  }

  companion object {
    const val VERSIONS = "src/main/starlark/core/repositories/versions.bzl"
    const val NATIVE = "src/main/starlark/core/repositories/native_compiler.bzl"
    const val TARGETS = "kotlin/internal/native/targets.bzl"
    const val KONAN_TESTDATA = "src/test/starlark/native_konan_properties.bzl"
    const val TOOLCHAINS = "kotlin/internal/toolchains.bzl"
    const val KOTLINC_OPTIONS_TEST = "src/test/starlark/internal/jvm/kotlinc_options_test.bzl"
    const val EXAMPLES = "examples"
    const val MODULE_BAZEL = "MODULE.bazel"
    const val KMP_DOC = "docs/kmp.md"

    private const val BZLMOD_SETUP =
      "@rules_kotlin//src/main/starlark/core/repositories:bzlmod_setup.bzl"
    private const val NATIVE_EXTENSION =
      "@rules_kotlin//src/main/starlark/core/repositories:native.bzl"

    private fun checkRelease(version: String) {
      if (!Rewrites.isRelease(version)) throw UpgradeException("$version is not a Kotlin release")
    }

    /** The default Kotlin/Native release needs a Build Tools API: the launcher compiles with it. */
    private fun checkNativeDefault(version: String) {
      if (!KotlinRelease.hasNativeBtapi(version)) {
        throw UpgradeException(
          "Kotlin/Native $version has no Build Tools API, which rules_kotlin compiles klibs " +
            "with: the default Kotlin/Native release must be ${KotlinRelease.FIRST_NATIVE_BTAPI} " +
            "or newer; keep $version with --keep instead",
        )
      }
    }

    private fun <T> await(future: CompletableFuture<T>): T =
      try {
        future.get()
      } catch (e: ExecutionException) {
        throw e.cause ?: e
      }

    /** A temporary file next to [file] with [content] and the permissions of [file]. */
    private fun stage(
      file: Path,
      content: ByteArray,
    ): Path {
      val temporary = Files.createTempFile(file.parent, ".${file.fileName}.", ".tmp")
      try {
        Files.write(temporary, content)
        if (Files.getFileStore(file).supportsFileAttributeView("posix")) {
          Files.setPosixFilePermissions(temporary, Files.getPosixFilePermissions(file))
        }
      } catch (e: Exception) {
        deleteQuietly(temporary)
        throw e
      }
      return temporary
    }

    private fun deleteQuietly(file: Path) {
      try {
        Files.deleteIfExists(file)
      } catch (ignored: IOException) {
        // A leftover temporary file next to a written file is harmless.
      }
    }

    internal fun describe(e: Exception): String =
      listOfNotNull(e::class.simpleName, e.message).joinToString(": ")

    private fun fail(problems: List<String>) {
      if (problems.isNotEmpty()) throw UpgradeException(problems.joinToString("\n"))
    }

    fun overridesSnippet(release: KotlinRelease): String {
      val v = release.version
      val btapi =
        KotlinRelease.BTAPI_IMPL_ARTIFACTS.keys.joinToString("") {
          "    ${it}_sha256 = \"${release.btapiImplSha256.getValue(it)}\",\n"
        }
      val native =
        release.nativePrebuiltSha256.toSortedMap().entries.joinToString("") { (host, sha256) ->
          "        \"$host\": \"$sha256\",\n"
        }
      return """
        |# Kotlin $v: the JVM compiler, the Build Tools API implementation and Kotlin/Native.
        |# Generated by `scripts/upgrade_kotlin.sh`.
        |kotlin_release = use_extension("$BZLMOD_SETUP", "rules_kotlin_extensions")
        |kotlin_release.kotlinc_version(
        |    sha256 = "${release.compilerSha256}",
        |    version = "$v",
        |)
        |kotlin_release.btapi_impl_version(
        |    name = "btapi_impl",
        |    version = "$v",
        |${btapi.trimEnd('\n')}
        |)
        |
        |kotlin_native_release = use_extension("$NATIVE_EXTENSION", "kotlin_native")
        |kotlin_native_release.version(
        |    sha256 = {
        |${native.trimEnd('\n')}
        |    },
        |    version = "$v",
        |)
        |
        """.trimMargin()
    }

    /** @param nativePinned whether the Kotlin/Native tables pin [release]. */
    private fun docSection(
      current: String,
      release: KotlinRelease,
      nativePinned: Boolean,
    ): String {
      val currentLevel = Rewrites.languageLevel(current)
      val level = Rewrites.languageLevel(release.version)
      val pins =
        if (nativePinned) {
          "rules_kotlin pins the Kotlin/Native distributions and\n|the LLVM of ${release.version}."
        } else {
          "rules_kotlin does not pin the Kotlin/Native\n|distributions of ${release.version}, " +
            "whose checksums the snippet gives, nor its LLVM."
        }
      return """
        |### Staying on Kotlin ${release.version}
        |
        |rules_kotlin defaults to Kotlin $current. A root module that stays on Kotlin
        |${release.version} selects it for the JVM compiler, the Build Tools API implementation and
        |Kotlin/Native in its `MODULE.bazel`; $pins
        |
        |```starlark
        |${overridesSnippet(release).trimEnd('\n')}
        |```
        |
        |A toolchain that sets no `api_version` or `language_version`, such as the default one, then
        |compiles at version $level, the one of Kotlin ${release.version}, instead of $currentLevel,
        |which that compiler treats as experimental. A toolchain that sets them keeps its values.
        |
        |The Build Tools API jar stays the one of $current: the worker of rules_kotlin is compiled
        |against it, and it runs implementations from three version lines back, so the
        |`btapi_impl` record above runs the compiler of ${release.version}.
        |
        """.trimMargin()
    }

    private fun nativeDocSection(
      default: String,
      release: NativeRelease,
    ): String {
      val v = release.version
      val compilation =
        if (release.btapiSha256 != null) {
          "Its klibs compile with its Kotlin/Native Build Tools API, as those of $default do."
        } else {
          "It has no Kotlin/Native Build Tools API: its klibs compile with the konanc command\n" +
            "|line, whatever `experimental_native_build_tools_api` says."
        }
      return """
        |### Staying on Kotlin/Native $v
        |
        |rules_kotlin defaults to Kotlin/Native $default. A root module that stays on Kotlin/Native
        |$v selects it in its `MODULE.bazel`; rules_kotlin pins the distributions and the LLVM of
        |$v, so the tag needs no checksums.
        |
        |```starlark
        |kotlin_native = use_extension("$NATIVE_EXTENSION", "kotlin_native")
        |kotlin_native.version(version = "$v")
        |```
        |
        |$compilation
        |
        """.trimMargin()
    }
  }
}
