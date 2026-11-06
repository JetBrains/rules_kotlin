"""Tests for kt_multiplatform_library: the targets it declares, and the library its alias selects per platform.

The native tests use the fake toolchains of //src/test/starlark/internal/native (see common.bzl there).
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("@rules_java//java:defs.bzl", "JavaInfo")
load("//kotlin:kmp.bzl", "KtSourceSetInfo", "kt_multiplatform_library")
load("//kotlin:native.bzl", "KtKlibInfo")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:multiplatform.bzl", "multiplatform_declaration_error")
load(
    "//src/test/starlark/internal/native:common.bzl",
    "for_target",
    "not_on_windows",
    "single_action",
    "tool_arguments",
)

_PACKAGE = "src/test/starlark/internal/kmp"
_NAMES = "src_test_starlark_internal_kmp-"

def _basenames(paths):
    return [path.rpartition("/")[2] for path in paths]

def _native_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The native library compiles the source set of the group of the konan target, which refines
    # the common one, and takes the other attributes of the group.
    tool = tool_arguments(single_action(env, "KotlinNativeKlibCompile").argv)
    group = _NAMES + "mpp_" + ctx.attr.group
    asserts.equals(
        env,
        ["-Xfragments=%smpp_common,%s,%smpp_native" % (_NAMES, group, _NAMES)],
        [arg for arg in tool if arg.startswith("-Xfragments=")],
    )
    asserts.equals(
        env,
        ["%s:%smpp_common" % (group, _NAMES), "%smpp_native:%s" % (_NAMES, group)],
        [arg[len("-Xfragment-refines="):] for arg in tool if arg.startswith("-Xfragment-refines=")],
    )
    asserts.equals(
        env,
        ["Platform.kt", "Greeting.kt", ctx.attr.actual],
        _basenames(tool[tool.index("-o") + 2:]),
    )
    asserts.equals(env, ctx.attr.opt_in, "-opt-in=kotlin.ExperimentalStdlibApi" in tool, str(tool))

    return analysistest.end(env)

def _alias_native_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    asserts.true(env, KtKlibInfo in target, "the alias should be the native library")
    asserts.false(env, JavaInfo in target, "the alias should not be the JVM library")
    asserts.equals(env, _NAMES + "mpp_native", target[KtKlibInfo].module_name)

    return analysistest.end(env)

def _alias_jvm_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    asserts.false(env, KtKlibInfo in target, "the alias should not be the native library")
    asserts.equals(env, ["mpp_jvm.jar"], [jar.basename for jar in target[JavaInfo].runtime_output_jars])

    return analysistest.end(env)

def _source_sets_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The group refines the common source set.
    info = analysistest.target_under_test(env)[KtSourceSetInfo]
    asserts.equals(env, _NAMES + "mpp_linux", info.name)
    asserts.equals(env, ["Platform.linux.kt"], [src.basename for src in info.srcs])
    asserts.equals(
        env,
        [_NAMES + "mpp_common", _NAMES + "mpp_linux"],
        [source_set.name for source_set in info.transitive_source_sets.to_list()],
    )
    asserts.equals(env, ["Platform.kt", "Greeting.kt"], [src.basename for src in info.depends_on[0].srcs])

    return analysistest.end(env)

def _srcs_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.equals(
        env,
        ["Greeting.kt", "Platform.apple.kt", "Platform.jvm.kt", "Platform.kt", "Platform.linux.kt"],
        sorted([f.basename for f in analysistest.target_under_test(env)[DefaultInfo].files.to_list()]),
    )

    return analysistest.end(env)

_NATIVE_ATTRS = {
    "actual": attr.string(),
    "group": attr.string(),
    "opt_in": attr.bool(),
}

native_linux_arm64_test = analysistest.make(
    _native_test_impl,
    attrs = _NATIVE_ATTRS,
    config_settings = for_target("linux_arm64"),
)
native_macos_arm64_test = analysistest.make(
    _native_test_impl,
    attrs = _NATIVE_ATTRS,
    config_settings = for_target("macos_arm64"),
)
alias_native_test = analysistest.make(_alias_native_test_impl, config_settings = for_target("linux_arm64"))
alias_jvm_test = analysistest.make(
    _alias_jvm_test_impl,
    config_settings = {
        "//command_line_option:platforms": [str(Label("//%s:jvm_platform" % _PACKAGE))],
    },
)
source_sets_test = analysistest.make(_source_sets_test_impl)
srcs_test = analysistest.make(_srcs_test_impl)

def _valid_declaration_test(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, None, multiplatform_declaration_error(dict(srcs = []), None, {}))
    asserts.equals(env, None, multiplatform_declaration_error(None, dict(srcs = []), {}))
    asserts.equals(
        env,
        None,
        multiplatform_declaration_error(
            None,
            None,
            {
                "apple": dict(targets = ["ios_arm64", "macos_arm64"]),
                "linux_64": dict(srcs = [], targets = ["linux_x64"], opts = ["-opt"]),
            },
        ),
    )

    return unittest.end(env)

def _invalid_declarations_test(ctx):
    env = unittest.begin(ctx)

    for message, jvm, android, native in [
        ("it declares no platform: give jvm, android or native", None, None, {}),
        ("jvm must be a dict of attributes of its library, not a list", [], None, {}),
        ("native must be a dict of groups of konan targets, not a list", None, None, ["apple"]),
        (
            "the native group 'a-b' must be a name of letters, digits and '_'",
            None,
            None,
            {"a-b": dict(targets = ["linux_x64"])},
        ),
        (
            "the native group 'jvm' would name a target the macro declares; rename it",
            None,
            None,
            {"jvm": dict(targets = ["linux_x64"])},
        ),
        ("the native group 'linux' lists no konan targets", None, None, {"linux": dict(srcs = [])}),
        (
            "the native group 'linux' lists the unknown konan target 'linux_riscv64'; the known ones are " +
            "ios_arm64, ios_simulator_arm64, linux_arm64, linux_x64, macos_arm64",
            None,
            None,
            {"linux": dict(targets = ["linux_riscv64"])},
        ),
        (
            "the konan target 'ios_arm64' is in both native groups 'apple' and 'ios'",
            None,
            None,
            {"apple": dict(targets = ["ios_arm64", "macos_arm64"]), "ios": dict(targets = ["ios_arm64"])},
        ),
    ]:
        asserts.equals(env, message, multiplatform_declaration_error(jvm, android, native))

    return unittest.end(env)

valid_declaration_test = unittest.make(_valid_declaration_test)
invalid_declarations_test = unittest.make(_invalid_declarations_test)

def multiplatform_test_suite(name):
    """Declares a multiplatform library and the tests of what kt_multiplatform_library declares.

    Args:
      name: the name of the generated test_suite target.
    """
    kt_multiplatform_library(
        name = "mpp",
        common_srcs = [
            "testdata/Platform.kt",
            "testdata/Greeting.kt",
        ],
        jvm = dict(srcs = ["testdata/Platform.jvm.kt"]),
        native = {
            "apple": dict(
                srcs = ["testdata/Platform.apple.kt"],
                targets = [
                    "ios_simulator_arm64",
                    "macos_arm64",
                ],
            ),
            "linux": dict(
                srcs = ["testdata/Platform.linux.kt"],
                opts = ["-opt-in=kotlin.ExperimentalStdlibApi"],
                targets = ["linux_arm64"],
            ),
        },
        tags = ["manual"],
    )

    # A platform of no konan target: the alias is the JVM library.
    native.platform(
        name = "jvm_platform",
        constraint_values = [
            "@platforms//cpu:riscv64",
            "@platforms//os:linux",
        ],
    )

    native_linux_arm64_test(
        name = "multiplatform_native_linux_test",
        target_under_test = ":mpp_native",
        actual = "Platform.linux.kt",
        group = "linux",
        opt_in = True,
        target_compatible_with = not_on_windows(),
    )
    native_macos_arm64_test(
        name = "multiplatform_native_apple_test",
        target_under_test = ":mpp_native",
        actual = "Platform.apple.kt",
        group = "apple",
        opt_in = False,
        target_compatible_with = not_on_windows(),
    )
    alias_native_test(
        name = "multiplatform_alias_native_test",
        target_under_test = ":mpp",
        target_compatible_with = not_on_windows(),
    )
    alias_jvm_test(
        name = "multiplatform_alias_jvm_test",
        target_under_test = ":mpp",
    )
    source_sets_test(
        name = "multiplatform_source_sets_test",
        target_under_test = ":mpp_linux",
    )
    srcs_test(
        name = "multiplatform_srcs_test",
        target_under_test = ":mpp_srcs",
    )
    unittest.suite(
        "multiplatform_declarations",
        valid_declaration_test,
        invalid_declarations_test,
    )

    native.test_suite(
        name = name,
        tests = [
            ":multiplatform_alias_jvm_test",
            ":multiplatform_alias_native_test",
            ":multiplatform_declarations",
            ":multiplatform_native_apple_test",
            ":multiplatform_native_linux_test",
            ":multiplatform_source_sets_test",
            ":multiplatform_srcs_test",
        ],
    )
