package io.bazel.kotlin.upgrade

import com.google.common.truth.Truth.assertThat
import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveOutputStream
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.nio.file.Files
import java.nio.file.Paths

class ParsersTest {
  private val hash = "687132a8ecf08bfd042c69fbe89fe120984abecb59e117dc20ec874eb4e2d644"

  @Test
  fun `given a bare or a named sha256 file when parsed then both give the hash`() {
    assertThat(Checksums.parseSidecar("$hash\n", "kotlin-compiler-9.1.0-RC.zip")).isEqualTo(hash)
    assertThat(Checksums.parseSidecar("$hash *llvm.tar.gz\n", "llvm.tar.gz")).isEqualTo(hash)
    assertThat(Checksums.parseSidecar("${hash.uppercase()}  llvm.tar.gz", "llvm.tar.gz"))
      .isEqualTo(hash)
  }

  @Test
  fun `given a sha256 file of another file or no hash when parsed then it fails`() {
    assertThrows(IllegalArgumentException::class.java) {
      Checksums.parseSidecar("$hash *other.tar.gz", "llvm.tar.gz")
    }
    assertThrows(IllegalArgumentException::class.java) { Checksums.parseSidecar("Not Found") }
    assertThrows(IllegalArgumentException::class.java) { Checksums.parseSidecar("") }
  }

  @Test
  fun `given a maven sha256 txt when parsed then it maps each path to its lowercase hash`() {
    val maven = Checksums.parseMavenSha256(testdata("maven-1.2.3-sha256.txt"))
    assertThat(maven).hasSize(4)
    assertThat(maven[KotlinRelease.mavenPath("kotlin-stdlib", "1.2.3")])
      .isEqualTo("aa94e6f417847322aa58d9fbec93278b74010f3cf593cf2038bd865e1ef42c3f")
    assertThrows(IllegalArgumentException::class.java) {
      Checksums.parseMavenSha256("org/x.jar not-a-hash")
    }
  }

  @Test
  fun `given a GitHub digest when parsed then only sha256 digests give a hash`() {
    assertThat(Checksums.parseDigest("sha256:$hash")).isEqualTo(hash)
    assertThat(Checksums.parseDigest("sha512:abc")).isNull()
    assertThat(Checksums.parseDigest(null)).isNull()
  }

  @Test
  fun `given konan properties when read then the LLVM and the link dependencies resolve`() {
    val properties = KonanProperties.parse(testdata("konan.properties"))
    assertThat(properties.userLlvm("macos_arm64")).isEqualTo("llvm-21-aarch64-macos-essentials-97")
    assertThat(properties.properties["dependencies.linux_x64"])
      .isEqualTo("\$toolchainDependency.linux_x64 lldb-4-linux")
    assertThat(properties.linkDependencies("macos_arm64", "macos_arm64"))
      .containsExactly(
        "libffi-3.3-1-macos-arm64",
        "lldb-4-macos",
        "llvm-21-aarch64-macos-essentials-97",
      ).inOrder()
    assertThat(properties.linkDependencies("macos_arm64", "linux_arm64"))
      .containsExactly(
        "aarch64-unknown-linux-gnu-gcc-8.3.0-glibc-2.25-kernel-4.9-2",
        "libffi-3.3-1-macos-arm64",
        "llvm-21-aarch64-macos-essentials-97",
      )
    assertThat(properties.linkDependencies("linux_x64", "linux_arm64"))
      .containsExactly(
        "aarch64-unknown-linux-gnu-gcc-8.3.0-glibc-2.25-kernel-4.9-2",
        "libffi-3.2.1-2-linux-x86-64",
        "llvm-21-x86_64-linux-dev-116",
        "qemu-aarch64-static-5.1.0-linux-2",
      )
    assertThat(properties.linkDependencies("macos_arm64", "ios_arm64"))
      .containsExactly("libffi-3.3-1-macos-arm64", "llvm-21-aarch64-macos-essentials-97")
  }

  @Test
  fun `given a distribution without its LLVM when read then it fails`() {
    assertThrows(UpgradeException::class.java) {
      KonanProperties.parse("llvmHome.macos_arm64 = x").userLlvm("macos_arm64")
    }
  }

