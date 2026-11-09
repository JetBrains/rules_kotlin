package examples.kmp.shared.di

import me.tatarka.inject.annotations.Component

@Component abstract class AppleComponent : SharedComponent

actual fun injectedGreeting(): String = AppleComponent::class.create().repository.greeting()

actual fun injectedNow(): Long = AppleComponent::class.create().repository.now()
