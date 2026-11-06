package examples.kmp.shared

import kotlinx.coroutines.delay
import kotlin.time.Duration

/** Common code, compiled for every platform with its own platformName(). */
fun greeting(): String = "Hello from ${platformName()}"

/**
 * The greeting, after waiting for [duration]: common code calling kotlinx.coroutines, of which each
 * platform compiles against its own variant, from @kmp_maven.
 */
suspend fun greetingAfter(duration: Duration): String {
  delay(duration)
  return greeting()
}