  @Test
  fun `given konan properties when excerpted then only the linked entries stay and it is stable`() {
    val hosts =
      mapOf(
        "linux_x64" to listOf("linux_arm64", "linux_x64"),
        "macos_arm64" to listOf("ios_arm64", "linux_arm64", "linux_x64", "macos_arm64"),
      )
    val properties = KonanProperties.parse(testdata("konan.properties"))
    val excerpt = properties.excerpt(hosts)

    assertThat(excerpt).doesNotContain("#")
    assertThat(excerpt).doesNotContain("airplaneMode")
    assertThat(excerpt).doesNotContain("mingw")
    assertThat(excerpt).doesNotContain("targetToolchain")
    assertThat(
      excerpt,
    ).contains("dependencies.linux_x64 = \\\n    \$toolchainDependency.linux_x64 \\\n")
    assertThat(excerpt).contains("llvm.linux_x64.user=llvm-21-x86_64-linux-essentials-116\n")
    assertThat(
      excerpt,
    ).startsWith("dependenciesUrl = https://download.jetbrains.com/kotlin/native\n")
    val reread = KonanProperties.parse(excerpt)
    assertThat(reread.excerpt(hosts)).isEqualTo(excerpt)
    for ((host, targets) in hosts) {
      for (target in targets) {
        assertThat(reread.linkDependencies(host, target))
          .isEqualTo(properties.linkDependencies(host, target))
      }
    }
  }

  @Test
  fun `given a tar gz stream when read then the file under any top directory is found`() {
    val tar =
      tar(
        "kotlin-native-prebuilt-9.1.0/bin/konanc" to "#!/bin/sh\n",
        "kotlin-native-prebuilt-9.1.0/" + "x".repeat(120) + "/long" to "long",
        "kotlin-native-prebuilt-9.1.0/konan/konan.properties" to "a = b\n",
      )
    assertThat(Tar.read(ByteArrayInputStream(tar), "konan/konan.properties")?.decodeToString())
      .isEqualTo("a = b\n")
    assertThat(Tar.read(ByteArrayInputStream(tar), "konan/other")).isNull()
  }

  @Test
  fun `given release assets when resolved then every checksum comes from them`() {
    val release =
      KotlinRelease.fromAssets(
        "1.2.3",
        listOf("macos-aarch64"),
        fakeAssets("1.2.3"),
        ::fakeDownload,
      )
    assertThat(release.compilerSha256).isEqualTo(sha("kotlin-compiler-1.2.3.zip"))
    assertThat(release.nativePrebuiltSha256)
      .containsExactly("macos-aarch64", sha("kotlin-native-prebuilt-macos-aarch64-1.2.3.tar.gz"))
    assertThat(release.buildToolsApiSha256).isEqualTo(sha(KotlinRelease.BUILD_TOOLS_API))
    assertThat(release.btapiImplSha256.keys)
      .containsExactlyElementsIn(KotlinRelease.BTAPI_IMPL_ARTIFACTS.keys)
      .inOrder()
    assertThat(release.btapiImplSha256["stdlib"]).isEqualTo(sha("kotlin-stdlib"))
  }

  @Test
  fun `given a missing asset or jar or a wrong digest when resolved then it fails`() {
    val withoutNative =
      fakeAssets("1.2.3") - "kotlin-native-prebuilt-macos-aarch64-1.2.3.tar.gz.sha256"
    assertThat(
      assertThrows(UpgradeException::class.java) {
        KotlinRelease.fromAssets("1.2.3", listOf("macos-aarch64"), withoutNative, ::fakeDownload)
      },
    ).hasMessageThat().contains(
      "has no asset kotlin-native-prebuilt-macos-aarch64-1.2.3.tar.gz.sha256",
    )

    val wrongDigest = fakeAssets("1.2.3") + ("kotlin-compiler-1.2.3.zip" to "sha256:$hash")
    assertThat(
      assertThrows(UpgradeException::class.java) {
        KotlinRelease.fromAssets("1.2.3", listOf("macos-aarch64"), wrongDigest, ::fakeDownload)
      },
    ).hasMessageThat().contains("but its .sha256 file says")

    val download = { asset: String ->
      fakeDownload(asset).lines().filterNot { "kotlin-reflect" in it }.joinToString("\n")
    }
    val noDigest = fakeAssets("1.2.3") + ("maven-1.2.3-sha256.txt" to null)
    assertThat(
      assertThrows(UpgradeException::class.java) {
        KotlinRelease.fromAssets("1.2.3", listOf("macos-aarch64"), noDigest, download)
      },
    ).hasMessageThat().contains("lists no org/jetbrains/kotlin/kotlin-reflect/1.2.3")
  }

  @Test
  fun `given release API responses when parsed then only well-formed assets are accepted`() {
    val api = "https://api.github.com/repos/JetBrains/kotlin/releases/tags/v1.2.3"
    assertThat(
      HttpReleaseSource.parseAssets(
        api,
        """{"tag_name": "v1.2.3", "draft": false, "assets": [{"name": "a.zip",
          "browser_download_url": "https://x/a.zip", "digest": "sha256:$hash", "size": 1.5e3},
          {"name": "b", "browser_download_url": "https://x/b", "digest": null}]}""",
      ),
    ).containsExactly(
      "a.zip",
      HttpReleaseSource.Asset("https://x/a.zip", "sha256:$hash"),
      "b",
      HttpReleaseSource.Asset("https://x/b", null),
    )
    val malformed =
      mapOf(
        "<html>" to "",
        "[]" to "",
        "{\"message\": \"Not Found\"}" to "assets",
        "{\"assets\": [1]}" to "",
        "{\"assets\": [{\"name\": 1}]}" to "",
        "{\"assets\": [{\"name\": \"a\"}]}" to "browser_download_url",
        "{\"assets\": [{\"name\": \"a\", \"browser_download_url\": \"u\", \"digest\": 1}]}" to
          "digest",
      )
    for ((text, field) in malformed) {
      val error =
        assertThrows(UpgradeException::class.java) { HttpReleaseSource.parseAssets(api, text) }
      assertThat(error).hasMessageThat().startsWith("$api: malformed release: ")
      assertThat(error).hasMessageThat().contains(field)
    }
  }

