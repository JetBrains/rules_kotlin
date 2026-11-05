import kotlin.test.Test
import kotlin.test.assertEquals

// failing_test runs only `passes` (see its args); failing_test_exit_code_test runs both and expects
// the test runner to fail.
class FailingTest {
    @Test
    fun passes() {
        assertEquals(2, 1 + 1)
    }

    @Test
    fun fails() {
        assertEquals(3, 1 + 1)
    }
}
