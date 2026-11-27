package examples.kmp.tests

import examples.kmp.shared.greeting
import examples.kmp.shared.greetingAfter
import examples.kmp.shared.greetingFrom
import examples.kmp.shared.platformName
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.currentTime
import kotlinx.coroutines.test.runTest

/** Whether [name] is how the platform of the test names itself: each platform has its `actual`. */
expect fun isPlatformOfTheTest(name: String): Boolean

/** Loads the text fixture configured for the platform (`resources` on JVM/Android, `data` on native). */
expect fun readTestFixture(): String

/** The value of the environment variable [name] in the process of the test, or null. */
expect fun testEnvironment(name: String): String?

/** A common test: every platform of //tests:shared_test compiles and runs it. */
class SharedTest {
  @Test
  fun greetsFromThePlatformOfTheTest() {
    assertTrue(isPlatformOfTheTest(platformName()), platformName())
    assertEquals("Hello from ${platformName()}", greeting())
  }

  @Test
  fun greetsFromAnyPlatform() {
    // greetingFrom is internal to //shared: the test of a platform is a friend of its library.
    assertEquals("Hello from the tests", greetingFrom("the tests"))
  }

  @OptIn(ExperimentalCoroutinesApi::class)
  @Test
  fun greetsAfterVirtualDelay() = runTest {
    // kotlinx-coroutines-test skips the 5-second delay in virtual time on every platform.
    assertEquals("Hello from ${platformName()}", greetingAfter(5.seconds))
    assertEquals(5_000L, currentTime)
  }

  @Test
  fun readsPlatformTestFixture() {
    assertEquals("Hello from fixture", readTestFixture())
  }

  @Test
  fun readsTheEnvOfTheTest() {
    // The env of //tests:shared_test is that of the test of every platform.
    assertEquals("Hello from env", testEnvironment("KMP_TEST_GREETING"))
  }
}
