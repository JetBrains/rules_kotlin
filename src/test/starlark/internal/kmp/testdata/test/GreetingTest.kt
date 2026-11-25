package kmp.test

import kotlin.test.Test
import kotlin.test.assertEquals

expect fun expectedPlatform(): String

class GreetingTest {
    @Test
    fun greets() {
        assertEquals("Hello from ${expectedPlatform()}", greeting())
    }
}
