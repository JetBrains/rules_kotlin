package io.bazel.kotlin.upgrade

/** The link dependencies of an exec host besides its LLVM, as KOTLIN_NATIVE_DEPS declares them. */
data class NativeDeps(
  val host: List<String>,
  val targets: Map<String, List<String>>,
)

/** A KOTLIN_NATIVE_ARCHIVES entry; [path] is relative to `_DEPS_BASE`. */
data class NativeArchive(
  val path: String,
  val sha256: String,
)

/**
 * Reads and rewrites the pins of the Kotlin release train. Every edit is anchored to a known
 * assignment or table and fails if the anchor is missing. Rendered tables have sorted keys and
 * buildifier's formatting.
 */
object Rewrites {
  private const val SHA256 = "[0-9a-f]{64}"
  private val QUOTED = Regex("\"([^\"]*)\"")

  // --- src/main/starlark/core/repositories/versions.bzl ---

  private val CURRENT_RELEASE = Regex("^_KOTLIN_CURRENT_RELEASE = \"([^\"]+)\"$")
  private const val COMPILER = "    KOTLIN_CURRENT_COMPILER_RELEASE = version("
  private const val BUILD_TOOLS_API = "    KOTLIN_BUILD_TOOLS_API = version("
  private const val BTAPI_IMPL = "    BTAPI_IMPL_CURRENT_RELEASE = btapi_impl_version("

  fun currentRelease(versionsBzl: String): String =
    versionsBzl
      .lines()
      .mapNotNull { CURRENT_RELEASE.matchEntire(it)?.groupValues?.get(1) }
      .singleOrNull()
      ?: throw UpgradeException("versions.bzl: no single _KOTLIN_CURRENT_RELEASE assignment")

  /** Without Kotlin/Native, which versions.bzl does not pin. */
  fun currentPins(versionsBzl: String): KotlinRelease {
    val lines = versionsBzl.lines()

    fun sha(
      header: String,
      field: String,
    ): String {
      val block = block(lines, header, "    ),", "versions.bzl")
      val pattern = Regex("^\\s+$field = \"($SHA256)\",$")
      return block
        .mapNotNull { lines[it].let(pattern::matchEntire)?.groupValues?.get(1) }
        .singleOrNull()
        ?: throw UpgradeException("versions.bzl: no single $field in ${header.trim()}")
    }
    return KotlinRelease(
      version = currentRelease(versionsBzl),
      compilerSha256 = sha(COMPILER, "sha256"),
      buildToolsApiSha256 = sha(BUILD_TOOLS_API, "sha256"),
      btapiImplSha256 =
        KotlinRelease.BTAPI_IMPL_ARTIFACTS.keys.associateWith { sha(BTAPI_IMPL, "${it}_sha256") },
      nativePrebuiltSha256 = emptyMap(),
    )
  }

  fun rewriteVersions(
    versionsBzl: String,
    release: KotlinRelease,
  ): String {
    val lines = versionsBzl.lines().toMutableList()
    currentRelease(versionsBzl)
    val assignment = "_KOTLIN_CURRENT_RELEASE = \"${release.version}\""
    lines.replaceAll { line -> if (CURRENT_RELEASE.matches(line)) assignment else line }

    fun set(
      header: String,
      field: String,
      sha256: String,
    ) {
      val pattern = Regex("^(\\s+$field = \")$SHA256(\",)$")
      val matches =
        block(lines, header, "    ),", "versions.bzl").filter { pattern.matches(lines[it]) }
      if (matches.size != 1) {
        throw UpgradeException("versions.bzl: no single $field in ${header.trim()}")
      }
      lines[matches[0]] = pattern.replace(lines[matches[0]], "$1$sha256$2")
    }
    set(COMPILER, "sha256", release.compilerSha256)
    set(BUILD_TOOLS_API, "sha256", release.buildToolsApiSha256)
    for ((field, sha256) in release.btapiImplSha256) set(BTAPI_IMPL, "${field}_sha256", sha256)
    return lines.joinToString("\n")
  }

