package examples.kmp.tests

import kotlin.experimental.ExperimentalNativeApi
import kotlin.native.OsFamily
import kotlin.native.Platform
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.toKString
import platform.posix.getenv

@OptIn(ExperimentalNativeApi::class)
actual fun isPlatformOfTheTest(name: String): Boolean =
  when (Platform.osFamily) {
    OsFamily.MACOSX -> name == "macOS"
    OsFamily.LINUX -> name == "Linux"
    else -> false
  }

@OptIn(ExperimentalForeignApi::class)
actual fun testEnvironment(name: String): String? = getenv(name)?.toKString()

actual abstract class RobolectricTest actual constructor()
