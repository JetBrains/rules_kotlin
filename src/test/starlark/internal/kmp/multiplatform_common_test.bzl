"""Tests for the srcs, deps, exports and plugins of kt_multiplatform_library itself: the declarations it accepts, the errors of the others, and what the libraries of its platforms get.

The macro prepends each common list to the same attribute of every platform. It checks the
declaration as written, before merging, so the errors name the common list a platform repeats.
The fixtures with common sources derive the same fragments as their counterparts of
multiplatform_test.bzl, which list every source in every platform, and the tests reuse its rules.
The native tests use the fake toolchains of //src/test/starlark/internal/native (see common.bzl
there).
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("@rules_java//java:defs.bzl", "java_library")
load("//kotlin:core.bzl", "kt_compiler_plugin")
load("//kotlin:kmp.bzl", "kt_multiplatform_library")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:multiplatform.bzl", "multiplatform_declaration_error", "with_common_attrs")
load("//src/test/starlark/internal/native:common.bzl", "fake_klib", "for_target", "not_on_windows")
load(
    ":multiplatform_test.bzl",
    "files_test",
    "fragments_graph_unix_test",
    "jvm_test",
    "native_linux_arm64_test",
    "native_macos_arm64_test",
)

_PACKAGE = "src/test/starlark/internal/kmp"

# The sources of the mpp fixture of multiplatform_test.bzl that several platforms list: every
# platform the common ones, and the native platforms those of Gradle's nativeMain.
_COMMON = [
    "testdata/Platform.kt",
    "testdata/Greeting.kt",
]
_NON_JVM = ["testdata/Description.native.kt"]

# The fragments of the mpp fixture: of the common sources, of the non-JVM ones and of the Apple ones.
_ALL = "ios_simulator_arm64-jvm-linux_arm64-macos_arm64"
_NATIVE = "ios_simulator_arm64-linux_arm64-macos_arm64"
_APPLE = "ios_simulator_arm64-macos_arm64"

# The konan targets of the libraries of every platform.
_KONAN_TARGETS = ["linux_arm64", "macos_arm64"]

# The common lists of the unit tests, which the platforms of a valid declaration do not repeat.
_COMMON_LISTS = {
    "deps": [":common_lib"],
    "exports": [":common_export"],
    "plugins": [":common_plugin"],
    "srcs": ["common.kt"],
}

# Lists as a select(), whose branches are only known at analysis.
_SELECTED_DEPS = select({"//conditions:default": [":common_lib"]})
_SELECTED_PLUGINS = select({"//conditions:default": [":plugin"]})

def _relative(label):
    """Normalizes the labels of the package as package_relative_label does for the unit tests: `:a.kt` is `a.kt`."""
    return label[1:] if label.startswith(":") else label

def _valid_common_declarations_test(ctx):
    env = unittest.begin(ctx)

    # Each platform lists only what it adds to the common lists.
    asserts.equals(
        env,
        None,
        multiplatform_declaration_error(
            dict(srcs = ["jvm.kt"], deps = [":jvm_lib"], exports = [":jvm_export"], plugins = [":jvm_plugin"]),
            dict(srcs = ["android.kt"], deps = [":android_lib"], manifest = "AndroidManifest.xml"),
            {"linux": dict(srcs = ["linux.kt"], targets = ["linux_x64"], deps = [":klib"], opts = ["-opt"])},
            common = _COMMON_LISTS,
        ),
    )

    # A platform of the common entries only: an empty jvm, and a native group of its targets alone.
    asserts.equals(env, None, multiplatform_declaration_error({}, None, {}, common = _COMMON_LISTS))
    asserts.equals(
        env,
        None,
        multiplatform_declaration_error(None, None, {"linux": dict(targets = ["linux_x64"])}, common = _COMMON_LISTS),
    )

    # The macro cannot read the labels of a select() of a platform: it prepends the common deps to it.
    asserts.equals(env, None, multiplatform_declaration_error(dict(deps = _SELECTED_DEPS), None, {}, common = _COMMON_LISTS))

    # Empty common lists check nothing.
    asserts.equals(
        env,
        None,
        multiplatform_declaration_error(dict(srcs = ["a.kt"], deps = [":lib"]), None, {}, common = {"deps": [], "srcs": []}),
    )

    return unittest.end(env)

def _invalid_common_declarations_test(ctx):
    env = unittest.begin(ctx)

    # A platform repeats a label of the common list of the attribute: every attribute, every kind of platform.
    for attr, label in [("srcs", "a.kt"), ("deps", ":lib"), ("exports", ":export"), ("plugins", ":plugin")]:
        own = {attr: [":own", label]}
        for platform, jvm, android, native in [
            ("jvm", own, None, {}),
            ("android", None, own, {}),
            ("the native group 'linux'", None, None, {"linux": dict(own, targets = ["linux_x64"])}),
        ]:
            asserts.equals(
                env,
                "the %s of %s list %s, which the %s of the macro already list" % (attr, platform, label, attr),
                multiplatform_declaration_error(jvm, android, native, common = {attr: [label]}),
            )

    for message, jvm, common in [
        ("it declares no platform: give jvm, android or native", None, {"srcs": ["a.kt"]}),
        ("the deps of jvm list :lib, which the deps of the macro already list", dict(deps = [":jvm_lib", ":lib"]), {"deps": [":lib"]}),
        ("the srcs of the macro list a.kt twice", {}, {"srcs": ["a.kt", "b.kt", "a.kt"]}),
        (
            "the deps of the macro must be a list of labels, not a select: it prepends them to the deps of every " +
            "platform when it is called, before any select() is resolved",
            {},
            {"deps": _SELECTED_DEPS},
        ),
        (
            "the plugins of the macro must be a list of labels, not a select: it prepends them to the plugins of " +
            "every platform when it is called, before any select() is resolved",
            {},
            {"plugins": [":common_plugin"] + _SELECTED_PLUGINS},
        ),
        (
            "the srcs of the macro must be a list of labels, not a string: it prepends them to the srcs of every " +
            "platform when it is called, before any select() is resolved",
            {},
            {"srcs": "a.kt"},
        ),
    ]:
        asserts.equals(env, message, multiplatform_declaration_error(jvm, None, {}, common = common))

    # A label written in another form is the same label once normalized, as the macro normalizes it;
    # the error names it as written.
    asserts.equals(
        env,
        "the srcs of jvm list :a.kt, which the srcs of the macro already list",
        multiplatform_declaration_error(dict(srcs = [":a.kt"]), None, {}, normalize = _relative, common = {"srcs": ["a.kt"]}),
    )
    asserts.equals(
        env,
        "the deps of the macro list :lib twice",
        multiplatform_declaration_error({}, None, {}, normalize = _relative, common = {"deps": ["lib", ":lib"]}),
    )

    return unittest.end(env)

def _with_common_attrs_test(ctx):
    env = unittest.begin(ctx)

    common = {"deps": [":common_lib"], "exports": [], "srcs": ["a.kt", "b.kt"]}
    jvm = dict(srcs = ["jvm.kt"], deps = [":jvm_lib"], manifest = "AndroidManifest.xml")
    group = dict(targets = ["linux_x64"], opts = ["-opt"])

    # The common list first, then the platform's own; the other keys stay as they are.
    asserts.equals(
        env,
        dict(srcs = ["a.kt", "b.kt", "jvm.kt"], deps = [":common_lib", ":jvm_lib"], manifest = "AndroidManifest.xml"),
        with_common_attrs(jvm, common),
    )

    # A platform without the attribute gets the common list alone; an empty common list adds no key.
    merged = with_common_attrs(group, common)
    asserts.equals(env, dict(targets = ["linux_x64"], opts = ["-opt"], srcs = ["a.kt", "b.kt"], deps = [":common_lib"]), merged)
    asserts.equals(env, group, with_common_attrs(group, {}))

    # Neither argument changes, nor shares a list with the result.
    merged["srcs"].append("c.kt")
    asserts.equals(env, dict(srcs = ["jvm.kt"], deps = [":jvm_lib"], manifest = "AndroidManifest.xml"), jvm)
    asserts.equals(env, dict(targets = ["linux_x64"], opts = ["-opt"]), group)
    asserts.equals(env, {"deps": [":common_lib"], "exports": [], "srcs": ["a.kt", "b.kt"]}, common)

    # The common deps and a select() of the platform make a select().
    asserts.equals(env, "select", type(with_common_attrs(dict(deps = _SELECTED_DEPS), {"deps": [":lib"]})["deps"]))

    return unittest.end(env)

valid_common_declarations_test = unittest.make(_valid_common_declarations_test)
invalid_common_declarations_test = unittest.make(_invalid_common_declarations_test)
with_common_attrs_test = unittest.make(_with_common_attrs_test)

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

def _library_of_every_platform(name):
    """Declares `name`, an alias with the shape of those of kmp_maven.

    It selects, for the Kotlin/Native rules, a fake klib `<name>_<konan target>` of linux_arm64 or
    macos_arm64, and the java_library `<name>_jvm` otherwise.

    Args:
      name: the name of the alias, and the prefix of the names of the libraries.
    """
    for konan_target in _KONAN_TARGETS:
        fake_klib(
            name = "%s_%s" % (name, konan_target),
            konan_target = konan_target,
            tags = ["manual"],
        )
    java_library(
        name = name + "_jvm",
        srcs = ["testdata/PlatformTypeLib.java"],
        tags = ["manual"],
    )
    native.alias(
        name = name + "_native",
        actual = select({
            str(Label("//kotlin/native/platforms:native_" + konan_target)): ":%s_%s" % (name, konan_target)
            for konan_target in _KONAN_TARGETS
        }),
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
    """Declares multiplatform libraries with common lists and the tests of what kt_multiplatform_library declares for them.

    Args:
      name: the name of the generated test_suite target.
    """

    # mpp of multiplatform_test.bzl, with its common sources in the srcs of the macro: the same fragments.
    kt_multiplatform_library(
        name = "mc_mpp",
        srcs = _COMMON,
        jvm = dict(srcs = ["testdata/Platform.jvm.kt"]),
        native = {
            "apple": dict(
                srcs = _NON_JVM + ["testdata/Platform.apple.kt"],
                targets = [
                    "ios_simulator_arm64",
                    "macos_arm64",
                ],
            ),
            "linux": dict(
                srcs = _NON_JVM + ["testdata/Platform.linux.kt"],
                opts = ["-opt-in=kotlin.ExperimentalStdlibApi"],
                targets = ["linux_arm64"],
            ),
        },
        tags = ["manual"],
    )

    # The common deps, exports and plugins of every platform, and those of the JVM and Linux alone.
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
    fake_klib(
        name = "mc_linux_dep",
        konan_target = "linux_arm64",
        tags = ["manual"],
    )
    fake_klib(
        name = "mc_linux_export",
        konan_target = "linux_arm64",
        tags = ["manual"],
    )
    java_library(
        name = "mc_plugin_lib",
        srcs = ["testdata/PlatformTypeLib.java"],
        tags = ["manual"],
    )
    for plugin in ["common", "jvm", "linux"]:
        kt_compiler_plugin(
            name = "mc_%s_plugin" % plugin,
            id = "test.%s" % plugin,
            tags = ["manual"],
            deps = [":mc_plugin_lib"],
        )

    # The JVM deps are a select(), which the common deps come before all the same; the group mac
    # has nothing of its own, and the opts of linux stay its own.
    kt_multiplatform_library(
        name = "mc_attrs",
        srcs = ["testdata/Platform.kt"],
        deps = [":mc_common_dep"],
        exports = [":mc_common_export"],
        plugins = [":mc_common_plugin"],
        jvm = dict(
            srcs = ["testdata/Platform.jvm.kt"],
            deps = select({"//conditions:default": [":mc_jvm_dep"]}),
            exports = [":mc_jvm_export"],
            plugins = [":mc_jvm_plugin"],
        ),
        native = {
            "linux": dict(
                srcs = ["testdata/Platform.linux.kt"],
                deps = [":mc_linux_dep"],
                exports = [":mc_linux_export"],
                opts = ["-opt-in=kotlin.ExperimentalStdlibApi"],
                plugins = [":mc_linux_plugin"],
                targets = ["linux_arm64"],
            ),
            "mac": dict(targets = ["macos_arm64"]),
        },
        tags = ["manual"],
    )

    # A JVM library and a native group of the common sources alone: one fragment, and empty leaves.
    kt_multiplatform_library(
        name = "mc_empty",
        srcs = ["testdata/Platform.kt"],
        jvm = {},
        native = {"linux": dict(targets = ["linux_arm64"])},
        tags = ["manual"],
    )

    # A single platform shares nothing: its leaf is the common sources, then its own.
    kt_multiplatform_library(
        name = "mc_single",
        srcs = _COMMON,
        jvm = dict(srcs = ["testdata/Platform.jvm.kt"]),
        tags = ["manual"],
    )

    native_linux_arm64_test(
        name = "multiplatform_common_native_linux_test",
        target_under_test = ":mc_mpp_native",
        fragments = [
            _ALL,
            _NATIVE,
            "linux_arm64",
        ],
        opt_in = True,
        refines = [
            _NATIVE + ":" + _ALL,
            "linux_arm64:" + _NATIVE,
        ],
        sources = [
            _ALL + ":Platform.kt",
            _ALL + ":Greeting.kt",
            _NATIVE + ":Description.native.kt",
            "linux_arm64:Platform.linux.kt",
        ],
        srcs = [
            "Platform.kt",
            "Greeting.kt",
            "Description.native.kt",
            "Platform.linux.kt",
        ],
        target_compatible_with = not_on_windows(),
    )
    native_macos_arm64_test(
        name = "multiplatform_common_native_apple_test",
        target_under_test = ":mc_mpp_native",
        fragments = [
            _ALL,
            _NATIVE,
            _APPLE,
            "macos_arm64",
        ],
        opt_in = False,
        refines = [
            _NATIVE + ":" + _ALL,
            _APPLE + ":" + _NATIVE,
            "macos_arm64:" + _APPLE,
        ],
        sources = [
            _ALL + ":Platform.kt",
            _ALL + ":Greeting.kt",
            _NATIVE + ":Description.native.kt",
            _APPLE + ":Platform.apple.kt",
        ],
        srcs = [
            "Platform.kt",
            "Greeting.kt",
            "Description.native.kt",
            "Platform.apple.kt",
        ],
        target_compatible_with = not_on_windows(),
    )
    jvm_test(
        name = "multiplatform_common_jvm_test",
        target_under_test = ":mc_mpp_jvm",
        fragments = [
            _ALL,
            "jvm",
        ],
        refines = ["jvm:" + _ALL],
        sources = [
            _ALL + ":Platform.kt",
            _ALL + ":Greeting.kt",
            "jvm:Platform.jvm.kt",
        ],
    )
    files_test(
        name = "multiplatform_common_srcs_test",
        target_under_test = ":mc_mpp_srcs",
        files = [
            "Description.native.kt",
            "Greeting.kt",
            "Platform.apple.kt",
            "Platform.jvm.kt",
            "Platform.kt",
            "Platform.linux.kt",
        ],
    )
    fragments_graph_unix_test(
        name = "multiplatform_common_fragments_graph_test",
        target_under_test = ":mc_mpp.fragments",
        graph = """\
