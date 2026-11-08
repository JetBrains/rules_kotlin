package examples.kmp.tests

import examples.kmp.shared.PlatformInfo
import examples.kmp.shared.detailedGreeting
import examples.kmp.shared.greeting
import examples.kmp.shared.greetingAfter
import examples.kmp.shared.platformName
import kotlinx.coroutines.runBlocking
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds

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

  @Test
  fun greetsInDetail() {
    // The intermediate source set, which the JVM library compiles with the common one and its own sources.
    assertEquals("${greeting()}, 64-bit", detailedGreeting())
  }

  @Test
  fun greetsAfterADelay() {
    // The common code runs on the JVM variant of kotlinx.coroutines.
    assertEquals(greeting(), runBlocking { greetingAfter(10.milliseconds) })
  }
}
