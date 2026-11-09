package examples.kmp.shared.di

import me.tatarka.inject.annotations.Inject

@Inject
actual class Clock actual constructor() {
  actual fun now(): Long = System.currentTimeMillis()
}
