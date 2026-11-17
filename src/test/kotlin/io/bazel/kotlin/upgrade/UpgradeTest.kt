package io.bazel.kotlin.upgrade

import com.google.common.truth.Truth.assertThat
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.IOException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.attribute.PosixFilePermissions

/**
 * Runs the upgrade on a copy of the files of this checkout, with release metadata derived from
 * its own pins plus fake releases, so the anchors are checked against the real files.
 */
class UpgradeTest {
  private val checkout = TestCheckout()
  private val source = FakeSource.of(checkout)
  private val upgrade = Upgrade(checkout.root, source)
  private val current = Rewrites.currentRelease(checkout.read(Upgrade.VERSIONS))
  private val pinned = Rewrites.nativePrebuilt(checkout.read(Upgrade.NATIVE)).keys

  @Test
  fun `given this checkout when upgraded to its own releases then nothing changes`() {
    // The doc is a fixture without the sections of the older releases of this checkout.
    assertThat(upgrade.plan(current, (pinned - current).toList()).keys - Upgrade.KMP_DOC).isEmpty()
  }

  @Test
  fun `given a minor release when upgraded then every pin moves and the current one is kept`() {
    val release = source.fakeRelease("9.1.0", base = current)
    val oldToolchains = checkout.read(Upgrade.TOOLCHAINS)

    val changes = upgrade.plan("9.1.0")
    assertThat(changes.keys).containsAtLeast(
      Upgrade.VERSIONS,
      Upgrade.NATIVE,
      Upgrade.KONAN_TESTDATA,
      Upgrade.TOOLCHAINS,
      Upgrade.KOTLINC_OPTIONS_TEST,
      TestCheckout.COMPOSE_MODULE,
      TestCheckout.DAGGER_MODULE,
      Upgrade.KMP_DOC,
    )
    upgrade.write(changes)

    val versions = checkout.read(Upgrade.VERSIONS)
    assertThat(Rewrites.currentRelease(versions)).isEqualTo("9.1.0")
    assertThat(Rewrites.currentPins(versions))
      .isEqualTo(release.copy(nativePrebuiltSha256 = emptyMap()))
    val native = checkout.read(Upgrade.NATIVE)
    assertThat(Rewrites.nativePrebuilt(native).keys).containsExactly(current, "9.1.0")
    assertThat(Rewrites.nativePrebuilt(native)["9.1.0"]).isEqualTo(release.nativePrebuiltSha256)
    assertThat(Rewrites.nativeLlvm(native).keys).containsExactly(current, "9.1.0")
    assertThat(checkout.read(Upgrade.KONAN_TESTDATA)).contains("    \"9.1.0\": {\n")

    val toolchains = checkout.read(Upgrade.TOOLCHAINS)
    // api_version and language_version of _kt_toolchain.
    assertThat(toolchains.lines().count { it.trim() == "default = \"9.1\"," }).isEqualTo(2)
    assertThat(toolchains.lines().count { it.trim() == "\"9.1\"," }).isEqualTo(2)
    assertThat(toolchains.lines())
      .containsAtLeastElementsIn(oldToolchains.lines().filterNot { "default = " in it })
    assertThat(checkout.read(Upgrade.KOTLINC_OPTIONS_TEST).split("expected = \"9.1\"")).hasSize(3)
    assertThat(checkout.read(TestCheckout.COMPOSE_MODULE))
      .contains("\"org.jetbrains.kotlin:kotlin-compose-compiler-plugin-embeddable:9.1.0\"")
    val dagger = checkout.read(TestCheckout.DAGGER_MODULE)
    assertThat(Rewrites.kotlinArtifacts(dagger))
      .containsExactly("kotlin-metadata-jvm" to "9.1.0", "kotlin-reflect" to "9.1.0")
    assertThat(dagger).contains("\"org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2\"")
    val doc = checkout.read(Upgrade.KMP_DOC)
    assertThat(doc).contains("### Staying on Kotlin $current\n")
    assertThat(doc).contains(Upgrade.overridesSnippet(source.releases.getValue(current)))
    assertThat(checkout.unchanged()).containsExactly(Upgrade.TARGETS)
    assertThat(changes.keys.filter { "capabilities_" in it }).isEmpty()

    assertThat(upgrade.plan("9.1.0", listOf(current))).isEmpty()
  }

