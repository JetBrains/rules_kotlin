package kmp.test

import kotlin.test.Test
import kotlin.test.assertTrue

class JvmLinuxTest {
    @Test
    fun names() {
        assertTrue(expectedPlatform().isNotEmpty())
    }
}
