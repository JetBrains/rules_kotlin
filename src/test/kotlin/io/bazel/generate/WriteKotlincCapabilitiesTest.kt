package io.bazel.generate

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import io.bazel.kotlin.generate.WriteKotlincCapabilities
import org.jetbrains.kotlin.arguments.dsl.base.KotlinReleaseVersion
import org.junit.Test
import java.nio.file.Files

class WriteKotlincCapabilitiesTest {
  // Use the latest supported version for testing
  private val testVersion = KotlinReleaseVersion.v2_3_0

  // JDK-8-compatible equivalent of readUtf8(path) (UTF-8); these files are always valid UTF-8.
  private fun readUtf8(path: java.nio.file.Path): String = String(Files.readAllBytes(path), Charsets.UTF_8)

  @Test
  fun smokeTest() {
    val tmp = Files.createTempDirectory("WriteKotlincCapabilitiesTest")
    WriteKotlincCapabilities.main("--out", tmp.toString())

    // check generated_opts file was created
    val generatedOpts = tmp.resolve(WriteKotlincCapabilities.generatedOptsName(testVersion))
    assertThat(Files.exists(generatedOpts)).isTrue()
    val content = readUtf8(generatedOpts)
    assertThat(content).contains("GENERATED_KOPTS")
    // assert stable flag from kotlin-compiler-arguments-description
    assertThat(content).contains("-progressive")
  }

  @Test
  fun `boolean options generate bool structure`() {
    val tmp = Files.createTempDirectory("WriteKotlincCapabilitiesTest")
    WriteKotlincCapabilities.main("--out", tmp.toString())

    val generatedOpts = readUtf8(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(testVersion)))

    // Boolean options should use attr.bool
    assertThat(generatedOpts).contains("type = attr.bool")

