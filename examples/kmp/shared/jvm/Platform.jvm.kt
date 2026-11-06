package examples.kmp.shared

actual fun platformName(): String = "JVM " + System.getProperty("java.specification.version")

actual class PlatformInfo actual constructor() {
  actual val name: String = platformName()
  actual val is64Bit: Boolean = System.getProperty("os.arch").contains("64")
}
