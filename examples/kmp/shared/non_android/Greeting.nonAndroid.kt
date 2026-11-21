package examples.kmp.shared

/**
 * The greeting with the bitness of the platform, for the platforms other than Android: the code of
 * Gradle's intermediate source set `nonAndroidMain`, which the JVM and native both list and Android
 * does not, so it is the fragment `jvm-native`, between `common` and their own sources.
 */
fun detailedGreeting(): String = "${greeting()}, ${if (PlatformInfo().is64Bit) 64 else 32}-bit"
