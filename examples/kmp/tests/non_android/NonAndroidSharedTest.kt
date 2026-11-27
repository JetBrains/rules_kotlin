package examples.kmp.tests

import examples.kmp.shared.detailedGreeting
import examples.kmp.shared.di.injectedGreeting
import examples.kmp.shared.greeting
import kotlin.test.Test
import kotlin.test.assertEquals

/** Shared across `jvm`, `linux_x64` and `macos_arm64` via the `non_android` alias. */
class NonAndroidSharedTest {
  @Test
  fun greetsInDetail() {
    assertEquals("${greeting()}, 64-bit", detailedGreeting())
  }

  @Test
  fun injectsThePlatformGreeting() {
    assertEquals(expectedInjectedGreeting(), injectedGreeting())
  }
}
