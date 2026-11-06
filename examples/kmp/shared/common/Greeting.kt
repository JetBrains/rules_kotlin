package examples.kmp.shared

/** Common code, compiled for every platform with its own platformName(). */
fun greeting(): String = "Hello from ${platformName()}"
