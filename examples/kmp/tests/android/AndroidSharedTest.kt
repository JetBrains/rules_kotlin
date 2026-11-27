package examples.kmp.tests

import android.os.Build
import examples.kmp.shared.di.AndroidComponent
import examples.kmp.shared.di.create
import examples.kmp.shared.di.injectedNow
import examples.kmp.shared.greeting
import examples.kmp.shared.platformName
import java.time.Duration
import kotlin.test.Test
import kotlin.test.assertEquals
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowSystemClock

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
actual abstract class RobolectricTest actual constructor()

actual fun readTestFixture(): String {
  val path = "tests/fixtures/greeting.txt"
  val stream = checkNotNull(SharedTest::class.java.classLoader?.getResourceAsStream(path)) {
    "$path is not on the Android local test classpath"
  }
  return stream.bufferedReader().use { it.readText().trim() }
}

actual fun expectedInjectedGreeting(): String = "${greeting()} (injected, ${platformName()})"

/** Compiled as the `android` leaf of //tests:shared_test and executed under Robolectric. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AndroidSharedTest {
  @Test
  fun greetsFromAndroidSdk35() {
    assertEquals(35, Build.VERSION.SDK_INT)
    assertEquals("Android 35", platformName())
    assertEquals("Hello from Android 35", greeting())
  }

  @Test
  fun providesRobolectricApplicationContext() {
    val application = RuntimeEnvironment.getApplication()
    assertEquals("examples.kmp.tests", application.packageName)
    assertEquals(35, application.applicationInfo.targetSdkVersion)
  }

  @Test
  fun advancesInjectedClockViaShadowSystemClock() {
    val before = injectedNow()
    ShadowSystemClock.advanceBy(Duration.ofMillis(1_250))
    assertEquals(before + 1_250L, injectedNow())
    assertEquals(
      "Hello from Android 35 (injected, Android 35)",
      AndroidComponent::class.create().repository.greeting(),
    )
  }
}
