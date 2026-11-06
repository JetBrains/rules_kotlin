/*
 * Copyright 2026 The Bazel Authors. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 */
package io.bazel.kotlin.builder.tasks

import com.google.common.truth.Truth.assertThat
import io.bazel.kotlin.builder.tasks.jvm.btapi.absoluteFragmentSources
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.JUnit4
import java.nio.file.Paths

/**
 * The Build Tools API passes the sources to the compiler as absolute paths, so the paths of the
 * sources of the K2 fragments are made absolute the same way, and no other argument changes.
 */
@RunWith(JUnit4::class)
class AbsoluteFragmentSourcesTest {
  @Test
  fun `relative fragment sources are resolved like the sources`() {
    val source = "bazel-out/darwin_arm64-fastbuild/bin/shared/Platform.kt"

    assertThat(absoluteFragmentSources(listOf("-Xfragment-sources=shared-common:$source")))
      .containsExactly("-Xfragment-sources=shared-common:${Paths.get(source).toAbsolutePath()}")
  }

  @Test
  fun `absolute fragment sources and other arguments are unchanged`() {
    val absolute = Paths.get("shared/Platform.kt").toAbsolutePath()
    val arguments =
      listOf(
        "-Xmulti-platform",
        "-Xexpect-actual-classes",
        "-Xfragments=shared-common,shared-jvm",
        "-Xfragment-sources=shared-common:$absolute",
        "-Xfragment-refines=shared-jvm:shared-common",
        "-Xfragment-sources=no-separator",
        "-opt-in=kotlin.RequiresOptIn",
      )

    assertThat(absoluteFragmentSources(arguments)).containsExactlyElementsIn(arguments).inOrder()
  }
}
