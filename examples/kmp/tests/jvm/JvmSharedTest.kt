package examples.kmp.tests

import examples.kmp.shared.PlatformInfo
import examples.kmp.shared.di.JvmComponent
import examples.kmp.shared.di.create
import examples.kmp.shared.di.injectedNow
import examples.kmp.shared.greeting
import examples.kmp.shared.platformName
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

actual fun readTestFixture(): String {
  val path = "tests/fixtures/greeting.txt"
  val stream = checkNotNull(SharedTest::class.java.classLoader?.getResourceAsStream(path)) {
    "$path is not on the JVM test classpath"
  }
  return stream.bufferedReader().use { it.readText().trim() }
}

actual fun expectedInjectedGreeting(): String = "${greeting()} (injected, ${platformName()})"

/** Compiled as the `jvm` leaf of //tests:shared_test. */
class JvmSharedTest {
  @Test
  fun describesTheJvm() {
    val info = PlatformInfo()
    assertEquals(platformName(), info.name)
    assertTrue(info.is64Bit)
  }

  @Test
  fun buildsKspJvmComponent() {
    val repository = JvmComponent::class.create().repository
    assertEquals("${greeting()} (injected, ${platformName()})", repository.greeting())
    assertTrue(injectedNow() > 0L)
  }
}
