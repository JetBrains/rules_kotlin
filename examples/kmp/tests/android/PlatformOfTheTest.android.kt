package examples.kmp.tests

actual fun isPlatformOfTheTest(name: String): Boolean = name.startsWith("Android ")

actual fun testEnvironment(name: String): String? = System.getenv(name)
