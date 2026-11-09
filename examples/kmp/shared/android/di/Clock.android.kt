package examples.kmp.shared.di

import android.os.SystemClock
import me.tatarka.inject.annotations.Inject

@Inject
actual class Clock actual constructor() {
  actual fun now(): Long = SystemClock.elapsedRealtime()
}
