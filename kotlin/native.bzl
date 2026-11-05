"""Public API for Kotlin/Native rules.

Experimental (prototype):
- kt_native_library: compile .kt -> .klib for the resolved konan target.
- kt_native_binary: link .kt sources + klib deps into a native executable (`bazel run`).
- kt_native_test: link .kt tests + klib deps into a test runner (`bazel test`) for the exec host.
- kt_native_framework: link .kt sources + klib deps into a static Apple framework.
- KtKlibInfo: the provider of a klib.

The konan target is selected by Bazel toolchain resolution (the build's --platforms),
not a rule attribute. See examples/native for usage.
"""

load("//kotlin/internal/native:binary.bzl", _kt_native_binary = "kt_native_binary")
load("//kotlin/internal/native:framework.bzl", _kt_native_framework = "kt_native_framework")
load("//kotlin/internal/native:library.bzl", _kt_native_library = "kt_native_library")
load("//kotlin/internal/native:providers.bzl", _KtKlibInfo = "KtKlibInfo")
load("//kotlin/internal/native:test.bzl", _kt_native_test = "kt_native_test")

kt_native_library = _kt_native_library
kt_native_binary = _kt_native_binary
kt_native_test = _kt_native_test
kt_native_framework = _kt_native_framework
KtKlibInfo = _KtKlibInfo
