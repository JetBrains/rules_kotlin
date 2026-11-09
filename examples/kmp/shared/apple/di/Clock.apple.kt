package examples.kmp.shared.di

import me.tatarka.inject.annotations.Inject
import platform.Foundation.NSDate
import platform.Foundation.timeIntervalSince1970

@Inject
actual class Clock actual constructor() {
  actual fun now(): Long = (NSDate().timeIntervalSince1970 * 1000).toLong()
}
