package examples.kmp.tests

import examples.kmp.shared.PlatformInfo
import examples.kmp.shared.detailedGreeting
import examples.kmp.shared.greeting
import examples.kmp.shared.greetingAfter
import examples.kmp.shared.platformName
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds

class GreetingNativeTest {
  @Test
  fun greetsFromTheHost() {
    // The exec hosts of Kotlin/Native: macOS (the Apple group) and Linux (the Linux group).
    assertTrue(platformName() == "macOS" || platformName() == "Linux", platformName())
    assertEquals("Hello from ${platformName()}", greeting())
  }

  @Test
  fun describesTheHost() {
    val info = PlatformInfo()
    assertEquals(platformName(), info.name)
    assertTrue(info.is64Bit)
  }

  @Test
  fun greetsInDetail() {
    // The intermediate source set, which the group of the host refines besides the common one.
    assertEquals("${greeting()}, 64-bit", detailedGreeting())
  }

  @Test
  fun greetsAfterADelay() {
    // The common code runs on the klib of kotlinx.coroutines of the host's konan target.
    assertEquals(greeting(), runBlocking { greetingAfter(10.milliseconds) })
  }
}
