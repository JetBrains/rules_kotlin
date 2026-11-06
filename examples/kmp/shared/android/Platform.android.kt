package examples.kmp.shared

import android.os.Build

actual fun platformName(): String = "Android " + Build.VERSION.SDK_INT

actual class PlatformInfo actual constructor() {
  actual val name: String = platformName()
  actual val is64Bit: Boolean = Build.SUPPORTED_64_BIT_ABIS.isNotEmpty()
}
