package org.example.kmpapp

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs

actual fun isExpectedPlatformName(name: String): Boolean = name.startsWith("Java ")

class JvmPlatformTest {
  @Test
  fun usesJvmPlatformActual() {
    val platform = assertIs<JvmPlatform>(getPlatform())
    assertEquals("Java ${System.getProperty("java.version")}", platform.name)
  }

  @Test
  fun loadsClasspathResourceAndEnv() {
    val path = "shared/src/jvmTest/resources/jvm_fixture.txt"
    val stream = checkNotNull(JvmPlatformTest::class.java.classLoader?.getResourceAsStream(path)) {
      "$path is not on the JVM test classpath"
    }
    val content = stream.bufferedReader().use { it.readText().trim() }
    assertEquals("Hello from jvmTest resource", content)
    assertEquals("kmp_app_shared_env", System.getenv("KMP_APP_TEST_ENV"))
  }
}
