package examples.kmp.tests

import examples.kmp.shared.greeting
import examples.kmp.shared.greetingFrom
import examples.kmp.shared.platformName
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Whether [name] is how the platform of the test names itself: each platform has its `actual`. */
expect fun isPlatformOfTheTest(name: String): Boolean

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
}
