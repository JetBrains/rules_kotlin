package examples.kmp.shared

import kotlin.experimental.ExperimentalNativeApi

actual fun platformName(): String = "Linux"

@OptIn(ExperimentalNativeApi::class)
actual class PlatformInfo actual constructor() {
  actual val name: String = platformName()
  actual val is64Bit: Boolean = Platform.cpuArchitecture.bitness == 64
}
