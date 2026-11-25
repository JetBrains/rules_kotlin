/*
 * Copyright 2026 The Bazel Authors. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package io.bazel.kotlin.kmp

import com.google.common.truth.Truth.assertThat
import io.bazel.kotlin.kmp.MultiplatformTestSuite.Companion.TEST_JAR_PROPERTY
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.JUnitCore
import org.junit.runner.Result
import org.junit.runner.RunWith
import org.junit.runners.JUnit4
import org.junit.runners.model.InitializationError

/**
 * Runs [MultiplatformTestSuite] over the jars of two libraries on the class path of this test,
 * fixture/Tests.kt and fixture/NoTests.kt, named as kt_multiplatform_test names the jar of a test:
 * by its path from the root of the repository.
 */
@RunWith(JUnit4::class)
class MultiplatformTestSuiteTest {
  private val testsJar = System.getProperty("fixture_tests_jar")
  private val noTestsJar = System.getProperty("fixture_no_tests_jar")
  private val loader = MultiplatformTestSuiteTest::class.java.classLoader

  private fun testClasses(jar: String?): List<String> =
    MultiplatformTestSuite.testClasses(jar, loader).map { it.name }

  private fun failure(jar: String?): String =
    assertThrows(InitializationError::class.java) { testClasses(jar) }.causes.single().message!!

  private fun setTestJar(jar: String?) {
    if (jar == null) {
      System.clearProperty(TEST_JAR_PROPERTY)
    } else {
      System.setProperty(TEST_JAR_PROPERTY, jar)
    }
  }

  private fun runSuite(jar: String?): Result {
    val previous = System.getProperty(TEST_JAR_PROPERTY)
    setTestJar(jar)
    try {
      return JUnitCore().run(MultiplatformTestSuite::class.java)
    } finally {
      setTestJar(previous)
    }
  }

  @Test
  fun `finds the classes JUnit can run, by name`() {
    // Not the abstract class, the interface, the inner class, the private class or the class
    // without tests.
    assertThat(testClasses(testsJar))
      .containsExactly(
        "io.bazel.kotlin.kmp.fixture.FirstTest",
        "io.bazel.kotlin.kmp.fixture.InheritingTest",
        "io.bazel.kotlin.kmp.fixture.NamedSuite",
        "io.bazel.kotlin.kmp.fixture.Outer\$NestedTest",
        "io.bazel.kotlin.kmp.fixture.SecondTest",
      ).inOrder()
  }

  @Test
  fun `finds the jar by the end of its path`() {
    assertThat(testClasses("/$testsJar")).hasSize(5)
    assertThat(testClasses(testsJar.substringAfter('/'))).hasSize(5)

    // Not by the end of its name.
    assertThat(failure(testsJar.substringAfterLast('/').drop(1)))
      .contains("no jar on the class path ends with")
  }

  @Test
  fun `loads the classes without initializing them`() {
    testClasses(testsJar)

    // Helper, which no test of the fixture uses, sets it when it is initialized.
    assertThat(System.getProperty("fixture_initialized")).isNull()
  }

  @Test
  fun `fails without the property`() {
    assertThat(failure(null)).contains("the system property rules_kotlin.kmp.test_jar is not set")
    assertThat(failure("")).contains("the system property rules_kotlin.kmp.test_jar is not set")
  }

  @Test
  fun `fails without the jar`() {
    assertThat(failure("no/such/test.jar"))
      .isEqualTo(
        "no jar on the class path ends with no/such/test.jar, the value of the system property " +
          "rules_kotlin.kmp.test_jar",
      )
  }

  @Test
  fun `fails without a test class`() {
    assertThat(failure(noTestsJar)).startsWith("$noTestsJar has no test class")
  }

  @Test
  fun `runs the tests of the classes`() {
    val result = runSuite(testsJar)

    // The test of FirstTest runs again in NamedSuite.
    assertThat(result.failures).isEmpty()
    assertThat(result.runCount).isEqualTo(6)
  }

  @Test
  fun `a suite that finds no test fails`() {
    for (jar in listOf(null, "no/such/test.jar", noTestsJar)) {
      val result = runSuite(jar)

      assertThat(result.wasSuccessful()).isFalse()
      assertThat(result.failureCount).isEqualTo(1)
    }
    assertThat(runSuite(noTestsJar).failures.single().message).contains("has no test class")
  }
}
