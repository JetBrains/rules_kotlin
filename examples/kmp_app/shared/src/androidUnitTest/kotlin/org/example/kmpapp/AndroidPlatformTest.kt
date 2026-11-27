package org.example.kmpapp

import android.os.Build
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

actual fun isExpectedPlatformName(name: String): Boolean = name.startsWith("Android ")

class AndroidPlatformTest {
  @Test
  fun usesAndroidPlatformActual() {
    val platform = assertIs<AndroidPlatform>(getPlatform())
    assertTrue(Build.VERSION.SDK_INT >= 0)
    assertEquals("Android ${Build.VERSION.SDK_INT}", platform.name)
    assertEquals("Hello, Android ${Build.VERSION.SDK_INT}!", Greeting().greet())
  }

  @Test
  fun readsBazelTestEnvironmentOnAndroidLocalTest() {
    // kt_android_local_test accepts `env` at analysis time, but its stub processor does not emit
    // TestEnvironment, so rule-level `env` only reaches _jvm and _ios; Bazel's runner env is set.
    assertTrue(!System.getenv("TEST_TMPDIR").isNullOrBlank())
  }
}
