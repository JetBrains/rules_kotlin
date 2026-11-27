package examples.kmp.tests

actual fun isPlatformOfTheTest(name: String): Boolean = name.startsWith("JVM ")

actual fun testEnvironment(name: String): String? = System.getenv(name)

actual abstract class RobolectricTest actual constructor()