  @Test
  fun `given a patch release when upgraded then the kept set is pruned but no enum changes`() {
    source.fakeRelease("9.1.0", base = current)
    source.fakeRelease("9.1.1", base = current)
    upgrade.write(upgrade.plan("9.1.0"))
    val toolchains = checkout.read(Upgrade.TOOLCHAINS)

    val changes = upgrade.plan("9.1.1", listOf("9.1.0"))
    assertThat(changes.keys).containsNoneOf(Upgrade.TOOLCHAINS, Upgrade.KOTLINC_OPTIONS_TEST)
    upgrade.write(changes)

    val native = checkout.read(Upgrade.NATIVE)
    assertThat(Rewrites.nativePrebuilt(native).keys).containsExactly("9.1.0", "9.1.1")
    assertThat(Rewrites.nativeLlvm(native).keys).containsExactly("9.1.0", "9.1.1")
    val testdata = checkout.read(Upgrade.KONAN_TESTDATA)
    assertThat(testdata).doesNotContain("    \"$current\": {\n")
    assertThat(checkout.read(Upgrade.TOOLCHAINS)).isEqualTo(toolchains)
    val doc = checkout.read(Upgrade.KMP_DOC)
    assertThat(doc).contains("### Staying on Kotlin 9.1.0\n")
    assertThat(doc).doesNotContain("### Staying on Kotlin $current\n")
    assertThat(checkout.unchanged()).containsExactly(Upgrade.TARGETS)
  }

  @Test
  fun `given pins already upgraded when an example lags behind then it still moves`() {
    source.fakeRelease("9.1.0", base = current)
    upgrade.write(upgrade.plan("9.1.0"))
    val behind = checkout.read(TestCheckout.DAGGER_MODULE)
    Files.writeString(
      checkout.root.resolve(TestCheckout.DAGGER_MODULE),
      Rewrites.rewriteKotlinArtifacts(behind, current),
    )

    val changes = upgrade.plan("9.1.0", listOf(current))
    assertThat(changes.keys).containsExactly(TestCheckout.DAGGER_MODULE)
    assertThat(changes.getValue(TestCheckout.DAGGER_MODULE)).isEqualTo(behind)
  }

  @Test
  fun `given Kotlin artifacts in examples when upgraded then their lock files are listed`() {
    source.fakeRelease("9.1.0", base = current)
    val expected =
      listOf(
        "examples/dagger maven_rules_kotlin_example",
        "examples/jetpack_compose maven_rules_kotlin_example",
      )

    assertThat(UpgradeKotlin.run(UpgradeKotlin.Options(version = "9.1.0"), upgrade) {}.lines())
      .containsExactlyElementsIn(expected + "")
      .inOrder()
    // Also when the pins are up to date, so that a rerun repins lock files a failed run left.
    assertThat(UpgradeKotlin.run(UpgradeKotlin.Options(version = "9.1.0"), upgrade) {}.lines())
      .containsExactlyElementsIn(expected + "")
      .inOrder()
    assertThat(
      UpgradeKotlin.run(UpgradeKotlin.Options(version = "9.1.0", dryRun = true), upgrade) {},
    ).isEmpty()
  }

  @Test
  fun `given maven installs when read then only locked ones with Kotlin artifacts are repinned`() {
    val module =
      """
      |maven.install(
      |    artifacts = ["org.jetbrains.kotlin:kotlin-stdlib:2.4.21"],
      |    lock_file = "//:maven_install.json",
      |)
      |maven.install(
      |    name = "other",
      |    artifacts = ["org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2"],
      |    lock_file = "//:other_install.json",
      |)
      |maven.install(
      |    name = "unlocked",
      |    artifacts = ["org.jetbrains.kotlin:kotlin-reflect:2.4.21"],
      |)
      |
      """.trimMargin()

    assertThat(Rewrites.lockedKotlinRepositories(module)).containsExactly("maven")
    assertThat(Rewrites.rewriteKotlinArtifacts(module, "9.1.0"))
      .isEqualTo(module.replace(":2.4.21\"", ":9.1.0\""))
  }

