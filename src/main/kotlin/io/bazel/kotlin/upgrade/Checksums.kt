package io.bazel.kotlin.upgrade

import java.security.MessageDigest

object Checksums {
  private val SHA256 = Regex("[0-9a-f]{64}")

  /**
   * A `.sha256` file holds a bare hash, or `<hash> *<file>` / `<hash>  <file>` as `sha256sum`
   * writes it; with [file], a named entry must name it.
   */
  fun parseSidecar(
    text: String,
    file: String? = null,
  ): String {
    val fields = text.trim().split(Regex("\\s+"), limit = 2)
    val hash = fields[0].lowercase()
    require(fields[0].isNotEmpty() && SHA256.matches(hash)) {
      "not a sha256 file${file?.let { " of $it" } ?: ""}: '${text.trim()}'"
    }
    if (file != null && fields.size == 2) {
      val named = fields[1].trim().removePrefix("*")
      require(named == file) { "the sha256 file of $file names $named" }
    }
    return hash
  }

  /** `maven-<version>-sha256.txt` has a `<path> <sha256>` line per [KotlinRelease.mavenPath]. */
  fun parseMavenSha256(text: String): Map<String, String> =
    text
      .lineSequence()
      .map(String::trim)
      .filter(String::isNotEmpty)
      .associate { line ->
        val fields = line.split(Regex("\\s+"))
        require(fields.size == 2 && SHA256.matches(fields[1].lowercase())) {
          "malformed maven sha256 line: '$line'"
        }
        fields[0] to fields[1].lowercase()
      }

  /** Null for a digest of another algorithm than `sha256:`. */
  fun parseDigest(digest: String?): String? =
    digest
      ?.takeIf { it.startsWith("sha256:") }
      ?.removePrefix("sha256:")
      ?.lowercase()
      ?.also { require(SHA256.matches(it)) { "malformed digest: $digest" } }

  fun sha256(bytes: ByteArray): String = hex(MessageDigest.getInstance("SHA-256").digest(bytes))

  fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it) }
}
