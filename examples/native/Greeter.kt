package greeter

fun greet(name: String): String = "hello, $name"

class Greeter(val who: String) {
    fun message(): String = greet(who)
}

// Only greeter and its associates, e.g. greeter_test, see it.
internal fun shout(name: String): String = greet(name).uppercase()