  // --- src/main/starlark/core/repositories/native_compiler.bzl ---

  private val NATIVE_VERSION = Regex("^KOTLIN_NATIVE_VERSION = \"([^\"]+)\"$")
  private const val PREBUILT = "KOTLIN_NATIVE_PREBUILT = {"
  private const val LLVM = "KOTLIN_NATIVE_LLVM = {"
  private const val BTAPI = "KOTLIN_NATIVE_BTAPI = {"
  private const val ARCHIVES = "KOTLIN_NATIVE_ARCHIVES = {"
  private const val DEPS = "KOTLIN_NATIVE_DEPS = {"

  /** The default Kotlin/Native release, KOTLIN_NATIVE_VERSION. */
  fun nativeVersion(nativeBzl: String): String =
    nativeBzl
      .lines()
      .mapNotNull { NATIVE_VERSION.matchEntire(it)?.groupValues?.get(1) }
      .singleOrNull()
      ?: throw UpgradeException("native_compiler.bzl: no single KOTLIN_NATIVE_VERSION assignment")

  /** Release to Maven artifact id to sha256; buildifier writes an empty table as `= {}`. */
  fun nativeBtapi(nativeBzl: String): Map<String, Map<String, String>> =
    if ("$BTAPI}" in nativeBzl.lines()) emptyMap() else nestedTable(nativeBzl, BTAPI)

  /** Release to exec host to sha256. */
  fun nativePrebuilt(nativeBzl: String): Map<String, Map<String, String>> =
    nestedTable(nativeBzl, PREBUILT)

  /** Release to exec host to LLVM. */
  fun nativeLlvm(nativeBzl: String): Map<String, Map<String, String>> = nestedTable(nativeBzl, LLVM)

  fun nativeArchives(nativeBzl: String): Map<String, NativeArchive> {
    val lines = nativeBzl.lines()
    val entry = Regex("^    \"([^\"]+)\": \\(_DEPS_BASE \\+ \"/([^\"]+)\", \"($SHA256)\"\\),$")
    return tableBody(lines, ARCHIVES).associate { index ->
      val match =
        entry.matchEntire(lines[index])
          ?: throw UpgradeException("KOTLIN_NATIVE_ARCHIVES: unexpected line: ${lines[index]}")
      match.groupValues[1] to NativeArchive(match.groupValues[2], match.groupValues[3])
    }
  }

  fun nativeDeps(nativeBzl: String): Map<String, NativeDeps> {
    val lines = nativeBzl.lines()
    val hostStart = Regex("^    \"([^\"]+)\": struct\\($")
    val hostDeps = Regex("^        host = \\[(.*)],$")
    val target = Regex("^            \"([^\"]+)\": \\[(.*)],$")
    val result = linkedMapOf<String, NativeDeps>()
    var host: String? = null
    var deps = emptyList<String>()
    var targets = linkedMapOf<String, List<String>>()
    for (index in tableBody(lines, DEPS)) {
      val line = lines[index]
      hostStart.matchEntire(line)?.let {
        host = it.groupValues[1]
        deps = emptyList()
        targets = linkedMapOf()
      }
      hostDeps.matchEntire(line)?.let { deps = quoted(it.groupValues[1]) }
      target.matchEntire(line)?.let { targets[it.groupValues[1]] = quoted(it.groupValues[2]) }
      if (line == "    ),") {
        val name = host ?: throw UpgradeException("KOTLIN_NATIVE_DEPS: unexpected '    ),'")
        result[name] = NativeDeps(deps, targets)
        host = null
      }
    }
    if (result.isEmpty()) throw UpgradeException("native_compiler.bzl: empty KOTLIN_NATIVE_DEPS")
    return result
  }

