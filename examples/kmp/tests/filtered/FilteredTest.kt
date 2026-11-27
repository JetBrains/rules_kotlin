package examples.kmp.tests

import examples.kmp.shared.greeting
import examples.kmp.shared.greetingFrom
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.fail

/**
 * Selected explicitly via `jvm = dict(test_class = ...)` and `native = dict(args = ["--ktest_filter=..."])`.
 */
class SelectedTest {
  @Test
  fun runsSelectedClass() {
    assertEquals("Hello from filtered", greetingFrom("filtered"))
    assertEquals("Hello from ${examples.kmp.shared.platformName()}", greeting())
  }
}

/**
 * Compiled into the same test targets as [SelectedTest], so the suite fails if runner filtering is ignored.
 */
class UnselectedTest {
  @Test
  fun skippedByRunnerConfiguration() {
    fail("UnselectedTest must be excluded by jvm.test_class and native --ktest_filter")
  }
}
