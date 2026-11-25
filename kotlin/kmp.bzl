"""Public API for Kotlin Multiplatform.

Experimental:
- kt_multiplatform_library: a multiplatform library declared once for its platforms: a library per
  platform, compiling the sources it shares with other platforms as K2 fragments, and an alias
  selecting the library of its consumer.
- kt_multiplatform_test: the tests of such a library, declared the same way: a test per platform,
  compiling the test sources it shares with other platforms as K2 fragments, with the library of
  the platform as associate, and a test_suite of them.
- kt_jvm_ksp_sources, kt_native_ksp_sources: KSP2 over the sources of a platform, as a separate
  action whose generated Kotlin files the library of the platform compiles.

kt_multiplatform_library declares a kt_android_library when it has an `android` platform, and
kt_multiplatform_test a kt_android_local_test, so this file loads the Android rules. See
examples/kmp and examples/kmp_app for usage, and docs/kmp.md for the guide.
"""

load(
    "//kotlin/internal/kmp:ksp.bzl",
    _kt_jvm_ksp_sources = "kt_jvm_ksp_sources",
    _kt_native_ksp_sources = "kt_native_ksp_sources",
)
load(
    "//kotlin/internal/kmp:multiplatform.bzl",
    _kt_multiplatform_library = "kt_multiplatform_library",
)
load(
    "//kotlin/internal/kmp:test.bzl",
    _kt_multiplatform_test = "kt_multiplatform_test",
)

kt_jvm_ksp_sources = _kt_jvm_ksp_sources
kt_native_ksp_sources = _kt_native_ksp_sources
kt_multiplatform_library = _kt_multiplatform_library
kt_multiplatform_test = _kt_multiplatform_test
