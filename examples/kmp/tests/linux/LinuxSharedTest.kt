package examples.kmp.tests

import examples.kmp.shared.PlatformInfo
import examples.kmp.shared.di.Clock
import examples.kmp.shared.di.injectedGreeting
import examples.kmp.shared.di.injectedNow
import examples.kmp.shared.greeting
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

actual fun expectedInjectedGreeting(): String = greeting()

/** Compiled into the `linux` test fragment, refining `native`. */
class LinuxSharedTest {
  @Test
  fun describesLinuxHost() {
    val info = PlatformInfo()
    assertEquals("Linux", info.name)
    assertTrue(info.is64Bit)
  }

  @Test
  fun usesFallbackBindingsWithoutKsp() {
    assertEquals(greeting(), injectedGreeting())
    assertTrue(injectedNow() >= 0L)
    assertTrue(Clock().now() >= 0L)
  }
}