  @Test
  fun `given no example with Kotlin artifacts when upgraded then nothing is written`() {
    source.fakeRelease("9.1.0", base = current)
    for (module in listOf(TestCheckout.COMPOSE_MODULE, TestCheckout.DAGGER_MODULE)) {
      Files.delete(checkout.root.resolve(module))
    }

    assertThat(assertThrows(UpgradeException::class.java) { upgrade.plan("9.1.0") })
      .hasMessageThat()
      .isEqualTo("examples: no MODULE.bazel pins an org.jetbrains.kotlin artifact")
  }

  @Test
  fun `given another LLVM when upgraded then its archives are pinned and old ones pruned`() {
    val oldLlvm = Rewrites.nativeLlvm(checkout.read(Upgrade.NATIVE)).getValue(current).values
    source.fakeRelease("9.2.0", base = current, newLlvm = true)
    source.fakeRelease("9.2.1", base = current, newLlvm = true)

    upgrade.write(upgrade.plan("9.2.0"))
    var archives = Rewrites.nativeArchives(checkout.read(Upgrade.NATIVE))
    val newLlvm = Rewrites.nativeLlvm(checkout.read(Upgrade.NATIVE)).getValue("9.2.0").values
    assertThat(newLlvm.intersect(oldLlvm.toSet())).isEmpty()
    assertThat(archives.keys).containsAtLeastElementsIn(oldLlvm + newLlvm)
    for (name in newLlvm) {
      assertThat(archives.getValue(name).path).isEqualTo(Rewrites.llvmPath(name))
      assertThat(archives.getValue(name).path).startsWith("resources/llvm/99-")
    }

    upgrade.write(upgrade.plan("9.2.1", listOf("9.2.0")))
    archives = Rewrites.nativeArchives(checkout.read(Upgrade.NATIVE))
    assertThat(archives.keys).containsAtLeastElementsIn(newLlvm)
    assertThat(archives.keys).containsNoneIn(oldLlvm)
  }

  @Test
  fun `given KOTLIN_NATIVE_DEPS drift when upgraded then nothing is written`() {
    val drift = "dependencies.macos_arm64 = lldb-4-macos lldb-99-macos\n"
    source.fakeRelease("9.3.0", base = current) { host, text ->
      if (host == "macos-aarch64") text + drift else text
    }
    val before = checkout.snapshot()

    val error =
      assertThrows(UpgradeException::class.java) {
        UpgradeKotlin.run(UpgradeKotlin.Options(version = "9.3.0"), upgrade) {}
      }
    assertThat(error).hasMessageThat().contains("konan.properties requires lldb-99-macos")
    assertThat(error).hasMessageThat().contains("update KOTLIN_NATIVE_DEPS")
    assertThat(checkout.snapshot()).isEqualTo(before)
  }

  @Test
  fun `given a missing artifact when upgraded then nothing is written`() {
    val before = checkout.snapshot()
    assertThat(
      assertThrows(UpgradeException::class.java) {
        UpgradeKotlin.run(UpgradeKotlin.Options(version = "9.4.0"), upgrade) {}
      },
    ).hasMessageThat().contains("release v9.4.0 has no asset")

    source.fakeRelease("9.4.0", base = current, newLlvm = true)
    source.dependencies.keys.removeIf { "/99-" in it }
    assertThat(
      assertThrows(UpgradeException::class.java) {
        UpgradeKotlin.run(UpgradeKotlin.Options(version = "9.4.0"), upgrade) {}
      },
    ).hasMessageThat().contains("HTTP 404")
    assertThat(checkout.snapshot()).isEqualTo(before)
  }

  @Test
  fun `given a kept release published with another checksum when upgraded then it fails`() {
    source.fakeRelease("9.5.0", base = current)
    val release = source.releases.getValue(current)
    val host = release.nativePrebuiltSha256.keys.first()
    source.releases[current] =
      release.copy(nativePrebuiltSha256 = release.nativePrebuiltSha256 + (host to "0".repeat(64)))

    assertThat(assertThrows(UpgradeException::class.java) { upgrade.plan("9.5.0") })
      .hasMessageThat()
      .contains("KOTLIN_NATIVE_PREBUILT pins")
  }

