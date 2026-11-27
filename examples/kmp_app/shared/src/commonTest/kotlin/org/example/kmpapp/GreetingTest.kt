package org.example.kmpapp

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking

/** Whether [name] matches the platform `actual` linked into this test target. */
expect fun isExpectedPlatformName(name: String): Boolean

class GreetingTest {
  @Test
  fun greetsThePlatform() {
    val platformName = getPlatform().name
    assertTrue(isExpectedPlatformName(platformName), platformName)
    assertEquals("Hello, $platformName!", Greeting().greet())
  }

  @Test
  fun greetsLater() {
    assertEquals(Greeting().greet(), runBlocking { Greeting().greetLater() })
  }
}
