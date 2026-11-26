@file:OptIn(ExperimentalNativeApi::class)

package io.bazel.kotlin.native.xctest

import kotlin.experimental.ExperimentalNativeApi
import kotlin.native.internal.test.testLauncherEntryPoint

/**
 * Runs the tests of the Kotlin/Native test library this file is compiled into, and returns the exit
 * code of the Kotlin test runner: 0 when every test passed. The XCTest case of
 * kt_native_xctest_library calls it by its C name, to which the rule appends a suffix for its
 * target: this file is a template.
 */
@CName("rules_kotlin_xctest_run")
public fun runKotlinTests(): Int = testLauncherEntryPoint(emptyArray())
