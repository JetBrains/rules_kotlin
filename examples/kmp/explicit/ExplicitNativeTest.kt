package examples.kmp.explicit

import kotlin.test.Test
import kotlin.test.assertEquals

class ExplicitNativeTest {
  @Test
  fun describesKotlinNative() {
    assertEquals("compiled for Kotlin/Native", describe())
  }
}