  @Test
  fun `given a dry run when upgraded then the changes are listed and nothing is written`() {
    source.fakeRelease("9.6.0", base = current)
    val before = checkout.snapshot()
    val log = mutableListOf<String>()

    UpgradeKotlin.run(
      UpgradeKotlin.Options(version = "9.6.0", dryRun = true),
      upgrade,
    ) { log += it }

    assertThat(log).contains("would change ${Upgrade.VERSIONS}")
    assertThat(checkout.snapshot()).isEqualTo(before)
  }

  @Test
  fun `given a pinned release when emitting overrides then every pinned checksum is in it`() {
    val pins = Rewrites.currentPins(checkout.read(Upgrade.VERSIONS))
    val native = Rewrites.nativePrebuilt(checkout.read(Upgrade.NATIVE)).getValue(current)

    val snippet = UpgradeKotlin.run(UpgradeKotlin.Options(emitOverrides = current), upgrade) {}

    assertThat(snippet).contains(
      "kotlin_release.kotlinc_version(\n    sha256 = \"${pins.compilerSha256}\",\n" +
        "    version = \"$current\",\n)\n",
    )
    assertThat(snippet).contains("kotlin_release.btapi_impl_version(\n    name = \"btapi_impl\",\n")
    for ((field, sha256) in pins.btapiImplSha256) {
      assertThat(snippet).contains("    ${field}_sha256 = \"$sha256\",\n")
    }
    for ((host, sha256) in native) {
      assertThat(snippet).contains("        \"$host\": \"$sha256\",\n")
    }
    assertThat(snippet).contains("kotlin_native_release.version(\n")
    assertThat(snippet.lines().count { "use_extension(" in it }).isEqualTo(2)
    // The toolchains follow the configured compiler: the overrides register none.
    assertThat(snippet).doesNotContain("register_toolchains")
  }

  @Test
  fun `given a kept release when upgraded then its doc section names its language level`() {
    source.fakeRelease("9.1.0", base = current)
    upgrade.write(upgrade.plan("9.1.0"))

    val doc = checkout.read(Upgrade.KMP_DOC)
    val level = Rewrites.languageLevel(current)
    assertThat(doc).contains("```starlark\n${upgrade.overrides(current)}```\n")
    assertThat(doc)
      .contains("compiles at version $level, the one of Kotlin $current, instead of 9.1,")
    assertThat(doc).doesNotContain("register_toolchains")
    assertThat(upgrade.plan("9.1.0", listOf(current))).isEmpty()
  }

  @Test
  fun `given a release published with other checksums when emitting overrides then it fails`() {
    val release = source.releases.getValue(current)
    source.releases[current] = release.copy(compilerSha256 = "0".repeat(64))

    assertThat(assertThrows(UpgradeException::class.java) { upgrade.overrides(current) })
      .hasMessageThat()
      .contains("versions.bzl pins other checksums")
  }

  @Test
  fun `given command lines when parsed then only the contract flags are accepted`() {
    assertThat(
      UpgradeKotlin.Options.parse(
        listOf("--version", "9.1.0", "--keep", "2.4.21", "--keep", "2.4.20"),
      ),
    ).isEqualTo(UpgradeKotlin.Options(version = "9.1.0", keep = listOf("2.4.21", "2.4.20")))
    assertThat(
      UpgradeKotlin.Options.parse(listOf("--dry-run", "--version", "9.1.0")).dryRun,
    ).isTrue()
    assertThat(UpgradeKotlin.Options.parse(listOf("--emit-overrides", "2.4.21")).emitOverrides)
      .isEqualTo("2.4.21")
    for (
    args in listOf(
      emptyList(),
      listOf("--version"),
      listOf("--version", "--dry-run"),
      listOf("--version", "9.1.0", "--emit-overrides", "2.4.21"),
      listOf("--emit-overrides", "2.4.21", "--keep", "2.4.20"),
      listOf("--emit-toolchain", "2.4.21"),
      listOf("--version", "9.1.0", "--ksp-version", "2.3.14"),
    )
    ) {
      assertThrows(
        args.toString(),
        UpgradeException::class.java,
      ) { UpgradeKotlin.Options.parse(args) }
    }
    assertThrows(UpgradeException::class.java) { upgrade.plan("latest") }
  }

