package io.bazel.kotlin.builder.tasks.jvm

import com.google.common.truth.Truth.assertThat
import com.google.devtools.build.lib.view.proto.Deps.Dependency.Kind
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.JUnit4

@RunWith(JUnit4::class)
class JDepsGeneratorTest {
  private fun kindsByPath(
    directDependencies: List<String>,
    explicitJars: List<String>,
    implicitJars: List<String>,
  ): List<Pair<String, Kind>> =
    jdepsOf("//pkg:target", directDependencies, explicitJars, implicitJars)
      .dependencyList
      .map { it.path to it.kind }

  @Test
  fun `jdeps list the unused direct dependencies and the used jars sorted by path`() {
    assertThat(
      kindsByPath(
        directDependencies = listOf("d.jar", "a.jar", "d.jar"),
        explicitJars = listOf("c.jar", "a.jar"),
        implicitJars = listOf("b.jar", "c.jar"),
      ),
    ).containsExactly(
      "a.jar" to Kind.EXPLICIT,
      "b.jar" to Kind.IMPLICIT,
      "c.jar" to Kind.EXPLICIT,
      "d.jar" to Kind.UNUSED,
    ).inOrder()
  }

  @Test
  fun `a direct dependency used only implicitly lists as unused, then implicit`() {
    assertThat(
      kindsByPath(
        directDependencies = listOf("a.jar"),
        explicitJars = emptyList(),
        implicitJars = listOf("a.jar"),
      ),
    ).containsExactly("a.jar" to Kind.UNUSED, "a.jar" to Kind.IMPLICIT).inOrder()
  }

  @Test
  fun `jdeps record the label and success`() {
    val jdeps = jdepsOf("//pkg:target", emptyList(), emptyList(), emptyList())

    assertThat(jdeps.ruleLabel).isEqualTo("//pkg:target")
    assertThat(jdeps.success).isTrue()
    assertThat(jdeps.dependencyList).isEmpty()
  }
}
