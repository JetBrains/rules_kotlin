package io.bazel.kotlin.upgrade

/**
 * A failure reported without a stack trace. Nothing is written when it is thrown, unless
 * [partial]: then some files could not be restored after a failed write.
 */
class UpgradeException(
  message: String,
  val partial: Boolean = false,
) : RuntimeException(message)

/** The checksums of the artifacts of one Kotlin/Native release that rules_kotlin pins. */
data class NativeRelease(
  val version: String,
  /** By exec host. */
  val prebuiltSha256: Map<String, String>,
  /**
   * By Maven artifact id, see [KotlinRelease.NATIVE_BTAPI_ARTIFACTS]; null for a release older than
   * [KotlinRelease.FIRST_NATIVE_BTAPI], which has no Kotlin/Native Build Tools API.
   */
  val btapiSha256: Map<String, String>?,
)

/** The checksums of the artifacts of one Kotlin release that rules_kotlin pins. */
data class KotlinRelease(
  val version: String,
  val compilerSha256: String,
  val buildToolsApiSha256: String,
  /** By btapi_impl_version field, see [BTAPI_IMPL_ARTIFACTS]. */
  val btapiImplSha256: Map<String, String>,
  /** By exec host. */
  val nativePrebuiltSha256: Map<String, String>,
) {
  companion object {
    const val BUILD_TOOLS_API = "kotlin-build-tools-api"

    /** In the order of `_ARTIFACTS` of src/main/starlark/core/repositories/btapi_impl.bzl. */
    val BTAPI_IMPL_ARTIFACTS =
      linkedMapOf(
        "build_tools_impl" to "kotlin-build-tools-impl",
        "compiler" to "kotlin-compiler-embeddable",
        "annotation_processing" to "kotlin-annotation-processing-embeddable",
        "jvm_abi_gen" to "jvm-abi-gen",
        "stdlib" to "kotlin-stdlib",
        "reflect" to "kotlin-reflect",
        "daemon_client" to "kotlin-daemon-client",
        "script_runtime" to "kotlin-script-runtime",
        "tooling_core" to "kotlin-tooling-core",
      )

    /**
     * The artifacts of the Kotlin/Native Build Tools API: the API the launcher of the Kotlin/Native
     * actions is compiled against, and the implementation a klib compilation loads. In the order
     * of `KOTLIN_NATIVE_BTAPI` of src/main/starlark/core/repositories/native_compiler.bzl.
     */
    val NATIVE_BTAPI_ARTIFACTS =
      listOf(
        BUILD_TOOLS_API,
        "kotlin-build-tools-cri-impl",
        "kotlin-build-tools-impl",
        "kotlin-daemon-client",
      )

    /** The first Kotlin/Native release with a Build Tools API (NativeKlibCompilationOperation). */
    const val FIRST_NATIVE_BTAPI = "2.5.20-dev-4986"

    /** The Kotlin dev Maven repository, which publishes the dev builds, e.g. 2.5.20-dev-5696. */
    const val MAVEN_DEV = "https://redirector.kotlinlang.org/maven/dev"

    /** Whether [version] is a dev build: no GitHub release, but artifacts in [MAVEN_DEV]. */
    fun isDev(version: String) = "-dev-" in version

    fun hasNativeBtapi(version: String) =
      Rewrites.VERSION_ORDER.compare(version, FIRST_NATIVE_BTAPI) >= 0

    fun compilerAsset(version: String) = "kotlin-compiler-$version.zip"

    fun nativeAsset(
      version: String,
      host: String,
    ) = "kotlin-native-prebuilt-$host-$version.tar.gz"

    fun mavenAsset(version: String) = "maven-$version-sha256.txt"

    fun mavenPath(
      artifact: String,
      version: String,
    ) = "org/jetbrains/kotlin/$artifact/$version/$artifact-$version.jar"

    /** The path of the distribution of a dev build in [MAVEN_DEV], with the host as classifier. */
    fun devNativePath(
      version: String,
      host: String,
    ) = "org/jetbrains/kotlin/kotlin-native-prebuilt/$version/" +
      "kotlin-native-prebuilt-$version-$host.tar.gz"

    /** @param assets each asset name to its GitHub digest (`sha256:<hash>`), if any. */
    fun fromAssets(
      version: String,
      hosts: Collection<String>,
      assets: Map<String, String?>,
      download: (String) -> String,
    ): KotlinRelease {
      val release = Assets(version, assets, download)
      return KotlinRelease(
        version = version,
        compilerSha256 = release.archiveSha256(compilerAsset(version)),
        buildToolsApiSha256 = release.jar(BUILD_TOOLS_API),
        btapiImplSha256 = BTAPI_IMPL_ARTIFACTS.mapValues { (_, artifact) -> release.jar(artifact) },
        nativePrebuiltSha256 =
          hosts.sorted().associateWith { host ->
            release.archiveSha256(nativeAsset(version, host))
          },
      )
    }

    /** The Kotlin/Native artifacts of a GitHub release; see [fromAssets]. */
    fun nativeFromAssets(
      version: String,
      hosts: Collection<String>,
      assets: Map<String, String?>,
      download: (String) -> String,
    ): NativeRelease {
      val release = Assets(version, assets, download)
      return NativeRelease(
        version = version,
        prebuiltSha256 =
          hosts.sorted().associateWith { host ->
            release.archiveSha256(nativeAsset(version, host))
          },
        btapiSha256 =
          if (hasNativeBtapi(version)) NATIVE_BTAPI_ARTIFACTS.associateWith(release::jar) else null,
      )
    }
  }

  /** The checksums of the assets of the GitHub release of [version]. */
  private class Assets(
    private val version: String,
    private val assets: Map<String, String?>,
    private val download: (String) -> String,
  ) {
    private val maven by lazy {
      val mavenAsset = mavenAsset(version)
      require(mavenAsset)
      val mavenText = download(mavenAsset)
      Checksums.parseDigest(assets[mavenAsset])?.let { digest ->
        if (Checksums.sha256(mavenText.toByteArray()) != digest) {
          throw UpgradeException("release v$version: $mavenAsset does not match its digest $digest")
        }
      }
      try {
        Checksums.parseMavenSha256(mavenText)
      } catch (e: IllegalArgumentException) {
        throw UpgradeException("release v$version: $mavenAsset: ${e.message}")
      }
    }

    private fun require(asset: String) {
      if (asset !in assets) throw UpgradeException("release v$version has no asset $asset")
    }

    fun archiveSha256(asset: String): String {
      require(asset)
      require("$asset.sha256")
      val published =
        try {
          Checksums.parseSidecar(download("$asset.sha256"), asset)
        } catch (e: IllegalArgumentException) {
          throw UpgradeException("release v$version: ${e.message}")
        }
      val digest = Checksums.parseDigest(assets[asset])
      if (digest != null && digest != published) {
        throw UpgradeException(
          "release v$version: $asset has digest $digest, but its .sha256 file says $published",
        )
      }
      return published
    }

    fun jar(artifact: String): String =
      maven[mavenPath(artifact, version)]
        ?: throw UpgradeException(
          "release v$version: ${mavenAsset(version)} lists no ${mavenPath(artifact, version)}",
        )
  }
}

/** Where the tool reads release metadata from: the network, or fixtures in tests. */
interface ReleaseSource {
  fun release(
    version: String,
    hosts: Collection<String>,
  ): KotlinRelease

  /** The Kotlin/Native artifacts of a release or a dev build. */
  fun nativeRelease(
    version: String,
    hosts: Collection<String>,
  ): NativeRelease

  /** The `konan/konan.properties` of the distribution archive of [host] with [sha256]. */
  fun konanProperties(
    version: String,
    host: String,
    sha256: String,
  ): String

  /** [path] is relative to the konan dependencies URL. */
  fun dependencySha256(path: String): String
}