  fun rewriteNative(
    nativeBzl: String,
    version: String,
    prebuilt: Map<String, Map<String, String>>,
    llvm: Map<String, Map<String, String>>,
    btapi: Map<String, Map<String, String>>,
    archives: Map<String, NativeArchive>,
  ): String {
    nativeVersion(nativeBzl)
    var text =
      nativeBzl
        .lines()
        .joinToString("\n") {
          if (NATIVE_VERSION.matches(it)) "KOTLIN_NATIVE_VERSION = \"$version\"" else it
        }
    text = replaceTable(text, PREBUILT, renderNested(prebuilt))
    text = replaceTable(text, LLVM, renderNested(llvm))
    text = replaceTableOrEmpty(text, BTAPI, renderNested(btapi))
    val rendered =
      archives.toSortedMap().map { (name, archive) ->
        "    \"$name\": (_DEPS_BASE + \"/${archive.path}\", \"${archive.sha256}\"),"
      }
    return replaceTable(text, ARCHIVES, rendered)
  }

  /** The path of an LLVM archive under `_DEPS_BASE`: `resources/llvm/<dir>/<name>.tar.gz`. */
  fun llvmPath(name: String): String {
    val match =
      Regex("^llvm-(\\d+)-(.+)-(essentials|dev)-\\d+$").matchEntire(name)
        ?: throw UpgradeException("$name is not an LLVM distribution name")
    return "resources/llvm/${match.groupValues[1]}-${match.groupValues[2]}/$name.tar.gz"
  }

  // --- kotlin/internal/native/targets.bzl ---

  /** Exec host to konan host. */
  fun konanHosts(targetsBzl: String): Map<String, String> {
    val lines = targetsBzl.lines()
    val body = tableBody(lines, "EXEC_HOSTS = {").joinToString("\n") { lines[it] }
    val hosts =
      Regex("\"([^\"]+)\": struct\\(\\s*konan_host = \"([^\"]+)\"")
        .findAll(body)
        .associate { it.groupValues[1] to it.groupValues[2] }
    if (hosts.isEmpty()) throw UpgradeException("targets.bzl: no exec host in EXEC_HOSTS")
    return hosts
  }

  // --- src/test/starlark/native_konan_properties.bzl ---

  private const val KONAN_PROPERTIES = "KONAN_PROPERTIES = {"

  /** Keeps everything of [testdata] before KONAN_PROPERTIES, such as its docstring. */
  fun rewriteKonanTestdata(
    testdata: String,
    excerpts: Map<String, Map<String, String>>,
  ): String {
    val lines = testdata.lines()
    val start = lines.indexOf(KONAN_PROPERTIES)
    if (start < 0) throw UpgradeException("native_konan_properties.bzl: no $KONAN_PROPERTIES")
    val rendered = mutableListOf(KONAN_PROPERTIES)
    for ((release, hosts) in excerpts.toSortedMap()) {
      rendered += "    \"$release\": {"
      for ((host, excerpt) in hosts.toSortedMap()) {
        if ("\"\"\"" in excerpt) {
          throw UpgradeException("the konan.properties of $release has \"\"\"")
        }
        rendered += "        \"$host\": \"\"\"\\"
        rendered += excerpt.replace("\\", "\\\\").removeSuffix("\n") + "\n\"\"\","
      }
      rendered += "    },"
    }
    rendered += "}"
    return (lines.subList(0, start) + rendered).joinToString("\n") + "\n"
  }

  // --- kotlin/internal/toolchains.bzl and its test ---

