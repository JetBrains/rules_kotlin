package test

expect fun platformName(): String

fun greeting(): String = "Hello from " + platformName()
