package examples.kmp.shared.di

import me.tatarka.inject.annotations.Component

@Component abstract class JvmComponent : SharedComponent

actual fun injectedGreeting(): String = JvmComponent::class.create().repository.greeting()

actual fun injectedNow(): Long = JvmComponent::class.create().repository.now()
