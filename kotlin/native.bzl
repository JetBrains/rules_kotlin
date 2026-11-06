"""Public API for Kotlin/Native rules.

Experimental (prototype):
- kt_native_library: compile .kt -> .klib for the resolved konan target.
- kt_native_binary: link .kt sources + klib deps into a native executable (`bazel run`).
- kt_native_test: link .kt tests + klib deps into a test runner (`bazel test`) for the exec host.
- kt_native_framework: link .kt sources + klib deps into a static Apple framework.
- kt_klib_import: a prebuilt .klib of a konan target (e.g. from Maven) as a klib dep.
- KtKlibInfo: the provider of a klib.

The konan target is selected by Bazel toolchain resolution (the build's --platforms),
not a rule attribute; a kt_klib_import names the one of its klib. The rules build with
the Kotlin platform type native (//kotlin/settings:kotlin_platform_type), so a dep that
selects on @rules_kotlin//kotlin/native/platforms:native_<konan target> is their klib.
See examples/native for usage.
"""

load("//kotlin/internal/native:binary.bzl", _kt_native_binary = "kt_native_binary")
load("//kotlin/internal/native:framework.bzl", _kt_native_framework = "kt_native_framework")
load("//kotlin/internal/native:import.bzl", _kt_klib_import = "kt_klib_import")
load("//kotlin/internal/native:library.bzl", _kt_native_library = "kt_native_library")
load("//kotlin/internal/native:providers.bzl", _KtKlibInfo = "KtKlibInfo")
load("//kotlin/internal/native:test.bzl", _kt_native_test = "kt_native_test")

kt_native_library = _kt_native_library
kt_native_binary = _kt_native_binary
kt_native_test = _kt_native_test
kt_native_framework = _kt_native_framework
kt_klib_import = _kt_klib_import
KtKlibInfo = _KtKlibInfo
