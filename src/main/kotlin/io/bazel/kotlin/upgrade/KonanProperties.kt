package io.bazel.kotlin.upgrade

/**
 * The `konan/konan.properties` of a Kotlin/Native distribution, read as `parse_konan_properties`
 * and `konan_link_dependencies` of src/main/starlark/core/repositories/native_compiler.bzl read it.
 */
class KonanProperties private constructor(
  private val entries: List<Entry>,
) {
  private class Entry(
    val key: String,
    val value: String,
    val lines: List<String>,
  )

  /** Each property to its unresolved value; a later entry of a key wins. */
  val properties: Map<String, String> = entries.associate { it.key to it.value }

  /** `llvm.<konanHost>.user`: the LLVM the distribution links with on its own host. */
  fun userLlvm(konanHost: String): String =
    properties["llvm.$konanHost.user"]
      ?: throw UpgradeException("konan.properties names no llvm.$konanHost.user")

  fun linkDependencies(
    konanHost: String,
    konanTarget: String,
  ): List<String> =
    linkKeys(konanHost, konanTarget)
      .flatMap { (key, suffix) -> resolve(hostProperty(key, suffix)) }
      .distinct()
      .sorted()

  /**
   * The lines of the entries the link dependencies of [hosts] (konan host to konan targets) resolve
   * through, plus the LLVM names and `dependenciesUrl`. An excerpt of an excerpt is itself.
   */
  fun excerpt(hosts: Map<String, List<String>>): String {
    val keys = linkedSetOf("dependenciesUrl")
    for ((konanHost, targets) in hosts) {
      keys += listOf("llvm.$konanHost.dev", "llvm.$konanHost.user")
      for (target in targets) {
        for ((key, suffix) in linkKeys(konanHost, target)) {
          keys += if ("$key.$suffix" in properties) "$key.$suffix" else key
        }
      }
    }
    val pending = ArrayDeque(keys)
    while (pending.isNotEmpty()) {
      val key = pending.removeFirst()
      for (token in tokens(properties[key] ?: continue)) {
        if (token.startsWith("$") && keys.add(token.substring(1))) {
          pending += token.substring(1)
        }
      }
    }
    val last = entries.withIndex().associate { (index, entry) -> entry.key to index }
    return entries
      .withIndex()
      .filter { (index, entry) -> entry.key in keys && last[entry.key] == index }
      .flatMap { it.value.lines }
      .joinToString("") { "$it\n" }
  }

  private fun linkKeys(
    konanHost: String,
    konanTarget: String,
  ): List<Pair<String, String>> {
    val suffix = if (konanTarget == konanHost) konanHost else "$konanHost-$konanTarget"
    return listOfNotNull(
      "llvmHome" to konanHost,
      "libffiDir" to konanHost,
      "dependencies" to suffix,
      ("emulatorDependency" to suffix).takeIf { konanTarget.startsWith("linux_") },
    )
  }

  private fun hostProperty(
    key: String,
    suffix: String,
  ): String = properties["$key.$suffix"] ?: properties[key] ?: ""

  /** Expands `$name` tokens recursively; a cycle stays unresolved. */
  private fun resolve(value: String): List<String> {
    val resolved = mutableListOf<String>()
    val pending = ArrayDeque(tokens(value).map { it to emptyList<String>() })
    var steps = 0
    while (pending.isNotEmpty() && steps++ < MAX_RESOLUTION_STEPS) {
      val (token, seen) = pending.removeFirst()
      val name = token.substring(1)
      if (token.startsWith("$") && name !in seen) {
        tokens(properties[name] ?: "").reversed().forEach { pending.addFirst(it to seen + name) }
      } else {
        resolved += token
      }
    }
    return resolved + pending.map { it.first }
  }

  companion object {
    private const val MAX_RESOLUTION_STEPS = 1000

    fun parse(text: String): KonanProperties {
      val entries = mutableListOf<Entry>()
      var logical: StringBuilder? = null
      var lines = mutableListOf<String>()
      for (raw in text.lines()) {
        val line = raw.trimStart(' ', '\t')
        if (logical == null) {
          if (line.isEmpty() || line.startsWith("#") || line.startsWith("!")) continue
          logical = StringBuilder()
          lines = mutableListOf()
        }
        lines += raw
        if (continues(line)) {
          logical.append(line, 0, line.length - 1)
          continue
        }
        entries += entry(logical.append(line).toString(), lines)
        logical = null
      }
      if (logical != null) entries += entry(logical.toString(), lines)
      return KonanProperties(entries)
    }

    private fun continues(line: String): Boolean =
      (line.length - line.trimEnd('\\').length) % 2 == 1

    private fun entry(
      logical: String,
      lines: List<String>,
    ): Entry {
      val keyEnd =
        listOf('=', ':', ' ', '\t')
          .map(logical::indexOf)
          .filter { it >= 0 }
          .minOrNull() ?: logical.length
      var rest = logical.substring(keyEnd)
      val separated = rest.startsWith("=") || rest.startsWith(":")
      rest = (if (separated) rest.substring(1) else rest).trimStart(' ', '\t')
      if (!separated && (rest.startsWith("=") || rest.startsWith(":"))) {
        rest = rest.substring(1).trimStart(' ', '\t')
      }
      return Entry(logical.substring(0, keyEnd), rest, lines.toList())
    }

    private fun tokens(value: String): List<String> =
      value.replace('\t', ' ').split(' ').filter(String::isNotEmpty)
  }
}
