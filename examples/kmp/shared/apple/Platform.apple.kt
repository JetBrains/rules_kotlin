package examples.kmp.shared

import kotlin.experimental.ExperimentalNativeApi

@OptIn(ExperimentalNativeApi::class)
actual fun platformName(): String =
  when (Platform.osFamily) {
    OsFamily.IOS -> "iOS"
    OsFamily.MACOSX -> "macOS"
    else -> Platform.osFamily.name
  }

@OptIn(ExperimentalNativeApi::class)
actual class PlatformInfo actual constructor() {
  actual val name: String = platformName()
  actual val is64Bit: Boolean = Platform.cpuArchitecture.bitness == 64
}
