package examples.kmp.shared

/**
 * The greeting with the bitness of the platform, for the platforms other than Android: the code of
 * Gradle's intermediate source set `nonAndroidMain`, the alias `non_android` of the library, so it
 * is the fragment `non_android`, between `common` and the sources of the JVM and the native groups.
 */
fun detailedGreeting(): String = "${greeting()}, ${if (PlatformInfo().is64Bit) 64 else 32}-bit"
