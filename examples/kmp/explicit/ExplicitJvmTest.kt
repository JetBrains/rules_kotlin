package examples.kmp.explicit

import org.junit.Test
import kotlin.test.assertEquals

class ExplicitJvmTest {
  @Test
  fun describesTheJvm() {
    assertEquals("compiled for the JVM", describe())
  }
}
