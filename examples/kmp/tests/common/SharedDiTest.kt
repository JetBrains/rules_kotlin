package examples.kmp.tests

import examples.kmp.shared.PlatformInfo
import examples.kmp.shared.di.injectedGreeting
import examples.kmp.shared.di.injectedNow
import examples.kmp.shared.platformName
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Base class for common tests that touch Android framework APIs on Android: the `android` `actual`
 * attaches `RobolectricTestRunner` with SDK 35, while the `jvm` and `native` actuals are empty base
 * classes.
 */
expect abstract class RobolectricTest()

/** Expected result of [injectedGreeting] on each platform (KSP on JVM/Android/Apple, plain on Linux). */
expect fun expectedInjectedGreeting(): String

/**
 * Shared DI and platform tests across all four platforms, exercising KSP-generated
 * `AndroidComponent` and `SystemClock.elapsedRealtime()` under Robolectric on Android.
 */
class SharedDiTest : RobolectricTest() {
  @Test
  fun describesThePlatform() {
    val info = PlatformInfo()
    assertEquals(platformName(), info.name)
    assertTrue(info.is64Bit)
  }

  @Test
  fun injectsThePlatformGreeting() {
    assertEquals(expectedInjectedGreeting(), injectedGreeting())
  }

  @Test
  fun readsTheInjectedClock() {
    assertTrue(injectedNow() >= 0L)
  }
}
