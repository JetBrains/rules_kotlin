import kotlin.test.BeforeClass
import kotlin.test.Test
import kotlin.test.assertEquals

// Three tests of two classes, which sharded_test splits into two shards and
// test_selection_test selects among, by shard and by filter. The declarations are public for
// strict_test, which compiles them in explicit API mode.
public class FirstSelectionTest {
    @Test
    public fun one() {
        assertEquals(1, "a".length)
    }

    @Test
    public fun two() {
        assertEquals(2, "ab".length)
    }
}

public class SecondSelectionTest {
    public companion object {
        // Runs before the tests of the class, and not when none of them is selected.
        @BeforeClass
        public fun beforeClass() {
            println("SecondSelectionTest.beforeClass")
        }
    }

    @Test
    public fun three() {
        assertEquals(3, "abc".length)
    }
}