  /** Makes [level] the default `api_version` and `language_version`; no value is removed. */
  fun rewriteToolchains(
    toolchainsBzl: String,
    level: String,
  ): String {
    val lines = toolchainsBzl.lines().toMutableList()
    val attribute = Regex("^(\\s+)\"(api_version|language_version)\": attr\\.string\\($")
    val seen = mutableSetOf<String>()
    var index = 0
    while (index < lines.size) {
      val match = attribute.matchEntire(lines[index])
      if (match == null) {
        index++
        continue
      }
      seen += match.groupValues[2]
      val indent = match.groupValues[1]
      val name = match.groupValues[2]
      val end =
        (index + 1 until lines.size).firstOrNull { lines[it] == "$indent)," }
          ?: throw UpgradeException("toolchains.bzl: unterminated $name")
      val defaultLine = Regex("^$indent    default = \"[^\"]*\",$")
      val default =
        (index + 1 until end).singleOrNull { defaultLine.matches(lines[it]) }
          ?: throw UpgradeException("toolchains.bzl: no single default of $name")
      lines[default] = "$indent    default = \"$level\","
      val valuesStart =
        (index + 1 until end).singleOrNull { lines[it] == "$indent    values = [" }
          ?: throw UpgradeException("toolchains.bzl: no values of $name")
      val valuesEnd =
        (valuesStart + 1 until end).firstOrNull { lines[it] == "$indent    ]," }
          ?: throw UpgradeException("toolchains.bzl: unterminated values of $name")
      val values = (valuesStart + 1 until valuesEnd).map { valueOf(lines[it]) }
      if (level !in values) {
        val sorted = (values + level).sortedWith(VERSION_ORDER)
        for (i in (valuesStart + 1 until valuesEnd).reversed()) lines.removeAt(i)
        lines.addAll(valuesStart + 1, sorted.map { "$indent        \"$it\"," })
      }
      index = end + (if (level in values) 0 else 1)
    }
    if (seen != setOf("api_version", "language_version")) {
      throw UpgradeException("toolchains.bzl: no api_version and language_version attributes")
    }
    return lines.joinToString("\n")
  }

  fun rewriteKotlincOptionsTest(
    testBzl: String,
    level: String,
  ): String {
    val lines = testBzl.lines().toMutableList()
    val expected = Regex("^(\\s+.*expected = \")[0-9.]+(\".*)$")
    val body =
      block(
        lines,
        "def _toolchain_versions_by_default_test_impl(ctx):",
        "    return analysistest.end(env)",
        "kotlinc_options_test.bzl",
      ).filter { expected.matches(lines[it]) }
    if (body.isEmpty()) throw UpgradeException("kotlinc_options_test.bzl: no default expectation")
    for (index in body) lines[index] = expected.replace(lines[index], "$1$level$2")
    return lines.joinToString("\n")
  }

  // --- examples/*/MODULE.bazel ---

  /**
   * A Maven artifact of the `org.jetbrains.kotlin` group, such as the Compose compiler plugin or
   * kotlin-metadata-jvm: it is released with the compiler and follows its release.
   */
  private val KOTLIN_ARTIFACT = Regex("\"org\\.jetbrains\\.kotlin:([A-Za-z0-9._-]+):([^\":]+)\"")
  private val MAVEN_INSTALL = Regex("^\\w+\\.install\\($")
  private val INSTALL_NAME = Regex("^ {4}name = \"([^\"]+)\",$")
  private val INSTALL_LOCK_FILE = Regex("^ {4}lock_file = ")

  /** The `org.jetbrains.kotlin` artifacts of a MODULE.bazel, as `artifact` to its version. */
  fun kotlinArtifacts(moduleBazel: String): List<Pair<String, String>> =
    KOTLIN_ARTIFACT
      .findAll(moduleBazel)
      .map { it.groupValues[1] to it.groupValues[2] }
      .toList()

  /** Moves every `org.jetbrains.kotlin` artifact of a MODULE.bazel to [version]. */
  fun rewriteKotlinArtifacts(
    moduleBazel: String,
    version: String,
  ): String =
    KOTLIN_ARTIFACT.replace(moduleBazel) {
      "\"org.jetbrains.kotlin:${it.groupValues[1]}:$version\""
    }

