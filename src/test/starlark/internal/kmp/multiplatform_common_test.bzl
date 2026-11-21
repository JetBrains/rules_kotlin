"""Tests for the lists kt_multiplatform_library gives the library of each platform: those of its lineage in the hierarchy.

The macro concatenates, per attribute, the lists of the nodes from `common` down to each platform:
the JVM library gets those of `jvm` last, a select() included, and the native library, for its
konan target, those of the groups and the platform above that target. The fixtures stand in for
each level: an alias with the shape of those of kmp_maven for the lists of every platform, and fake
klibs of the konan targets of a group for the lists of that group. The native tests use the fake
toolchains of //src/test/starlark/internal/native (see common.bzl there).
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_java//java:defs.bzl", "java_library")
load("//kotlin:core.bzl", "kt_compiler_plugin")
load("//kotlin:kmp.bzl", "kt_multiplatform_library")
load("//src/test/starlark/internal/native:common.bzl", "fake_klib", "for_target", "not_on_windows")
load(
    ":multiplatform_test.bzl",
    "fragments_graph_unix_test",
    "jvm_test",
    "native_linux_arm64_test",
)

_PACKAGE = "src/test/starlark/internal/kmp"

# The konan targets of the libraries of every platform.
_KONAN_TARGETS = ["ios_simulator_arm64", "linux_arm64", "macos_arm64"]

_OPT_IN = "-opt-in=kotlin.ExperimentalStdlibApi"

_AttrsInfo = provider(
    doc = "The list attributes of a library of a platform, in order.",
    fields = {
        "deps": "list of string: the labels of its deps.",
        "exports": "list of string: the labels of its exports.",
        "opts": "list of string: its opts, those of a native library; none for a JVM one.",
        "plugins": "list of string: the labels of its plugins.",
    },
)

def _attrs_aspect_impl(_target, ctx):
    return [_AttrsInfo(
        deps = [str(dep.label) for dep in ctx.rule.attr.deps],
        exports = [str(export.label) for export in ctx.rule.attr.exports],
        opts = getattr(ctx.rule.attr, "opts", []),
        plugins = [str(plugin.label) for plugin in ctx.rule.attr.plugins],
    )]

_attrs_aspect = aspect(implementation = _attrs_aspect_impl)

def _label(name):
    return str(Label("//%s:%s" % (_PACKAGE, name)))

def _attrs_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The labels the attributes resolve to in the configuration of the library, aliases followed.
    info = analysistest.target_under_test(env)[_AttrsInfo]
    asserts.equals(env, [_label(dep) for dep in ctx.attr.deps], info.deps)
    asserts.equals(env, [_label(export) for export in ctx.attr.exports], info.exports)
    asserts.equals(env, [_label(plugin) for plugin in ctx.attr.plugins], info.plugins)
    asserts.equals(env, ctx.attr.opts, info.opts)

    return analysistest.end(env)

_ATTRS_ATTRS = {
    "deps": attr.string_list(doc = "the names of the expected deps in the package, in order"),
    "exports": attr.string_list(doc = "the names of the expected exports in the package, in order"),
    "opts": attr.string_list(doc = "the expected opts, in order"),
    "plugins": attr.string_list(doc = "the names of the expected plugins in the package, in order"),
}

attrs_jvm_test = analysistest.make(
    _attrs_test_impl,
    attrs = _ATTRS_ATTRS,
    extra_target_under_test_aspects = [_attrs_aspect],
)
attrs_ios_simulator_arm64_test = analysistest.make(
    _attrs_test_impl,
    attrs = _ATTRS_ATTRS,
    config_settings = for_target("ios_simulator_arm64"),
    extra_target_under_test_aspects = [_attrs_aspect],
)
attrs_linux_arm64_test = analysistest.make(
    _attrs_test_impl,
    attrs = _ATTRS_ATTRS,
    config_settings = for_target("linux_arm64"),
    extra_target_under_test_aspects = [_attrs_aspect],
)
attrs_macos_arm64_test = analysistest.make(
    _attrs_test_impl,
    attrs = _ATTRS_ATTRS,
    config_settings = for_target("macos_arm64"),
    extra_target_under_test_aspects = [_attrs_aspect],
)

def _klib_of_targets(name, konan_targets):
    """Declares `name`, an alias selecting for the Kotlin/Native rules a fake klib `<name>_<konan target>` of each of `konan_targets`.

    Args:
      name: the name of the alias, and the prefix of the names of the klibs.
      konan_targets: the konan targets of the klibs, e.g. those of a group of the hierarchy.
    """
    for konan_target in konan_targets:
        fake_klib(
            name = "%s_%s" % (name, konan_target),
            konan_target = konan_target,
            tags = ["manual"],
        )
    native.alias(
        name = name,
        actual = select({
            str(Label("//kotlin/native/platforms:native_" + konan_target)): ":%s_%s" % (name, konan_target)
            for konan_target in konan_targets
        }),
        tags = ["manual"],
    )

def _library_of_every_platform(name):
    """Declares `name`, an alias with the shape of those of kmp_maven.

    It selects, for the Kotlin/Native rules, a fake klib `<name>_native_<konan target>` of each of
    _KONAN_TARGETS, and the java_library `<name>_jvm` otherwise.

    Args:
      name: the name of the alias, and the prefix of the names of the libraries.
    """
    _klib_of_targets(name = name + "_native", konan_targets = _KONAN_TARGETS)
    java_library(
        name = name + "_jvm",
        srcs = ["testdata/PlatformTypeLib.java"],
        tags = ["manual"],
    )
    native.alias(
        name = name,
        actual = select({
            str(Label("//kotlin/native/platforms:native")): ":%s_native" % name,
            "//conditions:default": ":%s_jvm" % name,
        }),
        tags = ["manual"],
    )

def multiplatform_common_test_suite(name):
    """Declares multiplatform libraries with lists at every level and the tests of what the library of each platform gets.

    Args:
      name: the name of the generated test_suite target.
    """

    # The lists of every platform, of jvm, of native, and of the groups and platforms below native.
    _library_of_every_platform(name = "mc_common_dep")
    _library_of_every_platform(name = "mc_common_export")
    java_library(
        name = "mc_jvm_dep",
        srcs = ["testdata/PlatformTypeLib.java"],
        tags = ["manual"],
    )
    java_library(
        name = "mc_jvm_export",
        srcs = ["testdata/PlatformTypeLib.java"],
        tags = ["manual"],
    )
    _klib_of_targets(name = "mc_native_dep", konan_targets = _KONAN_TARGETS)
    _klib_of_targets(name = "mc_apple_dep", konan_targets = ["ios_simulator_arm64", "macos_arm64"])
    for klib, konan_target in [
        ("mc_ios_dep", "ios_simulator_arm64"),
        ("mc_ios_simulator_export", "ios_simulator_arm64"),
        ("mc_linux_dep", "linux_arm64"),
        ("mc_linux_export", "linux_arm64"),
        ("mc_macos_export", "macos_arm64"),
    ]:
        fake_klib(
            name = klib,
            konan_target = konan_target,
            tags = ["manual"],
        )
    java_library(
        name = "mc_plugin_lib",
        srcs = ["testdata/PlatformTypeLib.java"],
        tags = ["manual"],
    )
    for plugin in ["apple", "common", "jvm", "linux", "native"]:
        kt_compiler_plugin(
            name = "mc_%s_plugin" % plugin,
            id = "test.%s" % plugin,
            tags = ["manual"],
            deps = [":mc_plugin_lib"],
        )

    # The deps of jvm are a select(), which the common deps come before all the same; linux_arm64
    # gets the lists of linux, macos_arm64 those of apple and macos, and ios_simulator_arm64 those of
    # apple, ios and its own. The opts of native are those of every konan target.
    kt_multiplatform_library(
        name = "mc_attrs",
        platforms = [
            "jvm",
            "linux_arm64",
            "macos_arm64",
            "ios_simulator_arm64",
        ],
        srcs = ["testdata/Platform.kt"],
        deps = [":mc_common_dep"],
        exports = [":mc_common_export"],
        plugins = [":mc_common_plugin"],
        native = dict(opts = [_OPT_IN]),
        deps_apple = [":mc_apple_dep"],
        deps_ios = [":mc_ios_dep"],
        deps_jvm = select({"//conditions:default": [":mc_jvm_dep"]}),
        deps_linux = [":mc_linux_dep"],
        deps_native = [":mc_native_dep"],
        exports_ios_simulator_arm64 = [":mc_ios_simulator_export"],
        exports_jvm = [":mc_jvm_export"],
        exports_linux = [":mc_linux_export"],
        exports_macos = [":mc_macos_export"],
        plugins_apple = [":mc_apple_plugin"],
        plugins_jvm = [":mc_jvm_plugin"],
        plugins_linux_arm64 = [":mc_linux_plugin"],
        plugins_native = [":mc_native_plugin"],
        srcs_jvm = ["testdata/Platform.jvm.kt"],
        srcs_linux = ["testdata/Platform.linux.kt"],
        tags = ["manual"],
    )

    # A JVM library and a native library of the common sources alone: the fragment common, and empty
    # leaves. The target_compatible_with of native narrows the compatibility of the native library.
    kt_multiplatform_library(
        name = "mc_empty",
        platforms = [
            "jvm",
            "linux_arm64",
        ],
        srcs = ["testdata/Platform.kt"],
        native = dict(target_compatible_with = not_on_windows()),
        tags = ["manual"],
    )

    attrs_jvm_test(
        name = "multiplatform_common_attrs_jvm_test",
        target_under_test = ":mc_attrs_jvm",
        exports = [
            "mc_common_export_jvm",
            "mc_jvm_export",
        ],
        plugins = [
            "mc_common_plugin",
            "mc_jvm_plugin",
        ],
        deps = [
            "mc_common_dep_jvm",
            "mc_jvm_dep",
        ],
    )
    attrs_linux_arm64_test(
        name = "multiplatform_common_attrs_native_linux_test",
        target_under_test = ":mc_attrs_native",
        exports = [
            "mc_common_export_native_linux_arm64",
            "mc_linux_export",
        ],
        opts = [_OPT_IN],
        plugins = [
            "mc_common_plugin",
            "mc_native_plugin",
            "mc_linux_plugin",
        ],
        target_compatible_with = not_on_windows(),
        deps = [
            "mc_common_dep_native_linux_arm64",
            "mc_native_dep_linux_arm64",
            "mc_linux_dep",
        ],
    )
    attrs_macos_arm64_test(
        name = "multiplatform_common_attrs_native_mac_test",
        target_under_test = ":mc_attrs_native",
        exports = [
            "mc_common_export_native_macos_arm64",
            "mc_macos_export",
        ],
        opts = [_OPT_IN],
        plugins = [
            "mc_common_plugin",
            "mc_native_plugin",
            "mc_apple_plugin",
        ],
        target_compatible_with = not_on_windows(),
        deps = [
            "mc_common_dep_native_macos_arm64",
            "mc_native_dep_macos_arm64",
            "mc_apple_dep_macos_arm64",
        ],
    )
    attrs_ios_simulator_arm64_test(
        name = "multiplatform_common_attrs_native_ios_test",
        target_under_test = ":mc_attrs_native",
        exports = [
            "mc_common_export_native_ios_simulator_arm64",
            "mc_ios_simulator_export",
        ],
        opts = [_OPT_IN],
        plugins = [
            "mc_common_plugin",
            "mc_native_plugin",
            "mc_apple_plugin",
        ],
        target_compatible_with = not_on_windows(),
        deps = [
            "mc_common_dep_native_ios_simulator_arm64",
            "mc_native_dep_ios_simulator_arm64",
            "mc_apple_dep_ios_simulator_arm64",
            "mc_ios_dep",
        ],
    )

    jvm_test(
        name = "multiplatform_common_empty_jvm_test",
        target_under_test = ":mc_empty_jvm",
        fragments = [
            "common",
            "jvm",
        ],
        refines = ["jvm:common"],
        sources = ["common:Platform.kt"],
    )
    native_linux_arm64_test(
        name = "multiplatform_common_empty_native_test",
        target_under_test = ":mc_empty_native",
        fragments = [
            "common",
            "linux_arm64",
        ],
        refines = ["linux_arm64:common"],
        sources = ["common:Platform.kt"],
        srcs = ["Platform.kt"],
        target_compatible_with = not_on_windows(),
    )
    fragments_graph_unix_test(
        name = "multiplatform_common_empty_fragments_graph_test",
        target_under_test = ":mc_empty.fragments",
        graph = """\
fragment common
  platforms: jvm, linux_arm64
  srcs:
    testdata/Platform.kt
leaf jvm
  refines: common
leaf linux_arm64
  refines: common
""",
        header = "#!/usr/bin/env sh\n",
        launcher = "mc_empty.fragments.sh",
    )

    native.test_suite(
        name = name,
        tests = [
            ":multiplatform_common_attrs_jvm_test",
            ":multiplatform_common_attrs_native_ios_test",
            ":multiplatform_common_attrs_native_linux_test",
            ":multiplatform_common_attrs_native_mac_test",
            ":multiplatform_common_empty_fragments_graph_test",
            ":multiplatform_common_empty_jvm_test",
            ":multiplatform_common_empty_native_test",
        ],
    )
