/*
 * Copyright 2025 The Bazel Authors. All rights reserved.
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
package io.bazel.kotlin.builder.tasks

import com.google.common.truth.Truth.assertThat
import io.bazel.kotlin.compiler.kotlinReleaseOf
import org.junit.Test

class KotlinReleasesTest {
  @Test
  fun testReleaseWithoutClassifier() {
    assertThat(kotlinReleaseOf("2.4.21")).isEqualTo(KotlinVersion(2, 4, 21))
  }

  @Test
  fun testClassifierDoesNotCount() {
    assertThat(kotlinReleaseOf("2.5.0-Beta2")).isEqualTo(KotlinVersion(2, 5, 0))
    assertThat(kotlinReleaseOf("2.5.20-dev-1532")).isEqualTo(KotlinVersion(2, 5, 20))
  }

  @Test
  fun testMalformedVersionHasNoRelease() {
    assertThat(kotlinReleaseOf("2.5")).isNull()
    assertThat(kotlinReleaseOf("2.5.x")).isNull()
    assertThat(kotlinReleaseOf("2.5.300")).isNull()
    assertThat(kotlinReleaseOf("")).isNull()
  }

  @Test
  fun testReleaseOrderDecidesTheAvailabilityOfAnOption() {
    val availableSince = KotlinVersion(2, 5, 0)
    assertThat(kotlinReleaseOf("2.5.0-Beta2")!! >= availableSince).isTrue()
    assertThat(kotlinReleaseOf("2.5.20-dev-1532")!! >= availableSince).isTrue()
    assertThat(kotlinReleaseOf("2.4.21")!! >= availableSince).isFalse()
  }
}
