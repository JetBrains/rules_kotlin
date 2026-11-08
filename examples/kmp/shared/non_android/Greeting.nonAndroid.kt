package examples.kmp.shared

/**
 * The greeting with the bitness of the platform, for the platforms other than Android: the code of
 * an intermediate source set, Gradle's `nonAndroidMain`, which the JVM library and the native groups
 * compile between the common source set and their own, and the Android library does not.
 */
fun detailedGreeting(): String = "${greeting()}, ${if (PlatformInfo().is64Bit) 64 else 32}-bit"
