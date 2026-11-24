import kotlin.test.Test
import kotlin.test.assertEquals
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.refTo
import kotlinx.cinterop.toKString
import platform.posix.fclose
import platform.posix.fgets
import platform.posix.fopen

class DataTest {
    // `bazel test` starts the test in its runfiles tree, where a file of its data is at its path
    // from the root of the workspace.
    @OptIn(ExperimentalForeignApi::class)
    @Test
    fun readsItsData() {
        val file = checkNotNull(fopen("greeting.txt", "r")) { "greeting.txt is not in the runfiles" }
        val buffer = ByteArray(64)
        val line = fgets(buffer.refTo(0), buffer.size, file)?.toKString()
        fclose(file)
        assertEquals("hello, runfiles", line?.trim())
    }
}
