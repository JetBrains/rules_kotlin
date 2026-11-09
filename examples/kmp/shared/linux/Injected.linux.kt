package examples.kmp.shared.di

import examples.kmp.shared.greeting

// The Linux targets have no component: this group does not run KSP.
actual fun injectedGreeting(): String = greeting()

actual fun injectedNow(): Long = Clock().now()