  /**
   * The repositories of the `maven.install` tags with a `lock_file` that pin an
   * `org.jetbrains.kotlin` artifact: their lock files need a repin after the rewrite.
   */
  fun lockedKotlinRepositories(moduleBazel: String): List<String> {
    val lines = moduleBazel.lines()
    val repositories = mutableListOf<String>()
    var index = 0
    while (index < lines.size) {
      if (!MAVEN_INSTALL.matches(lines[index])) {
        index++
        continue
      }
      val end = (index + 1 until lines.size).firstOrNull { lines[it] == ")" } ?: lines.size
      val body = lines.subList(index + 1, end)
      if (body.any { INSTALL_LOCK_FILE.containsMatchIn(it) } &&
        body.any { KOTLIN_ARTIFACT.containsMatchIn(it) }
      ) {
        repositories +=
          body.firstNotNullOfOrNull { INSTALL_NAME.matchEntire(it)?.groupValues?.get(1) } ?: "maven"
      }
      index = end + 1
    }
    return repositories.distinct()
  }

  // --- docs/kmp.md ---

  /** The region of the older releases `upgrade` keeps, each with its JVM compiler. */
  const val DOC_BEGIN = "<!-- BEGIN generated by scripts/upgrade_kotlin.sh: older releases -->"
  const val DOC_END = "<!-- END generated by scripts/upgrade_kotlin.sh: older releases -->"

  /** The region of the older Kotlin/Native releases `upgrade-native` keeps. */
  const val NATIVE_DOC_BEGIN =
    "<!-- BEGIN generated by scripts/upgrade_kotlin.sh: older Kotlin/Native releases -->"
  const val NATIVE_DOC_END =
    "<!-- END generated by scripts/upgrade_kotlin.sh: older Kotlin/Native releases -->"

  fun rewriteDocRegion(
    doc: String,
    content: String,
    beginMarker: String = DOC_BEGIN,
    endMarker: String = DOC_END,
  ): String {
    val lines = doc.lines()
    val begin = lines.indexOf(beginMarker)
    val end = lines.indexOf(endMarker)
    if (begin < 0 || end < begin || lines.count { it == beginMarker } != 1) {
      throw UpgradeException("docs/kmp.md: no single $beginMarker ... $endMarker region")
    }
    val body = if (content.isEmpty()) emptyList() else content.removeSuffix("\n").lines()
    return (lines.subList(0, begin + 1) + body + lines.subList(end, lines.size)).joinToString("\n")
  }

  private val RELEASE = Regex("^\\d+\\.\\d+\\.\\d+(-(dev-\\d+|[A-Za-z0-9.]+))?$")

  /** Whether [version] names a Kotlin release, e.g. 2.4.21, 2.5.20-RC2, or a dev build. */
  fun isRelease(version: String) = RELEASE.matches(version)

  /**
   * Numeric per component; within the same version, a dev build (e.g. 2.5.20-dev-5696) before a
   * Beta, a Beta before a release candidate, and a release candidate before the release, each
   * numeric by the number of its suffix (2.5.20-dev-999 before 2.5.20-dev-5696, -RC before -RC2).
   */
  val VERSION_ORDER: Comparator<String> =
    Comparator { a, b ->
      val left = a.split('-', limit = 2)
      val right = b.split('-', limit = 2)
      val l = left[0].split('.').map { it.toIntOrNull() ?: 0 }
      val r = right[0].split('.').map { it.toIntOrNull() ?: 0 }
      for (i in 0 until maxOf(l.size, r.size)) {
        val c = l.getOrElse(i) { 0 }.compareTo(r.getOrElse(i) { 0 })
        if (c != 0) return@Comparator c
      }
      val leftSuffix = left.getOrNull(1)
      val rightSuffix = right.getOrNull(1)
      compareValuesBy(
        leftSuffix,
        rightSuffix,
        { suffixKind(it) },
        { it?.let(::suffixNumber) ?: 0L },
        { it ?: "" },
      )
    }

  /** dev, then the other pre-releases (Beta), then RC, then the release. */
  private fun suffixKind(suffix: String?): Int =
    when {
      suffix == null -> 3
      suffix.startsWith("dev") -> 0
      suffix.startsWith("RC") -> 2
      else -> 1
    }

