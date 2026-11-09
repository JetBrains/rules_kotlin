package examples.kmp.shared.di

import me.tatarka.inject.annotations.Inject

/**
 * An `expect` class with an `@Inject` constructor, whose `actual` is in the sources of each platform (as
 * a Kotlin Gradle build injects one): KSP of a platform resolves the type to the actual, with its
 * constructor.
 */
@Inject
expect class Clock() {
  fun now(): Long
}
