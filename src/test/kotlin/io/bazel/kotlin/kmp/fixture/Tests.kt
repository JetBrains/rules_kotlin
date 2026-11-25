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
package io.bazel.kotlin.kmp.fixture

import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Suite

class FirstTest {
  @Test
  fun passes() = Unit
}

class SecondTest {
  @Test
  fun passes() = Unit

  @Test
  fun passesToo() = Unit
}

abstract class AbstractTest {
  @Test
  fun inherited() = Unit
}

class InheritingTest : AbstractTest()

interface TestContract {
  @Test
  fun contract() = Unit
}

@RunWith(Suite::class)
@Suite.SuiteClasses(FirstTest::class)
class NamedSuite

class Outer {
  class NestedTest {
    @Test
    fun passes() = Unit
  }

  inner class InnerTest {
    @Test
    fun neverRuns() = Unit
  }
}

private class PrivateTest {
  @Test
  fun neverRuns() = Unit
}

class Helper {
  fun help() = Unit

  companion object {
    init {
      System.setProperty("fixture_initialized", "true")
    }
  }
}
