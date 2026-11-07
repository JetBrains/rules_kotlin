package org.example.kmpapp

import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals

class GreetingTest {
  @Test
  fun greetsThePlatform() {
    assertEquals("Hello, ${getPlatform().name}!", Greeting().greet())
  }

  @Test
  fun greetsLater() {
    assertEquals(Greeting().greet(), runBlocking { Greeting().greetLater() })
  }
}