  @Test
  fun `given a write when it succeeds then no staged file is left and permissions are kept`() {
    source.fakeRelease("9.7.0", base = current)
    val changes = upgrade.plan("9.7.0")
    val toolchains = checkout.root.resolve(Upgrade.TOOLCHAINS)
    Files.setPosixFilePermissions(toolchains, PosixFilePermissions.fromString("rwxr-x---"))

    upgrade.write(changes)

    changes.forEach { (path, content) -> assertThat(checkout.read(path)).isEqualTo(content) }
    assertThat(PosixFilePermissions.toString(Files.getPosixFilePermissions(toolchains)))
      .isEqualTo("rwxr-x---")
    assertThat(checkout.temporaries()).isEmpty()
  }

  @Test
  fun `given a replacement failing midway when written then the replaced files are restored`() {
    source.fakeRelease("9.7.0", base = current)
    val changes = upgrade.plan("9.7.0")
    val before = checkout.snapshot()
    var calls = 0
    val failing =
      Upgrade(checkout.root, source) { staged, file ->
        if (++calls == 3) throw IOException("disk full")
        Upgrade.FileReplacer.ATOMIC.replace(staged, file)
      }

    val error = assertThrows(UpgradeException::class.java) { failing.write(changes) }
    assertThat(error).hasMessageThat().isEqualTo(
      "cannot replace ${changes.keys.sorted()[2]}: IOException: disk full; " +
        "the files already replaced were restored",
    )
    assertThat(error.partial).isFalse()
    // Two replacements, the failed one, and the two restorations.
    assertThat(calls).isEqualTo(5)
    assertThat(checkout.snapshot()).isEqualTo(before)
    assertThat(checkout.temporaries()).isEmpty()
  }

  @Test
  fun `given a restoration failing too when written then the error names the backups`() {
    source.fakeRelease("9.7.0", base = current)
    val changes = upgrade.plan("9.7.0")
    val before = checkout.snapshot()
    var calls = 0
    val failing =
      Upgrade(checkout.root, source) { staged, file ->
        if (++calls >= 3) throw IOException("disk full")
        Upgrade.FileReplacer.ATOMIC.replace(staged, file)
      }

    val error = assertThrows(UpgradeException::class.java) { failing.write(changes) }
    val replaced = changes.keys.sorted().take(2)
    assertThat(error.partial).isTrue()
    assertThat(error).hasMessageThat().contains("; could not restore ${replaced[0]} (original at ")
    assertThat(error).hasMessageThat().contains(", ${replaced[1]} (original at ")
    replaced.forEach { assertThat(checkout.read(it)).isEqualTo(changes[it]) }
    // Only the backups of the two files are left, next to them.
    val backups = checkout.temporaries()
    assertThat(
      backups.map {
        Files.readString(it)
      },
    ).containsExactlyElementsIn(replaced.map(before::get))
    backups.forEach { assertThat(error).hasMessageThat().contains("$it") }
    assertThat(checkout.unchanged()).containsAtLeastElementsIn(changes.keys - replaced.toSet())
  }

  @Test
  fun `given a file that cannot be staged when written then nothing is written`() {
    source.fakeRelease("9.7.0", base = current)
    val changes = upgrade.plan("9.7.0")
    val before = checkout.snapshot()
    // The last file staged: the others are staged before it, and must be cleaned up.
    val directory = checkout.root.resolve(changes.keys.max()).parent
    assertThat(changes.keys.count { checkout.root.resolve(it).parent == directory }).isEqualTo(1)
    Files.setPosixFilePermissions(directory, PosixFilePermissions.fromString("r-xr-xr-x"))
    try {
      assertThat(assertThrows(UpgradeException::class.java) { upgrade.write(changes) })
        .hasMessageThat()
        .startsWith("cannot stage the changes next to their files: AccessDeniedException")
    } finally {
      Files.setPosixFilePermissions(directory, PosixFilePermissions.fromString("rwxr-xr-x"))
    }
    assertThat(checkout.snapshot()).isEqualTo(before)
    assertThat(checkout.temporaries()).isEmpty()
  }
}

/** A temporary copy of the files of this checkout the tool reads and writes. */
class TestCheckout {
  val root: Path = Files.createTempDirectory("upgrade_kotlin")
  private val original: Map<String, String>

