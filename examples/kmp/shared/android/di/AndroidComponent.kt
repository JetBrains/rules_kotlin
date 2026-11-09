package examples.kmp.shared.di

import me.tatarka.inject.annotations.Component

@Component abstract class AndroidComponent : SharedComponent

actual fun injectedGreeting(): String = AndroidComponent::class.create().repository.greeting()

actual fun injectedNow(): Long = AndroidComponent::class.create().repository.now()
