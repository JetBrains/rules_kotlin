"""Tests for kt_multiplatform_library: the targets it declares, and the library its alias selects per consumer.

The native tests use the fake toolchains of //src/test/starlark/internal/native (see common.bzl there).
The alias is the native library below the Kotlin/Native rules, which set the Kotlin platform type
to native: the tests of the alias alone set it as such a consumer does.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("@rules_java//java:defs.bzl", "JavaInfo")
load("//kotlin:kmp.bzl", "KtSourceSetInfo", "kt_multiplatform_library", "kt_source_set")
load("//kotlin:native.bzl", "KtKlibInfo")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:multiplatform.bzl", "konan_targets_compatibility", "multiplatform_declaration_error")
load(
    "//src/test/starlark/internal/native:common.bzl",
    "for_target",
    "not_on_windows",
    "single_action",
    "tool_arguments",
)

_PACKAGE = "src/test/starlark/internal/kmp"
_NAMES = "src_test_starlark_internal_kmp-"
_KOTLIN_PLATFORM_TYPE = str(Label("//kotlin/settings:kotlin_platform_type"))

def _basenames(paths):
    return [path.rpartition("/")[2] for path in paths]

def _native_consumer_of(konan_target):
    """The config_settings of a Kotlin/Native consumer building for a konan target: the platform and the platform type the Kotlin/Native rules set."""
    return dict(for_target(konan_target), **{_KOTLIN_PLATFORM_TYPE: "native"})

def _native_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The native library compiles the source set of the group of the konan target, which refines
    # the common one and the source sets of its depends_on, and takes the other attributes of the
    # group.
    tool = tool_arguments(single_action(env, "KotlinNativeKlibCompile").argv)
    asserts.equals(
        env,
        ["-Xfragments=" + ",".join([_NAMES + "mpp_" + fragment for fragment in ctx.attr.fragments])],
        [arg for arg in tool if arg.startswith("-Xfragments=")],
    )
    refines = [refinement.split(":") for refinement in ctx.attr.refines]
    asserts.equals(
        env,
        ["%smpp_%s:%smpp_%s" % (_NAMES, refining, _NAMES, refined) for refining, refined in refines],
        [arg[len("-Xfragment-refines="):] for arg in tool if arg.startswith("-Xfragment-refines=")],
    )
    asserts.equals(
        env,
        ctx.attr.srcs,
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

def _intermediate_source_sets_test_impl(ctx):
    env = analysistest.begin(ctx)

    # A group with depends_on refines the common source set and the listed ones, Gradle's
    # appleMain.dependsOn(nativeMain), which refines the common one too.
    info = analysistest.target_under_test(env)[KtSourceSetInfo]
    asserts.equals(env, _NAMES + "mpp_apple", info.name)
    asserts.equals(env, ["Platform.apple.kt"], [src.basename for src in info.srcs])
    asserts.equals(
        env,
        [_NAMES + "mpp_common", _NAMES + "mpp_non_jvm"],
        [source_set.name for source_set in info.depends_on],
    )
    asserts.equals(
        env,
        [_NAMES + "mpp_common", _NAMES + "mpp_non_jvm", _NAMES + "mpp_apple"],
        [source_set.name for source_set in info.transitive_source_sets.to_list()],
    )
    asserts.equals(env, ["Description.native.kt"], [src.basename for src in info.depends_on[1].srcs])

    return analysistest.end(env)

def _srcs_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.equals(
        env,
        ["Greeting.kt", "Platform.apple.kt", "Platform.jvm.kt", "Platform.kt", "Platform.linux.kt"],
        sorted([f.basename for f in analysistest.target_under_test(env)[DefaultInfo].files.to_list()]),
    )

    return analysistest.end(env)

def _shared_srcs_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.equals(
        env,
        ["Platform.kt", "Platform.linux.kt"],
        [f.basename for f in analysistest.target_under_test(env)[DefaultInfo].files.to_list()],
    )

    return analysistest.end(env)

_NATIVE_ATTRS = {
    "fragments": attr.string_list(doc = "the expected fragments, without the prefix of the library"),
    "opt_in": attr.bool(),
    "refines": attr.string_list(doc = "the expected refinements, `<fragment>:<refined>`, without the prefix"),
    "srcs": attr.string_list(doc = "the basenames of the expected sources, in order"),
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
alias_native_test = analysistest.make(
    _alias_native_test_impl,
    config_settings = _native_consumer_of("linux_arm64"),
)

# A JVM consumer on a host of a konan target of the groups: the platform alone selects no native library.
alias_jvm_on_native_host_test = analysistest.make(_alias_jvm_test_impl, config_settings = for_target("linux_arm64"))
alias_jvm_test = analysistest.make(
    _alias_jvm_test_impl,
    config_settings = {
        "//command_line_option:platforms": [str(Label("//%s:jvm_platform" % _PACKAGE))],
    },
)

# The source set of a group is only compatible below a Kotlin/Native consumer building for one of its
# targets: the tests are such a consumer, as the native library is (the platform alone would skip the
# tests as incompatible).
source_sets_test = analysistest.make(_source_sets_test_impl, config_settings = _native_consumer_of("linux_arm64"))
intermediate_source_sets_test = analysistest.make(
    _intermediate_source_sets_test_impl,
    config_settings = _native_consumer_of("macos_arm64"),
)
srcs_test = analysistest.make(_srcs_test_impl)
shared_srcs_test = analysistest.make(_shared_srcs_test_impl)

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
                "apple": dict(targets = ["ios_arm64", "macos_arm64"], depends_on = [":non_jvm"]),
                "linux_64": dict(srcs = [], targets = ["linux_x64"], opts = ["-opt"], depends_on = []),
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
        (
            "the native group 'apple' must list the source sets it refines in depends_on, not give a string",
            None,
            None,
            {"apple": dict(targets = ["ios_arm64"], depends_on = ":non_jvm")},
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

def _konan_targets_compatibility_test(ctx):
    env = unittest.begin(ctx)

    # The native library is compatible with the platforms of its konan targets alone, whatever the
    # Kotlin platform type (is_<target>): it transitions itself to native. The labels are resolved as
    # the macro resolves them, in the repository of the rules.
    incompatible = [str(Label("@platforms//:incompatible"))]
    asserts.equals(
        env,
        {
            str(Label("//kotlin/native/platforms:is_ios_arm64")): [],
            str(Label("//kotlin/native/platforms:is_macos_arm64")): [],
            "//conditions:default": incompatible,
        },
        konan_targets_compatibility(["ios_arm64", "macos_arm64"]),
    )
    asserts.equals(
        env,
        {"//conditions:default": incompatible},
        konan_targets_compatibility([]),
    )

    # The source set of a group is only compatible below a Kotlin/Native consumer building for one of
    # its targets (native_<target>): a build of the package on a macOS host, a JVM consumer, skips
    # the source set of the apple group rather than resolving its deps for the JVM.
    asserts.equals(
        env,
        {
            str(Label("//kotlin/native/platforms:native_ios_arm64")): [],
            str(Label("//kotlin/native/platforms:native_macos_arm64")): [],
            "//conditions:default": incompatible,
        },
        konan_targets_compatibility(["ios_arm64", "macos_arm64"], native_consumer = True),
    )

    return unittest.end(env)

valid_declaration_test = unittest.make(_valid_declaration_test)
invalid_declarations_test = unittest.make(_invalid_declarations_test)
konan_targets_compatibility_test = unittest.make(_konan_targets_compatibility_test)

def multiplatform_test_suite(name):
    """Declares a multiplatform library and the tests of what kt_multiplatform_library declares.

    Args:
      name: the name of the generated test_suite target.
    """

    # An intermediate source set of the module, Gradle's nativeMain, which the apple group refines.
    kt_source_set(
        name = "mpp_non_jvm",
        srcs = ["testdata/Description.native.kt"],
        depends_on = [":mpp_common"],
        tags = ["manual"],
    )

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
                depends_on = [
                    ":mpp_common",
                    ":mpp_non_jvm",
                ],
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

    # A source several platforms compile, e.g. generated actuals shared by the JVM and native
    # platforms: the filegroup of the sources lists it once (a filegroup rejects duplicated labels).
    kt_multiplatform_library(
        name = "mpp_shared_src",
        common_srcs = ["testdata/Platform.kt"],
        jvm = dict(srcs = ["testdata/Platform.linux.kt"]),
        native = {
            "linux": dict(
                srcs = ["testdata/Platform.linux.kt"],
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
        fragments = [
            "common",
            "linux",
            "native",
        ],
        opt_in = True,
        refines = [
            "linux:common",
            "native:linux",
        ],
        srcs = [
            "Platform.kt",
            "Greeting.kt",
            "Platform.linux.kt",
        ],
        target_compatible_with = not_on_windows(),
    )

    # The common source set is listed once, although the group and its depends_on both name it.
    native_macos_arm64_test(
        name = "multiplatform_native_apple_test",
        target_under_test = ":mpp_native",
        fragments = [
            "common",
            "non_jvm",
            "apple",
            "native",
        ],
        opt_in = False,
        refines = [
            "non_jvm:common",
            "apple:common",
            "apple:non_jvm",
            "native:apple",
        ],
        srcs = [
            "Platform.kt",
            "Greeting.kt",
            "Description.native.kt",
            "Platform.apple.kt",
        ],
        target_compatible_with = not_on_windows(),
    )
    alias_native_test(
        name = "multiplatform_alias_native_test",
        target_under_test = ":mpp",
        target_compatible_with = not_on_windows(),
    )
    alias_jvm_on_native_host_test(
        name = "multiplatform_alias_jvm_on_native_host_test",
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
    intermediate_source_sets_test(
        name = "multiplatform_intermediate_source_sets_test",
        target_under_test = ":mpp_apple",
    )
    srcs_test(
        name = "multiplatform_srcs_test",
        target_under_test = ":mpp_srcs",
    )
    shared_srcs_test(
        name = "multiplatform_shared_srcs_test",
        target_under_test = ":mpp_shared_src_srcs",
    )
    unittest.suite(
        "multiplatform_declarations",
        valid_declaration_test,
        invalid_declarations_test,
        konan_targets_compatibility_test,
    )

    native.test_suite(
        name = name,
        tests = [
            ":multiplatform_alias_jvm_on_native_host_test",
            ":multiplatform_alias_jvm_test",
            ":multiplatform_alias_native_test",
            ":multiplatform_declarations",
            ":multiplatform_intermediate_source_sets_test",
            ":multiplatform_native_apple_test",
            ":multiplatform_native_linux_test",
            ":multiplatform_shared_srcs_test",
            ":multiplatform_source_sets_test",
            ":multiplatform_srcs_test",
        ],
    )