  init {
    for (path in FILES) {
      val file = root.resolve(path)
      Files.createDirectories(file.parent)
      Files.writeString(file, Files.readString(runfile(COPIES[path] ?: path)))
    }
    // The fixtures follow the release of the checkout, as the examples do.
    val current = Rewrites.currentRelease(read(Upgrade.VERSIONS))
    for (module in listOf(COMPOSE_MODULE, DAGGER_MODULE)) {
      Files.writeString(
        root.resolve(module),
        Rewrites.rewriteKotlinArtifacts(read(module), current),
      )
    }
    original = snapshot()
  }

  fun read(path: String): String = Files.readString(root.resolve(path))

  fun snapshot(): Map<String, String> = FILES.associateWith(::read)

  /** The files still equal to their original. */
  fun unchanged(): List<String> = FILES.filter { read(it) == original[it] }

  /** The temporary files under the checkout. */
  fun temporaries(): List<Path> =
    Files.walk(root).use { files ->
      files.filter { "${it.fileName}".endsWith(".tmp") }.sorted().toList()
    }

  companion object {
    const val COMPOSE_MODULE = "examples/jetpack_compose/MODULE.bazel"
    const val DAGGER_MODULE = "examples/dagger/MODULE.bazel"

    /**
     * The files a fixture stands in for: the examples are packages of their own, and docs/kmp.md
     * is also the name of a stardoc output.
     */
    private val COPIES =
      mapOf(
        COMPOSE_MODULE to "$TESTDATA/jetpack_compose_MODULE.bazel.txt",
        DAGGER_MODULE to "$TESTDATA/dagger_MODULE.bazel.txt",
        Upgrade.KMP_DOC to "$TESTDATA/kmp.md",
      )

    private const val TESTDATA = "src/test/kotlin/io/bazel/kotlin/upgrade/testdata"

    val FILES =
      listOf(
        Upgrade.VERSIONS,
        Upgrade.NATIVE,
        Upgrade.TARGETS,
        Upgrade.KONAN_TESTDATA,
        Upgrade.TOOLCHAINS,
        Upgrade.KOTLINC_OPTIONS_TEST,
        COMPOSE_MODULE,
        DAGGER_MODULE,
        Upgrade.KMP_DOC,
      )

    private fun runfile(path: String): Path =
      Paths.get(System.getenv("TEST_SRCDIR"), System.getenv("TEST_WORKSPACE"), path)
  }
}

/** Release metadata in memory: the releases a checkout pins, and fake ones. */
class FakeSource : ReleaseSource {
  val releases = mutableMapOf<String, KotlinRelease>()
  val konan = mutableMapOf<String, Map<String, String>>()
  val dependencies = mutableMapOf<String, String>()

  override fun release(
    version: String,
    hosts: Collection<String>,
  ): KotlinRelease =
    releases[version]
      ?: throw UpgradeException(
        "release v$version has no asset ${KotlinRelease.compilerAsset(version)}",
      )

  override fun konanProperties(
    version: String,
    host: String,
    sha256: String,
  ): String {
    check(releases.getValue(version).nativePrebuiltSha256[host] == sha256)
    return konan.getValue(version).getValue(host)
  }

  override fun dependencySha256(path: String): String =
    dependencies[path] ?: throw UpgradeException("GET $path.sha256: HTTP 404")

  /**
   * Adds a release with fake checksums whose distributions are the ones of [base], with other user
   * LLVMs if [newLlvm], edited by [edit] (exec host, text).
   */
  fun fakeRelease(
    version: String,
    base: String,
    newLlvm: Boolean = false,
    edit: (String, String) -> String = { _, text -> text },
  ): KotlinRelease {
    val baseKonan = konan.getValue(base)
    val renames =
      if (!newLlvm) {
        emptyMap()
      } else {
        baseKonan.entries
          .associate { (host, text) ->
            val llvm = KonanProperties.parse(text).userLlvm(KONAN_HOSTS.getValue(host))
            llvm to llvm.replaceFirst(Regex("^llvm-\\d+-"), "llvm-99-")
          }
      }
    for (renamed in renames.values) {
      dependencies[Rewrites.llvmPath(renamed)] = fake("$renamed.tar.gz")
    }
    konan[version] =
      baseKonan.mapValues { (host, text) ->
        edit(host, renames.entries.fold(text) { acc, (from, to) -> acc.replace(from, to) })
      }
    val release =
      KotlinRelease(
        version = version,
        compilerSha256 = fake("$version/compiler"),
        buildToolsApiSha256 = fake("$version/build_tools_api"),
        btapiImplSha256 =
          KotlinRelease.BTAPI_IMPL_ARTIFACTS.keys.associateWith {
            fake(
              "$version/$it",
            )
          },
        nativePrebuiltSha256 = baseKonan.keys.associateWith { fake("$version/$it") },
      )
    releases[version] = release
    return release
  }

