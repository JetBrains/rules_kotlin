package io.bazel.kotlin.upgrade

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.security.DigestInputStream
import java.security.MessageDigest
import java.time.Duration
import java.util.zip.GZIPInputStream

/**
 * Reads release metadata from GitHub, the Kotlin dev Maven repository (for the Kotlin/Native dev
 * builds) and the konan dependencies server. The `konan.properties` of a distribution is read by
 * streaming its whole archive, which must match the published checksum; it is cached by that
 * checksum.
 */
class HttpReleaseSource(
  cache: Path,
  private val log: (String) -> Unit,
) : ReleaseSource {
  private val cache = DownloadCache(cache.resolve("konan.properties"))
  private val client =
    HttpClient
      .newBuilder()
      .followRedirects(HttpClient.Redirect.NORMAL)
      .connectTimeout(Duration.ofSeconds(30))
      .build()

  override fun release(
    version: String,
    hosts: Collection<String>,
  ): KotlinRelease {
    val assets = githubAssets(version)
    return KotlinRelease.fromAssets(version, hosts, assets.mapValues { it.value.digest }) {
      text(assets.getValue(it).url)
    }
  }

  /**
   * A release: from its GitHub release, as [release]. A dev build: from the `.sha256` files the
   * Kotlin dev Maven repository publishes next to each archive and jar.
   */
  override fun nativeRelease(
    version: String,
    hosts: Collection<String>,
  ): NativeRelease {
    if (!KotlinRelease.isDev(version)) {
      val assets = githubAssets(version)
      return KotlinRelease.nativeFromAssets(version, hosts, assets.mapValues { it.value.digest }) {
        text(assets.getValue(it).url)
      }
    }

    fun sidecar(path: String): String {
      val url = "${KotlinRelease.MAVEN_DEV}/$path.sha256"
      return try {
        Checksums.parseSidecar(text(url), path.substringAfterLast('/'))
      } catch (e: IllegalArgumentException) {
        throw UpgradeException("$url: ${e.message}")
      }
    }
    return NativeRelease(
      version = version,
      prebuiltSha256 =
        hosts.sorted().associateWith { sidecar(KotlinRelease.devNativePath(version, it)) },
      btapiSha256 =
        if (KotlinRelease.hasNativeBtapi(version)) {
          KotlinRelease.NATIVE_BTAPI_ARTIFACTS.associateWith {
            sidecar(KotlinRelease.mavenPath(it, version))
          }
        } else {
          null
        },
    )
  }

  override fun konanProperties(
    version: String,
    host: String,
    sha256: String,
  ): String {
    cache.read(sha256)?.let { return it }
    val url = nativeUrl(version, host)
    val asset = url.substringAfterLast('/')
    log("downloading $url to read its konan/konan.properties")
    val digest = MessageDigest.getInstance("SHA-256")
    val properties =
      try {
        DigestInputStream(get(url), digest).use { raw ->
          val found = Tar.read(GZIPInputStream(raw), "konan/konan.properties")
          raw.transferTo(OutputStream.nullOutputStream())
          found
        }
      } catch (e: IOException) {
        throw UpgradeException("GET $url: cannot read the archive: ${Upgrade.describe(e)}")
      } ?: throw UpgradeException("$asset has no konan/konan.properties")
    val actual = Checksums.hex(digest.digest())
    if (actual != sha256) {
      throw UpgradeException("$asset has sha256 $actual, but the release publishes $sha256")
    }
    val text = String(properties, Charsets.UTF_8)
    try {
      cache.store(sha256, text)
    } catch (e: UpgradeException) {
      log("warning: ${e.message}")
    }
    return text
  }

  override fun dependencySha256(path: String): String {
    val url = "$DEPENDENCIES_URL/$path.sha256"
    return try {
      Checksums.parseSidecar(text(url), path.substringAfterLast('/'))
    } catch (e: IllegalArgumentException) {
      throw UpgradeException("$url: ${e.message}")
    }
  }

  private fun githubAssets(version: String): Map<String, Asset> {
    val api = "https://api.github.com/repos/JetBrains/kotlin/releases/tags/v$version"
    return parseAssets(api, text(api, github = true))
  }

  private fun text(
    url: String,
    github: Boolean = false,
  ): String =
    try {
      get(url, github).use { String(it.readAllBytes(), Charsets.UTF_8) }
    } catch (e: IOException) {
      throw UpgradeException("GET $url: ${Upgrade.describe(e)}")
    }

  private fun get(
    url: String,
    github: Boolean = false,
  ): InputStream {
    val uri =
      try {
        URI.create(url)
      } catch (e: IllegalArgumentException) {
        throw UpgradeException("not a URL: $url")
      }
    val request = HttpRequest.newBuilder(uri).timeout(Duration.ofMinutes(30))
    if (github) {
      request.header("Accept", "application/vnd.github+json")
      System.getenv("GITHUB_TOKEN")?.takeIf(String::isNotEmpty)?.let {
        request.header("Authorization", "Bearer $it")
      }
    }
    val response =
      try {
        client.send(request.build(), HttpResponse.BodyHandlers.ofInputStream())
      } catch (e: IOException) {
        throw UpgradeException("GET $url: ${Upgrade.describe(e)}")
      } catch (e: InterruptedException) {
        Thread.currentThread().interrupt()
        throw UpgradeException("GET $url: interrupted")
      }
    if (response.statusCode() != 200) {
      response.body().close()
      throw UpgradeException("GET $url: HTTP ${response.statusCode()}")
    }
    return response.body()
  }

  /** A GitHub release asset; [digest] is `sha256:<hash>`, if any. */
  data class Asset(
    val url: String,
    val digest: String?,
  )

  @Serializable
  private class Release(
    val assets: List<NamedAsset>,
  )

  @Serializable
  private class NamedAsset(
    val name: String,
    @SerialName("browser_download_url") val url: String,
    val digest: String? = null,
  )

  companion object {
    const val DEPENDENCIES_URL = "https://download.jetbrains.com/kotlin/native"

    private val JSON = Json { ignoreUnknownKeys = true }

    /** The URL of the distribution of [host]: in the Kotlin dev Maven repository for a dev build. */
    fun nativeUrl(
      version: String,
      host: String,
    ): String =
      if (KotlinRelease.isDev(version)) {
        "${KotlinRelease.MAVEN_DEV}/${KotlinRelease.devNativePath(version, host)}"
      } else {
        "https://github.com/JetBrains/kotlin/releases/download/v$version/" +
          KotlinRelease.nativeAsset(version, host)
      }

    /** The assets, by name, of the GitHub release API response [text] of [api]. */
    fun parseAssets(
      api: String,
      text: String,
    ): Map<String, Asset> {
      val release =
        try {
          JSON.decodeFromString(Release.serializer(), text)
        } catch (e: IllegalArgumentException) {
          throw UpgradeException("$api: malformed release: ${e.message}")
        }
      return release.assets.associate { it.name to Asset(it.url, it.digest) }
    }
  }
}