fragment ios_simulator_arm64-jvm-linux_arm64-macos_arm64
  srcs:
    testdata/Platform.kt
    testdata/Greeting.kt
fragment ios_simulator_arm64-linux_arm64-macos_arm64
  refines: ios_simulator_arm64-jvm-linux_arm64-macos_arm64
  srcs:
    testdata/Description.native.kt
fragment ios_simulator_arm64-macos_arm64
  refines: ios_simulator_arm64-linux_arm64-macos_arm64
  srcs:
    testdata/Platform.apple.kt
leaf ios_simulator_arm64
  refines: ios_simulator_arm64-macos_arm64
leaf jvm
  refines: ios_simulator_arm64-jvm-linux_arm64-macos_arm64
  srcs:
    testdata/Platform.jvm.kt
leaf linux_arm64
  refines: ios_simulator_arm64-linux_arm64-macos_arm64
  srcs:
    testdata/Platform.linux.kt
leaf macos_arm64
  refines: ios_simulator_arm64-macos_arm64
""",
        header = "#!/usr/bin/env sh\n",
        launcher = "mc_mpp.fragments.sh",
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
            "mc_common_export_linux_arm64",
            "mc_linux_export",
        ],
        opts = ["-opt-in=kotlin.ExperimentalStdlibApi"],
        plugins = [
            "mc_common_plugin",
            "mc_linux_plugin",
        ],
        target_compatible_with = not_on_windows(),
        deps = [
            "mc_common_dep_linux_arm64",
            "mc_linux_dep",
        ],
    )
    attrs_macos_arm64_test(
        name = "multiplatform_common_attrs_native_mac_test",
        target_under_test = ":mc_attrs_native",
        exports = ["mc_common_export_macos_arm64"],
        plugins = ["mc_common_plugin"],
        target_compatible_with = not_on_windows(),
        deps = ["mc_common_dep_macos_arm64"],
    )

    jvm_test(
        name = "multiplatform_common_empty_jvm_test",
        target_under_test = ":mc_empty_jvm",
        fragments = [
            "jvm-linux_arm64",
            "jvm",
        ],
        refines = ["jvm:jvm-linux_arm64"],
        sources = ["jvm-linux_arm64:Platform.kt"],
    )
    native_linux_arm64_test(
        name = "multiplatform_common_empty_native_test",
        target_under_test = ":mc_empty_native",
        fragments = [
            "jvm-linux_arm64",
            "linux_arm64",
        ],
        refines = ["linux_arm64:jvm-linux_arm64"],
        sources = ["jvm-linux_arm64:Platform.kt"],
        srcs = ["Platform.kt"],
        target_compatible_with = not_on_windows(),
    )
    fragments_graph_unix_test(
        name = "multiplatform_common_empty_fragments_graph_test",
        target_under_test = ":mc_empty.fragments",
        graph = """\