  companion object {
    private val KONAN_HOSTS = mapOf("linux-x86_64" to "linux_x64", "macos-aarch64" to "macos_arm64")

    private fun fake(name: String) = Checksums.sha256(name.toByteArray())

    /** The metadata of the releases [checkout] pins, as the checkout records it. */
    fun of(checkout: TestCheckout): FakeSource {
      val source = FakeSource()
      val versions = checkout.read(Upgrade.VERSIONS)
      val native = checkout.read(Upgrade.NATIVE)
      val current = Rewrites.currentRelease(versions)
      val documented = documentedReleases(checkout.read(Upgrade.KMP_DOC))
      for ((release, sha256) in Rewrites.nativePrebuilt(native)) {
        val jvm =
          when (release) {
            current -> {
              Rewrites.currentPins(versions)
            }

            else -> {
              documented[release]
                ?: KotlinRelease(
                  version = release,
                  compilerSha256 = fake("$release/compiler"),
                  buildToolsApiSha256 = fake("$release/build_tools_api"),
                  btapiImplSha256 =
                    KotlinRelease.BTAPI_IMPL_ARTIFACTS.keys.associateWith { fake("$release/$it") },
                  nativePrebuiltSha256 = emptyMap(),
                )
            }
          }
        source.releases[release] = jvm.copy(nativePrebuiltSha256 = sha256)
      }
      source.konan += konanTestdata(checkout.read(Upgrade.KONAN_TESTDATA))
      for (archive in Rewrites.nativeArchives(native).values) {
        source.dependencies[archive.path] = archive.sha256
      }
      return source
    }

    /** The JVM checksums of the older releases docs/kmp.md documents. */
    private fun documentedReleases(doc: String): Map<String, KotlinRelease> {
      val region = doc.substringAfter(Rewrites.DOC_BEGIN).substringBefore(Rewrites.DOC_END)
      return region.split("### Staying on Kotlin ").drop(1).associate { section ->
        val release = section.substringBefore('\n')
        val fields =
          Regex("^ {4}(\\w*?)_?sha256 = \"([0-9a-f]{64})\",$", RegexOption.MULTILINE)
            .findAll(section.substringBefore("kotlin_native_release"))
            .map { it.groupValues[1] to it.groupValues[2] }
            .toList()
        val compiler = fields.first { it.first == "" }.second
        release to
          KotlinRelease(
            version = release,
            compilerSha256 = compiler,
            buildToolsApiSha256 = fake("$release/build_tools_api"),
            btapiImplSha256 = fields.filter { it.first != "" }.toMap(),
            nativePrebuiltSha256 = emptyMap(),
          )
      }
    }

    /** KONAN_PROPERTIES of native_konan_properties.bzl: each release to each host's text. */
    private fun konanTestdata(testdata: String): Map<String, Map<String, String>> {
      val result = linkedMapOf<String, MutableMap<String, String>>()
      var release = ""
      var host: String? = null
      val text = StringBuilder()
      for (line in testdata.lines()) {
        val releaseMatch = Regex("^ {4}\"([^\"]+)\": \\{$").matchEntire(line)
        val hostMatch = Regex("^ {8}\"([^\"]+)\": \"\"\"\\\\$").matchEntire(line)
        when {
          host != null && line.startsWith("\"\"\"") -> {
            result.getOrPut(release, ::linkedMapOf)[host] = text.toString().replace("\\\\", "\\")
            host = null
          }

          host != null -> {
            text.append(line).append('\n')
          }

          releaseMatch != null -> {
            release = releaseMatch.groupValues[1]
          }

          hostMatch != null -> {
            host = hostMatch.groupValues[1]
            text.clear()
          }
        }
      }
      return result
    }
  }
}