/** Text files cached under [directory], keyed by the checksum of what they were read from. */
class DownloadCache(
  private val directory: Path,
) {
  fun read(key: String): String? {
    val file = directory.resolve(key)
    if (!Files.isRegularFile(file)) return null
    return try {
      Files.readString(file)
    } catch (e: IOException) {
      throw UpgradeException(
        "cannot read the download cache $file: ${Upgrade.describe(e)}; delete it, or set $ENV " +
          "to another directory",
      )
    }
  }

  fun store(
    key: String,
    text: String,
  ) {
    val file = directory.resolve(key)
    var temporary: Path? = null
    try {
      Files.createDirectories(directory)
      temporary = Files.createTempFile(directory, key, ".tmp")
      Files.writeString(temporary, text)
      Files.move(temporary, file, StandardCopyOption.REPLACE_EXISTING)
    } catch (e: IOException) {
      temporary?.let { runCatching { Files.deleteIfExists(it) } }
      throw UpgradeException(
        "cannot write the download cache $file: ${Upgrade.describe(e)}; set $ENV to another " +
          "directory",
      )
    }
  }

  companion object {
    const val ENV = "RULES_KOTLIN_UPGRADE_CACHE"
  }
}

object Tar {
  /** The first regular file whose path is [suffix] or ends with `/<suffix>`, or null. */
  fun read(
    input: InputStream,
    suffix: String,
  ): ByteArray? {
    val tar = TarArchiveInputStream(input)
    return generateSequence { tar.nextEntry }
      .firstOrNull { it.isFile && (it.name == suffix || it.name.endsWith("/$suffix")) }
      ?.let { tar.readAllBytes() }
  }
}
