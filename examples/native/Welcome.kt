package greeterkit

import greeter.greet

// The API of the GreeterKit framework, next to the one of greeter, which it exports.
class Welcome {
    fun text(): String = greet("Kotlin/Native")
}
