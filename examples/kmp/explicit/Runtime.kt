package examples.kmp.explicit

/** The runtime the code was compiled for. */
expect val runtime: String

fun describe(): String = "compiled for $runtime"
