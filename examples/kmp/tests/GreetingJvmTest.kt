package examples.kmp.tests

import examples.kmp.shared.PlatformInfo
import examples.kmp.shared.greeting
import examples.kmp.shared.platformName
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class GreetingJvmTest {
  @Test
  fun greetsFromTheJvm() {
    assertTrue(platformName().startsWith("JVM "), platformName())
    assertEquals("Hello from ${platformName()}", greeting())
  }

  @Test
  fun describesTheJvm() {
    assertEquals(platformName(), PlatformInfo().name)
  }
}
