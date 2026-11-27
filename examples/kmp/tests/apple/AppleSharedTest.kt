package examples.kmp.tests

import examples.kmp.shared.PlatformInfo
import examples.kmp.shared.di.AppleComponent
import examples.kmp.shared.di.create
import examples.kmp.shared.di.injectedNow
import examples.kmp.shared.greeting
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

actual fun expectedInjectedGreeting(): String = "${greeting()} (injected, macOS)"

/** Compiled into the `apple` test fragment, refining `native`. */
class AppleSharedTest {
  @Test
  fun describesAppleHost() {
    val info = PlatformInfo()
    assertEquals("macOS", info.name)
    assertTrue(info.is64Bit)
  }

  @Test
  fun buildsKspAppleComponent() {
    val repository = AppleComponent::class.create().repository
    assertEquals("${greeting()} (injected, macOS)", repository.greeting())
    assertTrue(injectedNow() > 0L)
  }
}
