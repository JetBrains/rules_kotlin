package greeter

import kotlin.test.Test
import kotlin.test.assertEquals

class GreeterTest {
    @Test
    fun greets() {
        assertEquals("hello, native", Greeter("native").message())
    }

    // shout is internal to greeter, whose associate greeter_test is.
    @Test
    fun shouts() {
        assertEquals("HELLO, NATIVE", shout("native"))
    }
}
