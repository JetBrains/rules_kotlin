package examples.kmp.shared.di

import kotlin.time.TimeSource

// No component on Linux: the class is plain, like the greeting of this group.
actual class Clock actual constructor() {
  private val start = TimeSource.Monotonic.markNow()

  actual fun now(): Long = start.elapsedNow().inWholeMilliseconds
}