  @Test
  fun `given an unusable download cache when used then it fails naming the file`() {
    val root = Files.createTempDirectory("download_cache")
    val underFile = DownloadCache(Files.writeString(root.resolve("file"), "").resolve("cache"))
    assertThat(underFile.read("abc")).isNull()
    val write = assertThrows(UpgradeException::class.java) { underFile.store("abc", "text") }
    assertThat(write).hasMessageThat().startsWith("cannot write the download cache $root/file/")
    assertThat(write).hasMessageThat().contains(DownloadCache.ENV)

    val cache = DownloadCache(root.resolve("cache"))
    cache.store("abc", "text")
    assertThat(cache.read("abc")).isEqualTo("text")
    // A directory in the place of an entry: the staged file cannot replace it.
    Files.createDirectories(root.resolve("cache/def/child"))
    assertThrows(UpgradeException::class.java) { cache.store("def", "text") }
    Files.write(root.resolve("cache/abc"), byteArrayOf(0xff.toByte(), 0xfe.toByte()))
    assertThat(assertThrows(UpgradeException::class.java) { cache.read("abc") })
      .hasMessageThat()
      .startsWith("cannot read the download cache $root/cache/abc: MalformedInputException")
    assertThat(Files.list(root.resolve("cache")).use { it.map { p -> "${p.fileName}" }.toList() })
      .containsExactly("abc", "def")
  }

  @Test
  fun `given a tar header with a malformed size when read then it fails`() {
    val tar = tar("konan.properties" to "a = b\n")
    "zzzzzzzzzzz\u0000".toByteArray().copyInto(tar, 124)
    assertThrows(IOException::class.java) {
      Tar.read(ByteArrayInputStream(tar), "konan.properties")
    }
  }

  companion object {
    fun testdata(name: String): String =
      Files.readString(
        Paths.get(
          System.getenv("TEST_SRCDIR"),
          System.getenv("TEST_WORKSPACE"),
          "src/test/kotlin/io/bazel/kotlin/upgrade/testdata",
          name,
        ),
      )

    fun sha(name: String): String = Checksums.sha256(name.toByteArray())

    /** The assets of a fake release whose checksums are the sha256 of the artifact names. */
    fun fakeAssets(version: String): Map<String, String?> {
      val archives =
        listOf(
          KotlinRelease.compilerAsset(version),
          KotlinRelease.nativeAsset(version, "linux-x86_64"),
          KotlinRelease.nativeAsset(version, "macos-aarch64"),
        )
      return archives.associateWith { "sha256:${sha(it)}" } +
        archives.associate { "$it.sha256" to null } +
        (
          KotlinRelease.mavenAsset(version) to
            "sha256:${Checksums.sha256(maven(version).toByteArray())}"
        )
    }

    fun fakeDownload(asset: String): String =
      when {
        asset.endsWith(
          ".sha256",
        ) -> "${sha(asset.removeSuffix(".sha256"))} *${asset.removeSuffix(".sha256")}\n"

        asset.startsWith(
          "maven-",
        ) -> maven(asset.removePrefix("maven-").removeSuffix("-sha256.txt"))

        else -> error("unexpected download $asset")
      }

    private fun maven(version: String): String =
      (KotlinRelease.BTAPI_IMPL_ARTIFACTS.values + KotlinRelease.BUILD_TOOLS_API)
        .joinToString("") { "${KotlinRelease.mavenPath(it, version)} ${sha(it)}\n" }

    /** A gzip-less tar of [files], with a GNU long-name entry for names over 100 bytes. */
    private fun tar(vararg files: Pair<String, String>): ByteArray {
      val out = ByteArrayOutputStream()
      TarArchiveOutputStream(out).use { tar ->
        tar.setLongFileMode(TarArchiveOutputStream.LONGFILE_GNU)
        for ((name, content) in files) {
          val bytes = content.toByteArray()
          tar.putArchiveEntry(TarArchiveEntry(name).apply { size = bytes.size.toLong() })
          tar.write(bytes)
          tar.closeArchiveEntry()
        }
      }
      return out.toByteArray()
    }
  }
}
