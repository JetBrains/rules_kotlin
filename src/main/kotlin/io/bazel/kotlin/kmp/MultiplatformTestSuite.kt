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

import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Suite
import org.junit.runners.model.InitializationError
import org.junit.runners.model.RunnerBuilder
import java.io.File
import java.lang.reflect.Modifier
import java.net.JarURLConnection
import java.util.jar.JarFile

/**
 * The default test class of the JVM and Android tests of `kt_multiplatform_test`: a JUnit 4 suite of
 * the test classes of the jar of the test.
 *
 * A test of a `kt_multiplatform_test` compiles the test sources of every fragment of its platform,
 * so no single class names its tests. The macro passes the jar the test compiles into as the system
 * property [TEST_JAR_PROPERTY], its path from the root of its repository. The suite runs every
 * class of that jar that JUnit 4 can run, and fails when it cannot find the jar, or a test class in
 * it: a test that runs nothing must not pass.
 */
@RunWith(MultiplatformTestSuite.Runner::class)
class MultiplatformTestSuite {
  class Runner(
    suite: Class<*>,
    builder: RunnerBuilder,
  ) : Suite(
      builder,
      suite,
      testClasses(System.getProperty(TEST_JAR_PROPERTY), suite.classLoader).toTypedArray(),
    )

  companion object {
    const val TEST_JAR_PROPERTY = "rules_kotlin.kmp.test_jar"

    private const val MANIFEST = "META-INF/MANIFEST.MF"

    /**
     * The test classes of the jar on the class path of [loader] whose path ends with [testJar], by
     * name: the public, concrete classes that are no inner classes and have a method with [Test],
     * their own or inherited, or are annotated with [RunWith].
     *
     * @throws InitializationError without [testJar], without such a jar, or without a test class
     *   in it; JUnit reports it as a failed test of the suite.
     */
    @JvmStatic
    fun testClasses(
      testJar: String?,
      loader: ClassLoader,
    ): List<Class<*>> {
      if (testJar.isNullOrEmpty()) {
        throw InitializationError(
          "the system property $TEST_JAR_PROPERTY is not set: kt_multiplatform_test sets it to " +
            "the jar of the test, whose test classes this suite runs",
        )
      }
      val suffix = "/" + testJar.trimStart('/')
      val jar =
        jars(loader).firstOrNull { it.invariantSeparatorsPath.endsWith(suffix) }
          ?: throw InitializationError(
            "no jar on the class path ends with $testJar, the value of the system property " +
              TEST_JAR_PROPERTY,
          )
      val classes =
        classNames(jar)
          .map { Class.forName(it, false, loader) }
          .filter(::isTestClass)
      if (classes.isEmpty()) {
        throw InitializationError(
          "$testJar has no test class: a public, concrete class with a method annotated with " +
            "@org.junit.Test",
        )
      }
      return classes
    }

    /**
     * The jars [loader] loads classes from. Each has a manifest, which the loader finds however it
     * was given its class path: as a list of jars, or as one jar whose manifest names the others.
     */
    private fun jars(loader: ClassLoader): List<File> =
      loader
        .getResources(MANIFEST)
        .asSequence()
        .mapNotNull { (it.openConnection() as? JarURLConnection)?.jarFileURL }
        .filter { it.protocol == "file" }
        .map { File(it.toURI()) }
        .distinct()
        .toList()

    private fun classNames(jar: File): List<String> =
      JarFile(jar).use { file ->
        file
          .entries()
          .asSequence()
          .map { it.name }
          .filter { it.endsWith(".class") && !it.startsWith("META-INF/") }
          .filterNot { it.endsWith("module-info.class") }
          .map { it.removeSuffix(".class").replace('/', '.') }
          .sorted()
          .toList()
      }

    private fun isTestClass(candidate: Class<*>): Boolean {
      val modifiers = candidate.modifiers
      val concrete = !Modifier.isAbstract(modifiers) && !candidate.isInterface
      if (!concrete || !Modifier.isPublic(modifiers)) {
        return false
      }
      // JUnit cannot construct a class that needs an instance of the class around it.
      val inner = candidate.isMemberClass && !Modifier.isStatic(modifiers)
      if (inner || candidate.isAnonymousClass || candidate.isLocalClass) {
        return false
      }
      // The methods of an interface that Kotlin compiles into its DefaultImpls are static.
      return candidate.isAnnotationPresent(RunWith::class.java) ||
        candidate.methods.any {
          it.isAnnotationPresent(Test::class.java) && !Modifier.isStatic(it.modifiers)
        }
    }
  }
}
