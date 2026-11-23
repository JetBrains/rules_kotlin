package io.bazel.kotlin.builder.tasks.jvm

import com.google.common.truth.Truth.assertThat
import io.bazel.kotlin.builder.Deps.Dep
import io.bazel.kotlin.builder.DirectoryType
import io.bazel.kotlin.builder.KotlinJvmTestBuilder
import io.bazel.kotlin.builder.utils.jars.SourceDependencies
import io.bazel.kotlin.builder.utils.jars.SourceDependenciesFile
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.nio.file.Path
import java.nio.file.Paths
import java.util.function.Consumer

@RunWith(Parameterized::class)
class KotlinBuilderJvmSourceDependenciesTest(private val buildToolsApi: Boolean) {
  companion object {
    @JvmStatic
    @Parameterized.Parameters(name = "buildToolsApi={0}")
    fun data(): Collection<Array<Any>> = listOf(arrayOf(true), arrayOf(false))
  }

  val ctx = KotlinJvmTestBuilder()

  private val testFixturesDep = Dep.fromLabel(":JdepsParserTestFixtures")

  private fun runCompileTask(block: (c: KotlinJvmTestBuilder.TaskBuilder) -> Unit): Dep =
    ctx.runCompileTask(
      Consumer { c: KotlinJvmTestBuilder.TaskBuilder ->
        if (buildToolsApi) {
          c.useBuildToolsApi()
        }
        c.outputJar()
        c.outputJdeps()
        c.compileKotlin()
        block(c)
      },
    )

  /** The path of a source of the last compilation. */
  private fun source(name: String): Path =
    ctx.directory(DirectoryType.SOURCES).resolve(name).toAbsolutePath()

  /**
   * The records the jdeps plugin wrote for the last compilation, by the path of the source. The
   * implicit jars a source also uses explicitly are dropped, as in the jdeps.
   */
  private fun records(): Map<Path, SourceDependencies> =
    SourceDependenciesFile
      .read(ctx.directory(DirectoryType.TEMP).resolve("source_dependencies"))
      .map { (source, record) ->
        Paths.get(source) to
          SourceDependencies(record.explicitJars, record.implicitJars - record.explicitJars)
      }.toMap()

  @Test
  fun `each analyzed source has a record with the jars it uses`() {
    val indirectInterfaceDef =
      runCompileTask { c ->
        c.addSource(
          "IndirectInterface.kt",
          """
          package something

          interface IndirectInterface
          """,
        )
      }
    val directInterfaceDef =
      runCompileTask { c ->
        c.addSource(
          "DirectInterface.kt",
          """
          package something

          interface DirectInterface : IndirectInterface
          """,
        )
        c.addDirectDependencies(indirectInterfaceDef)
      }

    runCompileTask { c ->
      c.addSource(
        "Calls.kt",
        """
        package something

        val result = JavaClass.staticMethod()
        """,
      )
      c.addSource(
        "Extends.kt",
        """
        package something

        interface SubInterface : DirectInterface
        """,
      )
      c.addSource("Empty.kt", "package something")
      c.addDirectDependencies(testFixturesDep, directInterfaceDef)
      c.addTransitiveDependencies(indirectInterfaceDef)
    }

    assertThat(records())
      .containsExactly(
        source("Calls.kt"),
        SourceDependencies(setOf(testFixturesDep.singleCompileJar()), emptySet()),
        source("Extends.kt"),
        SourceDependencies(
          setOf(directInterfaceDef.singleCompileJar()),
          setOf(indirectInterfaceDef.singleCompileJar()),
        ),
        source("Empty.kt"),
        SourceDependencies(emptySet(), emptySet()),
      )
  }
}
