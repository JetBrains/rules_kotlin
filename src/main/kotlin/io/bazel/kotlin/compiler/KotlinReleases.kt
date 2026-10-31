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
package io.bazel.kotlin.compiler

/**
 * The release of a Kotlin version string, without the classifier: "2.5.0-Beta2" gives 2.5.0 and
 * "2.5.20-dev-1532" gives 2.5.20. Null when the string does not start with three dot-separated
 * numbers of a release.
 */
fun kotlinReleaseOf(version: String): KotlinVersion? {
  val numbers = version.substringBefore('-').split('.')
  if (numbers.size != 3) {
    return null
  }
  val components =
    numbers.map { number ->
      number.toIntOrNull()?.takeIf { it in 0..KotlinVersion.MAX_COMPONENT_VALUE } ?: return null
    }
  return KotlinVersion(components[0], components[1], components[2])
}
