package examples.kmp.shared.di

import examples.kmp.shared.PlatformInfo
import examples.kmp.shared.greeting as commonGreeting
import me.tatarka.inject.annotations.Inject
import me.tatarka.inject.annotations.Provides

/**
 * Common code with an `@Inject` constructor: every platform's KSP run sees it with its component. The
 * clock is an `expect` class of the common sources, bound by the `actual` of the platform.
 */
@Inject
class GreetingRepository(private val info: PlatformInfo, private val clock: Clock) {
  fun greeting(): String = "${commonGreeting()} (injected, ${info.name})"

  fun now(): Long = clock.now()
}

/** The bindings of the common code; the `@Component` of each platform implements it. */
interface SharedComponent {
  val repository: GreetingRepository

  @Provides fun platformInfo(): PlatformInfo = PlatformInfo()
}
