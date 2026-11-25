package examples.kmp.shared

import kotlinx.coroutines.delay
import kotlin.time.Duration

/** Common code, compiled for every platform with its own platformName(). */
fun greeting(): String = greetingFrom(platformName())

/** Internal to the module: only the tests of //shared, its friends, call it (see //tests:shared_test). */
internal fun greetingFrom(platform: String): String = "Hello from $platform"

/**
 * The greeting, after waiting for [duration]: common code calling kotlinx.coroutines, of which each
 * platform compiles against its own variant, from @kmp_maven.
 */
suspend fun greetingAfter(duration: Duration): String {
  delay(duration)
  return greeting()
}
