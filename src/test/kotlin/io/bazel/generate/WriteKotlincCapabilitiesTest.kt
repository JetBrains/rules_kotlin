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

  // The generator column-aligns map entries and varies list/dict spacing, so assertions on its output
  // must not hard-code spacing. Tests state the expected snippet as readable text; matching strips all
  // whitespace from both sides so layout differences (alignment padding, comma spacing) are ignored.
  private fun normalizeWhitespace(s: String): String = s.filterNot { it.isWhitespace() }

  private fun assertMatching(content: String, expected: String) {
    assertWithMessage("expected to find (ignoring whitespace):\n$expected")
      .that(normalizeWhitespace(content).contains(normalizeWhitespace(expected)))
      .isTrue()
  }

  private fun countIgnoringWhitespace(content: String, expected: String): Int =
    normalizeWhitespace(content).split(normalizeWhitespace(expected)).size - 1

  @Test
  fun smokeTest() {
    val tmp = Files.createTempDirectory("WriteKotlincCapabilitiesTest")
    WriteKotlincCapabilities.main("--out", tmp.toString())

    // check generated_opts file was created
    val generatedOpts = tmp.resolve(WriteKotlincCapabilities.generatedOptsName(testVersion))
    assertThat(Files.exists(generatedOpts)).isTrue()
    val content = Files.readString(generatedOpts)
    assertThat(content).contains("GENERATED_KOPTS")
    // assert stable flag from kotlin-compiler-arguments-description
    assertThat(content).contains("-progressive")
  }

  @Test
  fun `boolean options generate bool structure`() {
    val tmp = Files.createTempDirectory("WriteKotlincCapabilitiesTest")
    WriteKotlincCapabilities.main("--out", tmp.toString())

    val generatedOpts = Files.readString(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(testVersion)))

    // Boolean options should use attr.bool
    assertMatching(generatedOpts, "type = attr.bool")

    // Boolean options should map True to the flag
    assertMatching(generatedOpts, "value_to_flag = {True:")
  }

  @Test
  fun `string options use map_value_to_flag`() {
    val tmp = Files.createTempDirectory("WriteKotlincCapabilitiesTest")
    WriteKotlincCapabilities.main("--out", tmp.toString())

    val generatedOpts = Files.readString(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(testVersion)))

    // String options should use _map_string_flag helper
    assertMatching(generatedOpts, "map_value_to_flag = _map_string_flag")

    // The helper function should be defined
    assertThat(generatedOpts).contains("def _map_string_flag(flag):")
  }

  @Test
  fun `string list options use map_string_list_flag`() {
    val tmp = Files.createTempDirectory("WriteKotlincCapabilitiesTest")
    WriteKotlincCapabilities.main("--out", tmp.toString())

    val generatedOpts = Files.readString(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(testVersion)))

    // String list options should use _map_string_list_flag helper
    assertMatching(generatedOpts, "map_value_to_flag = _map_string_list_flag")

    // The helper function should be defined
    assertThat(generatedOpts).contains("def _map_string_list_flag(flag):")

    // String list options should have type = attr.string_list
    assertMatching(generatedOpts, "type = attr.string_list")
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
    val opts20 = Files.readString(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(KotlinReleaseVersion.v2_0_0)))
    val opts21 = Files.readString(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(KotlinReleaseVersion.v2_1_0)))
    val opts22 = Files.readString(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(KotlinReleaseVersion.v2_2_0)))
    val opts23 = Files.readString(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(KotlinReleaseVersion.v2_3_0)))

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

    val opts21 = Files.readString(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(KotlinReleaseVersion.v2_1_0)))
    val opts22 = Files.readString(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(KotlinReleaseVersion.v2_2_0)))

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

    val opts23 = Files.readString(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(KotlinReleaseVersion.v2_3_0)))

    assertMatching(opts23, "values = [\"\", \"first-only\", \"first-only-warn\", \"param-property\"]")
    assertMatching(opts23, "values = [\"\", \"ignore\", \"strict\", \"warn\"]")
  }

  @Test
  fun `active and removed arguments are deduplicated`() {
    val tmp = Files.createTempDirectory("WriteKotlincCapabilitiesTest")
    WriteKotlincCapabilities.main("--out", tmp.toString())

    val opts21 = Files.readString(tmp.resolve(WriteKotlincCapabilities.generatedOptsName(KotlinReleaseVersion.v2_1_0)))
    val count = countIgnoringWhitespace(opts21, "\"x_ir_inliner\": struct(")
    assertThat(count).isEqualTo(1)
  }
}
