package io.bazel.kotlin.builder.utils.jars

import com.google.common.truth.Truth.assertThat
import org.junit.Assert.fail
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.JUnit4
import java.nio.file.Files
import java.nio.file.Path

@RunWith(JUnit4::class)
class SourceDependenciesTest {
  @Test
  fun `the per-source file keeps every source, including those without dependencies`() {
    val file = Files.createTempDirectory("SourceDependenciesTest").resolve("source_deps")
    val dependencies =
      mapOf(
        "/src/A.kt" to SourceDependencies(setOf("a.jar", "b.jar"), setOf("c.jar")),
        "/src/B.kt" to SourceDependencies(emptySet(), emptySet()),
        "/src/C.kt" to SourceDependencies(emptySet(), setOf("c.jar")),
      )

    SourceDependenciesFile.append(file, dependencies)

    assertThat(SourceDependenciesFile.read(file)).isEqualTo(dependencies)
  }

  @Test
  fun `an append writes the path of a jar once, then one line per source`() {
    val file = Files.createTempDirectory("SourceDependenciesTest").resolve("source_deps")

    SourceDependenciesFile.append(
      file,
      mapOf(
        "/src/A.kt" to SourceDependencies(setOf("a.jar", "b.jar"), setOf("c.jar")),
        "/src/B.kt" to SourceDependencies(setOf("b.jar"), emptySet()),
      ),
    )

    assertThat(Files.readAllLines(file))
      .containsExactly(
        "jar\t0\ta.jar",
        "jar\t1\tb.jar",
        "jar\t2\tc.jar",
        "src\t/src/A.kt\t0,1\t2",
        "src\t/src/B.kt\t1\t",
      ).inOrder()
  }

  @Test
  fun `an appended record replaces the source's earlier records and keeps the others`() {
    val file = Files.createTempDirectory("SourceDependenciesTest").resolve("source_deps")
    SourceDependenciesFile.append(
      file,
      mapOf(
        "/src/A.kt" to SourceDependencies(setOf("a.jar"), emptySet()),
        "/src/B.kt" to SourceDependencies(setOf("b.jar"), emptySet()),
      ),
    )

    SourceDependenciesFile.append(
      file,
      mapOf(
        "/src/A.kt" to SourceDependencies(emptySet(), emptySet()),
        "/src/C.kt" to SourceDependencies(setOf("c.jar"), emptySet()),
      ),
    )

    assertThat(SourceDependenciesFile.read(file))
      .containsExactly(
        "/src/A.kt",
        SourceDependencies(emptySet(), emptySet()),
        "/src/B.kt",
        SourceDependencies(setOf("b.jar"), emptySet()),
        "/src/C.kt",
        SourceDependencies(setOf("c.jar"), emptySet()),
      )
  }

  @Test
  fun `rounds append to a missing file, and a source analyzed in consecutive rounds is replaced`() {
    val file = Files.createTempDirectory("SourceDependenciesTest").resolve("source_deps")

    SourceDependenciesFile.append(
      file,
      mapOf(
        "/src/A.kt" to SourceDependencies(setOf("a.jar"), emptySet()),
        "/src/B.kt" to SourceDependencies(setOf("b.jar"), setOf("c.jar")),
      ),
    )
    SourceDependenciesFile.append(
      file,
      mapOf("/src/B.kt" to SourceDependencies(setOf("d.jar"), emptySet())),
    )

    assertThat(SourceDependenciesFile.read(file))
      .containsExactly(
        "/src/A.kt",
        SourceDependencies(setOf("a.jar"), emptySet()),
        "/src/B.kt",
        SourceDependencies(setOf("d.jar"), emptySet()),
      )
  }

  @Test
  fun `the records of the empty path add up, while a source's record is replaced`() {
    val file = Files.createTempDirectory("SourceDependenciesTest").resolve("source_deps")

    SourceDependenciesFile.append(
      file,
      mapOf(
        "" to SourceDependencies(setOf("a.jar"), emptySet()),
        "/src/A.kt" to SourceDependencies(setOf("a.jar"), emptySet()),
      ),
    )
    SourceDependenciesFile.append(
      file,
      mapOf(
        "" to SourceDependencies(setOf("b.jar"), setOf("c.jar")),
        "/src/A.kt" to SourceDependencies(emptySet(), emptySet()),
      ),
    )

    assertThat(SourceDependenciesFile.read(file))
      .containsExactly(
        "",
        SourceDependencies(setOf("a.jar", "b.jar"), setOf("c.jar")),
        "/src/A.kt",
        SourceDependencies(emptySet(), emptySet()),
      )
  }

  @Test
  fun `a missing per-source file has no sources`() {
    val file = Files.createTempDirectory("SourceDependenciesTest").resolve("missing")

    assertThat(SourceDependenciesFile.read(file)).isEmpty()
  }

  @Test
  fun `a line of an unknown kind fails, naming the file and the line`() {
    val file = Files.createTempDirectory("SourceDependenciesTest").resolve("source_deps")
    Files.write(file, listOf("src\t/src/A.kt\t\t", "a.jar"))

    assertReadFails(file, "$file: unknown line kind in: a.jar")
  }

  @Test
  fun `a jar index without a jar line fails, naming the file and the line`() {
    val file = Files.createTempDirectory("SourceDependenciesTest").resolve("source_deps")
    Files.write(file, listOf("jar\t0\ta.jar", "src\t/src/A.kt\t1\t"))

    assertReadFails(file, "$file: no jar 1 in: src\t/src/A.kt\t1\t")
  }

  @Test
  fun `a jar line with an unexpected index fails, naming the file and the line`() {
    val file = Files.createTempDirectory("SourceDependenciesTest").resolve("source_deps")
    Files.write(file, listOf("jar\t1\ta.jar"))

    assertReadFails(file, "$file: jar 0 expected in: jar\t1\ta.jar")
  }

  @Test
  fun `a cut jar line fails, naming the file and the line`() {
    val file = Files.createTempDirectory("SourceDependenciesTest").resolve("source_deps")
    Files.write(file, listOf("jar\t0"))

    assertReadFails(file, "$file: a jar line has 3 fields, not 2, in: jar\t0")
  }

  @Test
  fun `a cut source line fails, naming the file and the line`() {
    val file = Files.createTempDirectory("SourceDependenciesTest").resolve("source_deps")
    Files.write(file, listOf("jar\t0\ta.jar", "src\t/src/A.kt\t0"))

    assertReadFails(file, "$file: a source line has 4 fields, not 3, in: src\t/src/A.kt\t0")
  }

  private fun assertReadFails(
    file: Path,
    message: String,
  ) {
    try {
      SourceDependenciesFile.read(file)
      fail("read accepted $file")
    } catch (e: IllegalStateException) {
      assertThat(e.message).isEqualTo(message)
    }
  }
}