  private fun suffixNumber(suffix: String): Long =
    Regex("\\d+")
      .findAll(suffix)
      .lastOrNull()
      ?.value
      ?.toLongOrNull() ?: 0L

  fun languageLevel(version: String): String =
    Regex("^(\\d+\\.\\d+)\\.").find(version)?.groupValues?.get(1)
      ?: throw UpgradeException("$version is not a Kotlin release")

  private fun valueOf(line: String): String = QUOTED.find(line)?.groupValues?.get(1) ?: ""

  private fun quoted(list: String): List<String> =
    QUOTED.findAll(list).map { it.groupValues[1] }.toList()

  /** The lines strictly between the only [header] line and the next [closer] line. */
  private fun block(
    lines: List<String>,
    header: String,
    closer: String,
    file: String,
  ): IntRange {
    val starts = lines.indices.filter { lines[it] == header }
    if (starts.size != 1) throw UpgradeException("$file: no single '${header.trim()}'")
    val end =
      (starts[0] + 1 until lines.size).firstOrNull { lines[it] == closer }
        ?: throw UpgradeException("$file: '${header.trim()}' is not closed")
    return starts[0] + 1 until end
  }

  private fun tableBody(
    lines: List<String>,
    header: String,
  ): IntRange = block(lines, header, "}", header.substringBefore(" ="))

  private fun nestedTable(
    text: String,
    header: String,
  ): Map<String, Map<String, String>> {
    val lines = text.lines()
    val outer = Regex("^    \"([^\"]+)\": \\{$")
    val inner = Regex("^        \"([^\"]+)\": \"([^\"]+)\",$")
    val result = linkedMapOf<String, MutableMap<String, String>>()
    var current: MutableMap<String, String>? = null
    for (index in tableBody(lines, header)) {
      val line = lines[index]
      val o = outer.matchEntire(line)
      val i = inner.matchEntire(line)
      when {
        o != null -> current = linkedMapOf<String, String>().also { result[o.groupValues[1]] = it }
        i != null && current != null -> current[i.groupValues[1]] = i.groupValues[2]
        line == "    }," -> current = null
        else -> throw UpgradeException("${header.substringBefore(" =")}: unexpected line: $line")
      }
    }
    return result
  }

  private fun renderNested(table: Map<String, Map<String, String>>): List<String> =
    table.toSortedMap().flatMap { (key, values) ->
      listOf("    \"$key\": {") +
        values.toSortedMap().map { (k, v) -> "        \"$k\": \"$v\"," } +
        "    },"
    }

  private fun replaceTable(
    text: String,
    header: String,
    body: List<String>,
  ): String {
    val lines = text.lines()
    val range = tableBody(lines, header)
    return (lines.subList(0, range.first) + body + lines.subList(range.last + 1, lines.size))
      .joinToString("\n")
  }

  /** As [replaceTable], with buildifier's one-line `NAME = {}` for an empty table, either way. */
  private fun replaceTableOrEmpty(
    text: String,
    header: String,
    body: List<String>,
  ): String {
    val lines = text.lines()
    val empty = "$header}"
    val start =
      lines.indexOf(empty).takeIf { it >= 0 }
        ?: return if (body.isEmpty()) {
          val range = tableBody(lines, header)
          (lines.subList(0, range.first - 1) + empty + lines.subList(range.last + 2, lines.size))
            .joinToString("\n")
        } else {
          replaceTable(text, header, body)
        }
    if (lines.count { it == empty } != 1) {
      throw UpgradeException("${header.substringBefore(" =")}: no single '$empty'")
    }
    val replacement = if (body.isEmpty()) listOf(empty) else listOf(header) + body + "}"
    return (lines.subList(0, start) + replacement + lines.subList(start + 1, lines.size))
      .joinToString("\n")
  }
}
