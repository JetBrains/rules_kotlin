package examples.kmp.tests

actual fun isPlatformOfTheTest(name: String): Boolean = name.startsWith("JVM ")

actual abstract class RobolectricTest actual constructor()
