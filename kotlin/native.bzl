"""Public API for Kotlin/Native rules.

Experimental (prototype):
- kt_native_library: compile .kt -> .klib for the resolved konan target.
- kt_native_binary: link .kt sources + klib deps into a native executable.

The konan target is selected by Bazel toolchain resolution (the build's --platforms),
not a rule attribute. See examples/native for usage.
"""

load("//kotlin/internal/native:binary.bzl", _kt_native_binary = "kt_native_binary")
load("//kotlin/internal/native:library.bzl", _kt_native_library = "kt_native_library")
load("//kotlin/internal/native:providers.bzl", _KtNativeInfo = "KtNativeInfo")

kt_native_library = _kt_native_library
kt_native_binary = _kt_native_binary
KtNativeInfo = _KtNativeInfo
