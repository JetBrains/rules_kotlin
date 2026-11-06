package kmp.test

actual fun platformName(): String = "JVM " + System.getProperty("java.version")

actual class PlatformInfo actual constructor() {
    actual val name: String = platformName()
}
