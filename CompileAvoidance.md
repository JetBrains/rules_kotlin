[![Build Status](https://badge.buildkite.com/a8860e94a7378491ce8f50480e3605b49eb2558cfa851bbf9b.svg)](https://buildkite.com/bazel/kotlin-postsubmit)

# Compilation Avoidance

# ABI support

**rules_kotlin** now supports compilation avoidance through the use of ABI jars (also known as
interface or header jars) for classpath dependencies. This can have significant performance wins for
non-ABI affecting changes since down stream recompilation can be avoided in such cases. 

This feature can be enabled through the `experimental_use_abi_jars` flag in the tool chain as
follows

```python
load("//kotlin:core.bzl", "define_kt_toolchain")


define_kt_toolchain(
    name = "kotlin_toolchain",
    experimental_use_abi_jars = True,
)
```

This feature is implemented using the Jetbrains Kotlin JvmABI compiler plugin for generating headers
for Kotlin code. Unfortunately there are some known bugs with this plugin that affect less than 1%
of targets.
* https://youtrack.jetbrains.com/issue/KT-40340
* https://youtrack.jetbrains.com/issue/KT-40133

If you encounter such bugs, ABI generation can be disabled on a per target basis by setting the
following tag

```python
load("//kotlin:jvm.bzl", "kt_jvm_library")

kt_jvm_library(
    name = "framework",
    tags = ["kt_abi_plugin_incompatible"],
)
```

Depending on your compiler version you may find non-public symbols in your ABI jar such as [internal declarations](https://youtrack.jetbrains.com/issue/KT-65690) or [effectively private classes](https://youtrack.jetbrains.com/issue/KT-64590). 
Exclusion of these symbols from the ABI jar can be enabled through the `experimental_treat_internal_as_private_in_abi_jars` and `experimental_remove_private_classes_in_abi_jars` flags in addition to `experimental_use_abi_jars` flag when defining the toolchain as follows

```python
load("//kotlin:core.bzl", "define_kt_toolchain")


define_kt_toolchain(
    name = "kotlin_toolchain",
    experimental_use_abi_jars = True,
    experimental_treat_internal_as_private_in_abi_jars = True,
    experimental_remove_private_classes_in_abi_jars = True,
)
```

In order to completely remove debug information from the ABI jar, the `experimental_remove_debug_info_in_abi_jars` flag can be used along with `experimental_use_abi_jars`

```python
load("//kotlin:core.bzl", "define_kt_toolchain")


define_kt_toolchain(
    name = "kotlin_toolchain",
    experimental_use_abi_jars = True,
    experimental_remove_debug_info_in_abi_jars = True,
)
```

If you encounter bugs in older compiler versions such as [KT-71525](https://youtrack.jetbrains.com/issue/KT-71525) then ABI generation with only public symbols can be disabled on a per target basis by setting the following tags

```python
load("//kotlin:jvm.bzl", "kt_jvm_library")

kt_jvm_library(
    name = "framework",
    tags = [
        "kt_treat_internal_as_private_in_abi_plugin_incompatible", 
        "kt_remove_private_classes_in_abi_plugin_incompatible", 
        "kt_remove_debug_info_in_abi_plugin_incompatible"
    ],
)
```

# Kotlin Multiplatform

## JVM and Android

The JVM and Android libraries of a `kt_multiplatform_library` (`<name>_jvm` and `<name>_android`),
and every other `kt_jvm_library` or `kt_android_library` with `kmp_fragments`, emit an ABI jar when
the Kotlin toolchain sets `experimental_use_abi_jars = True`, like any other `kt_jvm_library` or
`kt_android_library`. Their dependents then compile against it; by default `experimental_use_abi_jars`
is off and they compile against the class jar.

The ABI jar keeps internal declarations, unless the toolchain sets
`experimental_treat_internal_as_private_in_abi_jars` or `experimental_remove_private_classes_in_abi_jars`.
In that case, a target that lists the library in `associates` compiles against its class jar. The tag
`kt_abi_plugin_incompatible` turns the ABI jar off for one target, as above.

## Kotlin/Native

The build setting `experimental_native_header_klibs` turns on header klibs: the declarations of a
klib without function bodies. It is off by default, and is set on the command line or in `.bazelrc`:

```
build --@rules_kotlin//kotlin/settings:experimental_native_header_klibs=true
```

With it on, every `kt_native_library` writes `<name>.header.klib` beside `<name>.klib`, in the same
compilation. Then:

* the libraries that depend on it compile against its header klib;
* the sources of `kt_native_binary`, `kt_native_test` and `kt_native_framework` compile against the
  header klibs of their deps;
* the links read the full klibs, and a framework exports full klibs;
* a header klib keeps internal declarations, so a `kt_native_test` still sees those of its
  `associates`;
* a `kt_klib_import`, and the KSP action of a multiplatform library, keep reading full klibs.

The tag `kt_native_header_klib_incompatible` turns the header klib off for one library. Its
dependents then compile against its full klib.

```python
load("@rules_kotlin//kotlin:native.bzl", "kt_native_library")

kt_native_library(
    name = "framework",
    tags = ["kt_native_header_klib_incompatible"],
)
```

## What stays cached

Measured with Kotlin and Kotlin/Native 2.4.21.

* **Header klib.** It stays the same, so the compilations of the dependents stay cached, when:
  * the body of a private, internal or public function that is not `inline` changes;
  * private declarations are added;
  * lines move in a file without `inline` functions.

  It changes with an internal or public signature, the value of a `const val`, a default argument
  or the body of an `inline` function.
* **ABI jar, internal declarations kept.** It stays the same when the body of a private, internal or
  public function that is not `inline` changes, and when a private function is added. It changes
  with a new private class, an internal or public signature, or the body of an `inline` function.
* **Links** read full klibs, so a binary, test or framework relinks after every edit to a library it
  links.

The integration test `//src/test/integration:compile_avoidance_test` checks the first two for an
edit to a private body and for a public signature edit.

## Limitations

* **Sealed hierarchies.** A header klib leaves out the private subclasses of a public sealed type.
  In a dependent, a `when` over that type without `else` then compiles, and throws
  `NoWhenBranchMatchedException` at run time when it meets a private subclass. A build with
  `experimental_native_header_klibs` off rejects that `when`, so keep a CI build with the setting
  off. On the JVM the same gap exists only when the toolchain removes private classes or internal
  declarations from ABI jars.
* **Inline functions.** In a file that declares an `inline` function, an edit that changes the
  length of the file changes the header klib, and the dependents recompile. Keep `inline` functions
  in files of their own.
* **Experimental compiler option.** The header klib comes from the experimental konanc option
  `-Xheader-klib-path`, tried with Kotlin/Native 2.4.21. Of the compiler plugins, only
  kotlinx.serialization was tried. The tag `kt_native_header_klib_incompatible` covers a library
  whose plugins do not work with it.
