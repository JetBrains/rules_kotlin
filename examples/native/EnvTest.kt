import kotlin.test.Test
import kotlin.test.assertEquals
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.refTo
import kotlinx.cinterop.toKString
import platform.posix.fclose
import platform.posix.fgets
import platform.posix.fopen
import platform.posix.getenv

@OptIn(ExperimentalForeignApi::class)
class EnvTest {
    // `bazel test` sets the env of the test for its process.
    @Test
    fun readsItsEnv() {
        assertEquals("hello, env", getenv("GREETING")?.toKString())
    }

    // The location of a file of the data is its path from the root of the workspace, where the
    // test finds it in its runfiles tree.
    @Test
    fun readsTheFileItsEnvNames() {
        val path = checkNotNull(getenv("GREETING_FILE")?.toKString()) { "GREETING_FILE is not set" }
        val file = checkNotNull(fopen(path, "r")) { "$path is not in the runfiles" }
        val buffer = ByteArray(64)
        val line = fgets(buffer.refTo(0), buffer.size, file)?.toKString()
        fclose(file)
        assertEquals("hello, runfiles", line?.trim())
    }
}
