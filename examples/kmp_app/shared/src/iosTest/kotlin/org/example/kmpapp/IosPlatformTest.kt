package org.example.kmpapp

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue
import kotlinx.cinterop.ExperimentalForeignApi
import platform.Foundation.NSBundle
import platform.Foundation.NSProcessInfo
import platform.Foundation.NSString
import platform.Foundation.NSUTF8StringEncoding
import platform.Foundation.stringWithContentsOfFile
import platform.UIKit.UIDevice

actual fun isExpectedPlatformName(name: String): Boolean =
  name.startsWith("${UIDevice.currentDevice.systemName()} ")

class IosPlatformTest {
  @Test
  fun usesIosPlatformActualAndUiDevice() {
    val platform = assertIs<IOSPlatform>(getPlatform())
    val device = UIDevice.currentDevice
    assertTrue(device.systemName().isNotBlank())
    assertTrue(device.systemVersion.isNotBlank())
    assertEquals("${device.systemName()} ${device.systemVersion}", platform.name)
    assertEquals("Hello, ${platform.name}!", Greeting().greet())
  }

  @OptIn(ExperimentalForeignApi::class)
  @Test
  fun loadsBundleResourceAndSimulatorEnv() {
    val path = checkNotNull(
      NSBundle.allBundles
        .filterIsInstance<NSBundle>()
        .firstNotNullOfOrNull { it.pathForResource("ios_fixture", ofType = "txt") },
    ) { "ios_fixture.txt is not in any loaded NSBundle" }
    val content = checkNotNull(
      NSString.stringWithContentsOfFile(path, encoding = NSUTF8StringEncoding, error = null),
    ) { "Could not read $path" }
    assertEquals("Hello from iosTest bundle", content.trim())
    assertEquals(
      "kmp_app_shared_env",
      NSProcessInfo.processInfo.environment["KMP_APP_TEST_ENV"] as? String,
    )
  }
}
