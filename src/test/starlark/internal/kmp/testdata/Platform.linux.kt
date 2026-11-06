package kmp.test

actual fun platformName(): String = "Linux"

actual class PlatformInfo actual constructor() {
    actual val name: String = platformName()
}
