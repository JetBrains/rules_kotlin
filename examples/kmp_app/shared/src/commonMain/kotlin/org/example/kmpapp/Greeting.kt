package org.example.kmpapp

import kotlinx.coroutines.delay

/** Common code, which the Android app calls from Kotlin and the iOS app from Swift. */
class Greeting {
  private val platform: Platform = getPlatform()

  fun greet(): String = "Hello, ${platform.name}!"

  /**
   * The greeting, a moment later: common code suspending in kotlinx.coroutines. Swift calls it as
   * an `async` function.
   */
  suspend fun greetLater(): String {
    delay(100)
    return greet()
  }
}
