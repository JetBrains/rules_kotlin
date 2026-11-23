package io.bazel.kotlin.builder.utils.jars

import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardOpenOption

/** The jars one source file uses. */
data class SourceDependencies(
  val explicitJars: Set<String>,
  val implicitJars: Set<String>,
)

/**
 * The jars each source file of a compilation uses, by the source's path as the compiler reports
 * it. Incremental compilation recompiles some sources only, possibly over several rounds: the jdeps
 * plugin appends a record for each source a round analyzes, without reading the file, and a
 * source's last record replaces its earlier ones.
 *
 * The empty path holds the jars used outside any source file. No source owns them, so a record of
 * the empty path adds to its earlier ones.
 *
 * The plugin appends in place. An interrupted write cuts the last line, and [read] cannot always
 * tell a cut line from a complete one. A consumer that keeps the records across compilations
 * therefore gives the plugin a new file for each compilation, and merges that file into the kept
 * records after the compilation succeeds.
 *
 * The fields of a line are separated by tabs. An append starts with a `jar` line for each jar its
 * sources use: the index of the jar, which counts from 0 in the order of the lines, and the path
 * of the jar. The record of a source is one `src` line: the path of the source, the indexes of
 * the jars it uses explicitly, and the indexes of the jars it needs implicitly, each list
 * separated by commas. The indexes refer to the `jar` lines of the same append, so an append
 * writes the path of a jar once, not once per source that uses it.
 */
object SourceDependenciesFile {
  private const val JAR = "jar"
  private const val SOURCE = "src"

  /**
   * The dependencies of each source, from its last record, and of the empty path, from all its
   * records.
   */
  fun read(path: Path): Map<String, SourceDependencies> {
    if (!Files.isRegularFile(path)) {
      return emptyMap()
    }
    val jars = mutableListOf<String>()
    val explicit = linkedMapOf<String, MutableSet<String>>()
    val implicit = linkedMapOf<String, MutableSet<String>>()
    // A jar used in several appends has one String, which the sets of every source share.
    val interned = hashMapOf<String, String>()

    fun jarsOf(
      indexes: String,
      line: String,
    ): MutableSet<String> =
      if (indexes.isEmpty()) {
        linkedSetOf()
      } else {
        indexes.split(',').mapTo(linkedSetOf()) { index ->
          index.toIntOrNull()?.let(jars::getOrNull) ?: error("$path: no jar $index in: $line")
        }
      }
    Files.readAllLines(path, StandardCharsets.UTF_8).forEach { line ->
      val fields = line.split('\t')
      when (fields[0]) {
        JAR -> {
          check(fields.size == 3) {
            "$path: a jar line has 3 fields, not ${fields.size}, in: $line"
          }
          // The jar lines of an append count from 0, so jar 0 starts a new table.
          if (fields[1] == "0") {
            jars.clear()
          }
          check(fields[1] == jars.size.toString()) {
            "$path: jar ${jars.size} expected in: $line"
          }
          val jar = fields[2]
          jars.add(interned.getOrPut(jar) { jar })
        }

        SOURCE -> {
          check(fields.size == 4) {
            "$path: a source line has 4 fields, not ${fields.size}, in: $line"
          }
          val source = fields[1]
          val explicitJars = jarsOf(fields[2], line)
          val implicitJars = jarsOf(fields[3], line)
          // The records of the empty path add up.
          if (source.isEmpty() && source in explicit) {
            explicit.getValue(source).addAll(explicitJars)
            implicit.getValue(source).addAll(implicitJars)
          } else {
            explicit[source] = explicitJars
            implicit[source] = implicitJars
          }
        }

        else -> {
          error("$path: unknown line kind in: $line")
        }
      }
    }
    return explicit.keys.associateWith {
      SourceDependencies(explicit.getValue(it), implicit.getValue(it))
    }
  }

  /**
   * Appends a record for each source, which replaces the source's earlier records. The write is
   * not atomic.
   */
  fun append(
    path: Path,
    dependencies: Map<String, SourceDependencies>,
  ) {
    Files.write(
      path,
      records(dependencies),
      StandardCharsets.UTF_8,
      StandardOpenOption.CREATE,
      StandardOpenOption.APPEND,
    )
  }

  /** The `jar` lines of the jars the sources use, then the record of each source. */
  private fun records(dependencies: Map<String, SourceDependencies>): List<String> {
    val indexes = linkedMapOf<String, Int>()

    fun indexesOf(jars: Set<String>): String =
      jars.joinToString(",") { indexes.getOrPut(it) { indexes.size }.toString() }
    val sources =
      dependencies.map { (source, used) ->
        "$SOURCE\t$source\t${indexesOf(used.explicitJars)}\t${indexesOf(used.implicitJars)}"
      }
    return indexes.map { (jar, index) -> "$JAR\t$index\t$jar" } + sources
  }
}
