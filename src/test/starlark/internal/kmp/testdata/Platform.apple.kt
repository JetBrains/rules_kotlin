package kmp.test

actual fun platformName(): String = "Apple"

actual class PlatformInfo actual constructor() {
    actual val name: String = platformName()
}
