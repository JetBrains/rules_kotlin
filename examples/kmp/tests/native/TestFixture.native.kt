package examples.kmp.tests

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.refTo
import kotlinx.cinterop.toKString
import platform.posix.fclose
import platform.posix.fgets
import platform.posix.fopen

@OptIn(ExperimentalForeignApi::class)
actual fun readTestFixture(): String {
  val path = "tests/fixtures/greeting.txt"
  val file = checkNotNull(fopen(path, "r")) { "$path is not in the native test runfiles" }
  return try {
    val buffer = ByteArray(64)
    checkNotNull(fgets(buffer.refTo(0), buffer.size, file)?.toKString()) {
      "$path is empty"
    }.trim()
  } finally {
    fclose(file)
  }
}
