"""Public API for Kotlin Multiplatform.

Experimental:
- kt_multiplatform_library: a multiplatform library whose platforms each list every source they
  compile: a library per platform, compiling the sources it shares with other platforms as K2
  fragments, so `expect` declarations and their `actual` ones are in one module, and an alias
  selecting the library of its consumer: the native one for a Kotlin/Native rule
  (`@rules_kotlin//kotlin/native/platforms:native_<konan target>`), the Android one for an Android
  platform and the JVM one otherwise.
- kt_jvm_ksp_sources, kt_native_ksp_sources: KSP2 over the sources of a platform, as a separate
  action whose generated Kotlin files the library of the platform compiles.

kt_multiplatform_library declares a kt_android_library when it has an `android` platform, so this
file loads the Android rules. See examples/kmp and examples/kmp_app for usage, and docs/kmp.md
for the guide.
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

kt_jvm_ksp_sources = _kt_jvm_ksp_sources
kt_native_ksp_sources = _kt_native_ksp_sources
kt_multiplatform_library = _kt_multiplatform_library