fragment jvm-linux_arm64
  srcs:
    testdata/Platform.kt
leaf jvm
  refines: jvm-linux_arm64
leaf linux_arm64
  refines: jvm-linux_arm64
""",
        header = "#!/usr/bin/env sh\n",
        launcher = "mc_empty.fragments.sh",
    )

    jvm_test(
        name = "multiplatform_common_single_platform_test",
        target_under_test = ":mc_single_jvm",
    )
    fragments_graph_unix_test(
        name = "multiplatform_common_single_fragments_graph_test",
        target_under_test = ":mc_single.fragments",
        graph = """\
leaf jvm
  srcs:
    testdata/Platform.kt
    testdata/Greeting.kt
    testdata/Platform.jvm.kt
""",
        header = "#!/usr/bin/env sh\n",
        launcher = "mc_single.fragments.sh",
    )

    unittest.suite(
        "multiplatform_common_declarations",
        valid_common_declarations_test,
        invalid_common_declarations_test,
        with_common_attrs_test,
    )

    native.test_suite(
        name = name,
        tests = [
            ":multiplatform_common_attrs_jvm_test",
            ":multiplatform_common_attrs_native_linux_test",
            ":multiplatform_common_attrs_native_mac_test",
            ":multiplatform_common_declarations",
            ":multiplatform_common_empty_fragments_graph_test",
            ":multiplatform_common_empty_jvm_test",
            ":multiplatform_common_empty_native_test",
            ":multiplatform_common_fragments_graph_test",
            ":multiplatform_common_jvm_test",
            ":multiplatform_common_native_apple_test",
            ":multiplatform_common_native_linux_test",
            ":multiplatform_common_single_fragments_graph_test",
            ":multiplatform_common_single_platform_test",
            ":multiplatform_common_srcs_test",
        ],
    )
