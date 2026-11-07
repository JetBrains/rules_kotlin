"""Public API for Kotlin Multiplatform.

Experimental:
- kt_source_set: a source set, Kotlin sources that the Kotlin/Native, JVM and Android rules listing it
  in their `source_sets` compile with their own sources, as the K2 fragments of one compilation, so
  `expect` declarations and their `actual` ones are in one module.
- kt_multiplatform_library: a multiplatform library from a declaration like the one of the Kotlin
  Gradle plugin: its source sets, a library per platform and an alias selecting the library of its
  consumer: the native one for a Kotlin/Native rule
  (`@rules_kotlin//kotlin/native/platforms:native_<konan target>`), the Android one for an Android
  platform and the JVM one otherwise.
- KtSourceSetInfo: the provider of a source set.

kt_multiplatform_library declares a kt_android_library when it has an `android` platform, so this
file loads the Android rules. See examples/kmp and examples/kmp_app for usage, and docs/kmp.md
for the guide.
"""

load(
    "//kotlin/internal/kmp:multiplatform.bzl",
    _kt_multiplatform_library = "kt_multiplatform_library",
)
load(
    "//kotlin/internal/kmp:source_set.bzl",
    _KtSourceSetInfo = "KtSourceSetInfo",
    _kt_source_set = "kt_source_set",
)

kt_source_set = _kt_source_set
kt_multiplatform_library = _kt_multiplatform_library
KtSourceSetInfo = _KtSourceSetInfo
