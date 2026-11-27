package examples.kmp.tests

import kotlin.experimental.ExperimentalNativeApi
import kotlin.native.OsFamily
import kotlin.native.Platform

@OptIn(ExperimentalNativeApi::class)
actual fun isPlatformOfTheTest(name: String): Boolean =
  when (Platform.osFamily) {
    OsFamily.MACOSX -> name == "macOS"
    OsFamily.LINUX -> name == "Linux"
    else -> false
  }

actual abstract class RobolectricTest actual constructor()
