package io.bazel.kotlin.upgrade

/**
 * A failure reported without a stack trace. Nothing is written when it is thrown, unless
 * [partial]: then some files could not be restored after a failed write.
 */
class UpgradeException(
  message: String,
  val partial: Boolean = false,
) : RuntimeException(message)

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

    /** @param assets each asset name to its GitHub digest (`sha256:<hash>`), if any. */
    fun fromAssets(
      version: String,
      hosts: Collection<String>,
      assets: Map<String, String?>,
      download: (String) -> String,
    ): KotlinRelease {
      fun require(asset: String) {
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

      val mavenAsset = mavenAsset(version)
      require(mavenAsset)
      val mavenText = download(mavenAsset)
      Checksums.parseDigest(assets[mavenAsset])?.let { digest ->
        if (Checksums.sha256(mavenText.toByteArray()) != digest) {
          throw UpgradeException("release v$version: $mavenAsset does not match its digest $digest")
        }
      }
      val maven =
        try {
          Checksums.parseMavenSha256(mavenText)
        } catch (e: IllegalArgumentException) {
          throw UpgradeException("release v$version: $mavenAsset: ${e.message}")
        }

      fun jar(artifact: String): String =
        maven[mavenPath(artifact, version)]
          ?: throw UpgradeException(
            "release v$version: $mavenAsset lists no ${mavenPath(artifact, version)}",
          )

      return KotlinRelease(
        version = version,
        compilerSha256 = archiveSha256(compilerAsset(version)),
        buildToolsApiSha256 = jar(BUILD_TOOLS_API),
        btapiImplSha256 = BTAPI_IMPL_ARTIFACTS.mapValues { (_, artifact) -> jar(artifact) },
        nativePrebuiltSha256 =
          hosts.sorted().associateWith { host -> archiveSha256(nativeAsset(version, host)) },
      )
    }
  }
}

/** Where the tool reads release metadata from: the network, or fixtures in tests. */
interface ReleaseSource {
  fun release(
    version: String,
    hosts: Collection<String>,
  ): KotlinRelease

  /** The `konan/konan.properties` of the distribution archive of [host] with [sha256]. */
  fun konanProperties(
    version: String,
    host: String,
    sha256: String,
  ): String

  /** [path] is relative to the konan dependencies URL. */
  fun dependencySha256(path: String): String
}