    // Boolean options should map True to the flag
    assertThat(generatedOpts).contains("value_to_flag = {True:")
  }

  @Test
  fun `string options use map_value_to_flag`() {
    val tmp = Files.createTempDirectory("WriteKotlincCapabilitiesTest")
    WriteKotlincCapabilities.main("--out", tmp.toString())

    val generatedOpts = readUtf8(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(testVersion)))

    // String options should use _map_string_flag helper
    assertThat(generatedOpts).contains("map_value_to_flag = _map_string_flag")

    // The helper function should be defined
    assertThat(generatedOpts).contains("def _map_string_flag(flag):")
  }

  @Test
  fun `string list options use map_string_list_flag`() {
    val tmp = Files.createTempDirectory("WriteKotlincCapabilitiesTest")
    WriteKotlincCapabilities.main("--out", tmp.toString())

    val generatedOpts = readUtf8(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(testVersion)))

    // String list options should use _map_string_list_flag helper
    assertThat(generatedOpts).contains("map_value_to_flag = _map_string_list_flag")

    // The helper function should be defined
    assertThat(generatedOpts).contains("def _map_string_list_flag(flag):")

    // String list options should have type = attr.string_list
    assertThat(generatedOpts).contains("type = attr.string_list")
  }

  @Test
  fun `generates files for all supported versions`() {
    val tmp = Files.createTempDirectory("WriteKotlincCapabilitiesTest")
    WriteKotlincCapabilities.main("--out", tmp.toString())

    for (version in WriteKotlincCapabilities.SUPPORTED_VERSIONS) {
      val generatedOptsFile = tmp.resolve(WriteKotlincCapabilities.generatedOptsName(version))
      assertWithMessage("generated_opts file for ${version.major}.${version.minor}")
        .that(Files.exists(generatedOptsFile))
        .isTrue()
    }
  }

  @Test
  fun `version filtering works correctly`() {
    val tmp = Files.createTempDirectory("WriteKotlincCapabilitiesTest")
    WriteKotlincCapabilities.main("--out", tmp.toString())

    // XXlenient-mode was introduced in v2.2.0 - should be in 2.2 and 2.3 but not in 2.0 and 2.1
    val opts20 = readUtf8(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(KotlinReleaseVersion.v2_0_0)))
    val opts21 = readUtf8(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(KotlinReleaseVersion.v2_1_0)))
    val opts22 = readUtf8(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(KotlinReleaseVersion.v2_2_0)))
    val opts23 = readUtf8(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(KotlinReleaseVersion.v2_3_0)))

    assertThat(opts20).doesNotContain("-XXlenient-mode")
    assertThat(opts21).doesNotContain("-XXlenient-mode")
    assertThat(opts22).contains("-XXlenient-mode")
    assertThat(opts23).contains("-XXlenient-mode")
  }

  @Test
  fun `experimental flags marked deprecated when stable counterpart exists`() {
    val tmp = Files.createTempDirectory("WriteKotlincCapabilitiesTest")
    WriteKotlincCapabilities.main("--out", tmp.toString())

    // -jvm-default was introduced in 2.2, -Xjvm-default exists since 1.2
    // In 2.1: only -Xjvm-default exists, no deprecation prefix from us
    // In 2.2+: both exist, -Xjvm-default should have our DEPRECATED prefix

    val opts21 = readUtf8(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(KotlinReleaseVersion.v2_1_0)))
    val opts22 = readUtf8(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(KotlinReleaseVersion.v2_2_0)))

    // In 2.1, -Xjvm-default should NOT have our DEPRECATED prefix (stable version doesn't exist yet)
    assertThat(opts21).contains("-Xjvm-default")
    assertThat(opts21).doesNotContain("DEPRECATED: Use -jvm-default instead")

    // In 2.2, -Xjvm-default SHOULD have our DEPRECATED prefix (stable -jvm-default now exists)
    assertThat(opts22).contains("-Xjvm-default")
    assertThat(opts22).contains("DEPRECATED: Use -jvm-default instead")

    // Also verify -jvm-default exists in 2.2
    assertThat(opts22).contains("\"-jvm-default\"")
  }

  @Test
  fun `enum metadata is generated for key string flags`() {
    val tmp = Files.createTempDirectory("WriteKotlincCapabilitiesTest")
    WriteKotlincCapabilities.main("--out", tmp.toString())

    val opts23 = readUtf8(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(KotlinReleaseVersion.v2_3_0)))

    // Exact output: the generator emits no space after the leading `["",` (see _KOPTS struct emission).
    assertThat(opts23).contains("values = [\"\",\"first-only\", \"first-only-warn\", \"param-property\"]")
    assertThat(opts23).contains("values = [\"\",\"ignore\", \"strict\", \"warn\"]")
  }

  @Test
  fun `active and removed arguments are deduplicated`() {
    val tmp = Files.createTempDirectory("WriteKotlincCapabilitiesTest")
    WriteKotlincCapabilities.main("--out", tmp.toString())

    val opts21 = readUtf8(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(KotlinReleaseVersion.v2_1_0)))
    // The deduplicated entry must appear exactly once (match the quoted key, which is unambiguous).
    val count = opts21.split("\"x_ir_inliner\":").size - 1
    assertThat(count).isEqualTo(1)
  }

  @Test
  fun `generator output is byte-for-byte idempotent across runs`() {
    val first = Files.createTempDirectory("WriteKotlincCapabilitiesTest-run1")
    val second = Files.createTempDirectory("WriteKotlincCapabilitiesTest-run2")
    WriteKotlincCapabilities.main("--out", first.toString())
    WriteKotlincCapabilities.main("--out", second.toString())

    // Every generated file must be identical across regenerations. A failure here means the generator
    // became non-deterministic (e.g. an unsorted collection, a timestamp, or hash-ordered iteration),
    // which would make the checked-in generated_opts_*.bazel files churn on every regeneration.
    val names =
      WriteKotlincCapabilities.SUPPORTED_VERSIONS
        .filter { it >= KotlinReleaseVersion.v2_0_0 }
        .map { WriteKotlincCapabilities.generatedOptsName(it) } + "templates.bzl"

    for (name in names) {
      assertWithMessage("generator output for $name must be byte-for-byte identical across regenerations")
        .that(readUtf8(second.resolve(name)))
        .isEqualTo(readUtf8(first.resolve(name)))
    }
  }
}
