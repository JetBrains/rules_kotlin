@file:OptIn(ExperimentalNativeApi::class, ExperimentalForeignApi::class)

package io.bazel.kotlin.native.test

import kotlin.experimental.ExperimentalNativeApi
import kotlin.native.internal.test.GeneratedSuites
import kotlin.native.internal.test.TestCase
import kotlin.native.internal.test.TestSuite
import kotlin.native.internal.test.testLauncherEntryPoint
import kotlin.system.exitProcess
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.toKString
import platform.posix.fclose
import platform.posix.fopen
import platform.posix.getenv

/**
 * The entry point of the test runner of kt_native_test, in place of the one konanc generates: it
 * runs the Kotlin test runner on the tests that `bazel test` selects, which the Kotlin test runner
 * does not read from the environment.
 *
 * - `--test_filter` (TESTBRIDGE_TEST_ONLY) is a regular expression: the tests whose
 *   `<suite name>#<test name>` has a match of it run, as for a JUnit 4 test. The suite name of the
 *   tests of a class is its qualified name. A filter that selects no test fails the test.
 * - `shard_count` (TEST_TOTAL_SHARDS, TEST_SHARD_INDEX): the tests the filter left are dealt to the
 *   shards in turn, in the order they are registered in, so a shard may have none, and passes.
 *
 * The options of the Kotlin test runner in [args], e.g. `--ktest_filter`, select among these tests.
 * Without these variables, e.g. under `bazel run`, every test runs.
 */
public fun main(args: Array<String>) {
    // Bazel fails a sharded test whose runner does not create this file: it tells that the runner
    // knows about shards.
    environment("TEST_SHARD_STATUS_FILE")?.let { path -> fopen(path, "w")?.let { fclose(it) } }

    val suites = GeneratedSuites.suites
    val all = suites.flatMapIndexed { index, suite -> suite.testCases.values.map { SuiteTest(index, it) } }
    var selected = all

    val filter = environment("TESTBRIDGE_TEST_ONLY")
    if (filter != null) {
        val regex = try {
            Regex(filter)
        } catch (e: IllegalArgumentException) {
            fail("The test filter '$filter' is not a regular expression: ${e.message}")
        }
        selected = selected.filter { regex.containsMatchIn("${suites[it.suite].name}#${it.case.name}") }
        if (selected.isEmpty()) {
            fail("No tests found matching the test filter '$filter', a regular expression searched in <suite name>#<test name>")
        }
    }

    val totalShards = environment("TEST_TOTAL_SHARDS")
    if (totalShards != null) {
        val total = totalShards.toIntOrNull()
        val index = environment("TEST_SHARD_INDEX")?.toIntOrNull()
        if (total == null || total < 1 || index == null || index !in 0 until total) {
            fail("TEST_TOTAL_SHARDS is '$totalShards' and TEST_SHARD_INDEX is '${environment("TEST_SHARD_INDEX")}': expected a number of shards and the index of one of them")
        }
        selected = selected.filterIndexed { position, _ -> position % total == index }
    }

    if (selected.size != all.size) {
        val cases = selected.groupBy({ it.suite }, { it.case })
        for (index in suites.indices) {
            suites[index] = SelectedSuite(suites[index], cases[index].orEmpty().associateBy { it.name })
        }
    }

    val exitCode = testLauncherEntryPoint(args)
    if (exitCode != 0) {
        exitProcess(exitCode)
    }
}

/** A test case and the index of its suite in the generated ones. */
private class SuiteTest(val suite: Int, val case: TestCase)

/** [suite] with [testCases] alone. The Kotlin test runner skips a suite without test cases, and its class hooks. */
private class SelectedSuite(
    private val suite: TestSuite,
    override val testCases: Map<String, TestCase>,
) : TestSuite by suite {
    override val size: Int get() = testCases.size

    override fun toString(): String = suite.toString()
}

/** The value of the environment variable [name], or null when it is not set or empty. */
private fun environment(name: String): String? = getenv(name)?.toKString()?.takeIf { it.isNotEmpty() }

/** Prints [message] where the Kotlin test runner reports the tests, and fails the test. */
private fun fail(message: String): Nothing {
    println(message)
    exitProcess(1)
}
