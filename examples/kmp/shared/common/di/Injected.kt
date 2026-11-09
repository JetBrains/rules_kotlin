package examples.kmp.shared.di

/** The greeting of the repository the component of the platform builds, from the code KSP generated. */
expect fun injectedGreeting(): String

/** The time of the clock the component of the platform injects: the `actual` of an `@Inject expect class`. */
expect fun injectedNow(): Long
