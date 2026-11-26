"""Analysis tests for kt_native_xctest_library: its generated sources, the klib compile, the static link and the CcInfo.

See common.bzl for the fake toolchains. The tests of the actions add the fake C++ toolchain, so they
need no Apple toolchain on the host; the tests of the failures do not, as the rule fails before it
reads one.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//kotlin:native.bzl", "kt_native_library", "kt_native_xctest_library")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:fragment.bzl", "kt_kmp_fragment")
load(
    ":common.bzl",
    "FAKE_COVERAGE_FLAGS",
    "FAKE_OBJC_COMPILER",
    "HEADER_KLIBS_ATTRS",
    "NO_LIGHT_DEBUG",
    "PACKAGE",
    "argument_after",
    "compile_klib_of",
    "for_target",
    "launcher_values",
    "libraries",
    "not_on_windows",
    "prefixed",
    "single_action",
    "tool_arguments",
    "with_fake_cc_toolchain",
    "with_header_klibs",
)

# The sources of the rules a library gets with its own names: the launcher gives the generated test
# runner a C name and compiles with the srcs, the test case calls it.
_LAUNCHER = "XCTestLauncher.kt"
_TEST_CASE = "XCTestShim.m"

def _basenames(paths):
    return sorted([path.rpartition("/")[2] for path in paths])

def _expansion(env, template):
    """The action of the target under test that expands a source of the rules."""
    path = "kotlin/internal/native/" + template
    actions = [
        action
        for action in analysistest.target_actions(env)
        if action.mnemonic == "TemplateExpand" and path in [f.path for f in action.inputs.to_list()]
    ]
    asserts.equals(env, 1, len(actions), "actions expanding %s" % path)
    return actions[0]

def _expanded(env, template):
    """The File a source of the rules expands to, checked to be `_kt_native/<name>_<template>` of the target under test."""
    source = _expansion(env, template).outputs.to_list()[0]
    name = analysistest.target_under_test(env).label.name
    asserts.equals(env, "%s/_kt_native/%s_%s" % (PACKAGE, name, template), source.short_path)
    return source

def _xctest_names_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The class and the function are named after the package and the name of the target, so that the
    # libraries of one test bundle differ in them; the test case calls the launcher of its library.
    names = {
        "KotlinNativeTests": "KotlinNativeTests_" + ctx.attr.suffix,
        "rules_kotlin_xctest_run": "rules_kotlin_xctest_run_" + ctx.attr.suffix,
    }
    for template in [_LAUNCHER, _TEST_CASE]:
        asserts.equals(env, names, _expansion(env, template).substitutions, template)
        _expanded(env, template)

    # So is the static library: konanc names the symbols it exports after its output. It is in the
    # directory of the name of the target, which the identifier does not tell apart from others.
    name = analysistest.target_under_test(env).label.name
    stem = "%s/_kt_native/%s/lib%s" % (PACKAGE, name, ctx.attr.suffix)
    outputs = [output.short_path for output in single_action(env, "KotlinNativeLink").outputs.to_list()]
    asserts.equals(env, [stem + ".a", stem + "_api.h"], outputs)

    return analysistest.end(env)

def _xctest_link_test_impl(ctx):
    env = analysistest.begin(ctx)

    header_klibs = ctx.attr.header_klibs
    compile = single_action(env, "KotlinNativeKlibCompile")
    compile_tool = tool_arguments(compile.argv)
    link = single_action(env, "KotlinNativeLink")
    link_tool = tool_arguments(link.argv)

    # The launcher compiles with the srcs, after them, into the private klib.
    launcher = _expanded(env, _LAUNCHER).path
    asserts.equals(env, [PACKAGE + "/testdata/greeter.kt", launcher], launcher_values(compile.argv, "--source"))
    main_klib = compile.outputs.to_list()[0]
    asserts.equals(env, PACKAGE + "/_kt_native/xctest_app_tests.klib", main_klib.short_path)

    # The associate and its deps are deps of both actions, and the srcs see the internals of the
    # associate, as for kt_native_test.
    closure = ["xctest_app_ios_simulator_arm64.klib", "xctest_greeter_ios_simulator_arm64.klib"]
    asserts.equals(env, [compile_klib_of(name, header_klibs) for name in closure], _basenames(libraries(compile_tool)))
    asserts.equals(env, closure, _basenames(libraries(link_tool)))
    associate_klib = compile_klib_of("xctest_app_ios_simulator_arm64.klib", header_klibs)
    associate = [path for path in libraries(compile_tool) if path.endswith("/" + associate_klib)]
    asserts.equals(env, associate, [argument_after(compile_tool, "-friend-modules")])

    # The link is a static library with the generated test runner, named as konanc names it, with
    # the package and the name of the target, and konanc writes the C header of the library next to
    # it.
    library, header = link.outputs.to_list()
    stem = PACKAGE + "/_kt_native/xctest_app_tests/libsrc_test_starlark_internal_native_xctest_app_tests"
    asserts.equals(env, stem + ".a", library.short_path)
    asserts.equals(env, stem + "_api.h", header.short_path)
    asserts.equals(env, "static", argument_after(link_tool, "-produce"))
    asserts.equals(env, "ios_simulator_arm64", argument_after(link_tool, "-target"))
    for flag in [NO_LIGHT_DEBUG, "-generate-test-runner", "-Xinclude=__EXECROOT__/" + main_klib.path]:
        asserts.true(env, flag in link_tool, "%s should be in %s" % (flag, link_tool))
    asserts.false(env, "-generate-test-runner" in compile_tool, str(compile_tool))
    asserts.equals(env, ["-o", library.path], link_tool[-2:])
    asserts.equals(env, "iPhoneSimulator", link.env.get("APPLE_SDK_PLATFORM"), str(link.env))
    asserts.equals(env, [library], analysistest.target_under_test(env)[DefaultInfo].files.to_list())

    # Without kmp_fragments, the library compiles no fragments.
    asserts.false(env, "-Xmulti-platform" in compile_tool, str(compile_tool))

    return analysistest.end(env)

def _test_case_compile(env):
    """The one action of the C++ toolchain that compiles the XCTest case, checked to be of the fake toolchain."""
    test_case = _expanded(env, _TEST_CASE)
    compiles = [
        action
        for action in analysistest.target_actions(env)
        if test_case in action.inputs.to_list() and [f for f in action.outputs.to_list() if f.extension == "o"]
    ]
    asserts.equals(env, 1, len(compiles), "actions compiling %s" % test_case.short_path)
    asserts.true(env, compiles[0].argv[0].endswith("/" + FAKE_OBJC_COMPILER), "the fake toolchain should compile it, not %s" % compiles[0].argv[0])
    return compiles[0]

def _xctest_cc_info_test_impl(ctx):
    env = analysistest.begin(ctx)

    library = single_action(env, "KotlinNativeLink").outputs.to_list()[0]
    _test_case_compile(env)

    # The CcInfo links the test case whole, as nothing refers to it, and the Kotlin tests as a
    # static library: its object files of the libraries that klibs embed do not link whole.
    linker_inputs = analysistest.target_under_test(env)[CcInfo].linking_context.linker_inputs.to_list()
    linked = [lib for linker_input in linker_inputs for lib in linker_input.libraries]
    asserts.equals(env, 2, len(linked), str(linked))
    alwayslink = {(lib.static_library or lib.pic_static_library): lib.alwayslink for lib in linked}
    asserts.equals(env, False, alwayslink.get(library), "alwayslink of %s in %s" % (library, alwayslink))
    asserts.equals(env, [True], [whole for static, whole in alwayslink.items() if static != library], str(alwayslink))

    # The flags konanc links an iOS binary with travel with the library.
    flags = [flag for linker_input in linker_inputs for flag in linker_input.user_link_flags]
    asserts.equals(env, ["-lc++", "-lobjc", "-Wl,-framework,Foundation", "-Wl,-framework,UIKit"], flags)

    return analysistest.end(env)

def _xctest_coverage_test_impl(ctx):
    env = analysistest.begin(ctx)

    # A coverage build instruments the XCTest case in the LLVM format only, whose profile runtime
    # the test bundle of rules_apple links: it does not link the one of the gcov format, the
    # default, which an object file instrumented in that format needs.
    argv = _test_case_compile(env).argv
    flags = [flag for flag in FAKE_COVERAGE_FLAGS.values() if flag in argv]
    asserts.equals(env, [FAKE_COVERAGE_FLAGS[feature] for feature in ctx.attr.instrumented_with], flags, str(argv))

    return analysistest.end(env)

def _xctest_fragments_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The launcher is a source of the leaf fragment, after the srcs: every Kotlin source of a
    # multiplatform compilation belongs to a fragment.
    compile = single_action(env, "KotlinNativeKlibCompile")
    compile_tool = tool_arguments(compile.argv)
    common = PACKAGE + "/testdata/common.kt"
    actual = PACKAGE + "/testdata/actual.kt"
    launcher = _expanded(env, _LAUNCHER).path
    asserts.equals(env, [common, actual, launcher], launcher_values(compile.argv, "--source"))
    asserts.true(env, "-Xmulti-platform" in compile_tool, str(compile_tool))
    asserts.equals(env, ["common,ios_simulator_arm64"], prefixed(compile_tool, "-Xfragments="))
    asserts.equals(
        env,
        ["common:" + common, "ios_simulator_arm64:" + actual, "ios_simulator_arm64:" + launcher],
        prefixed(compile_tool, "-Xfragment-sources="),
    )
    asserts.equals(env, ["ios_simulator_arm64:common"], prefixed(compile_tool, "-Xfragment-refines="))

    # The link includes the private klib, and gets no fragment flag.
    main_klib = compile.outputs.to_list()[0]
    link_tool = tool_arguments(single_action(env, "KotlinNativeLink").argv)
    asserts.equals(env, ["__EXECROOT__/" + main_klib.path], prefixed(link_tool, "-Xinclude="))
    asserts.equals(env, [], prefixed(link_tool, "-Xfragment"))

    return analysistest.end(env)

def _xctest_non_apple_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(env, "kt_native_xctest_library builds for the test bundles of Apple platforms, but this target is linux_arm64")
    asserts.expect_failure(env, "set target_compatible_with to skip it")

    return analysistest.end(env)

def _xctest_same_identifier_test_impl(ctx):
    env = analysistest.begin(ctx)

    # Both libraries analyse in this one build: two files of one path would be a conflict. Their
    # identifiers are equal, so the directories of their names keep their files apart.
    files = [file.short_path for file in analysistest.target_under_test(env)[DefaultInfo].files.to_list()]
    asserts.equals(env, 2, len(files), str(files))
    asserts.equals(env, 2, len(depset(files).to_list()), str(files))
    for name in ["xctest_app_tests_2", "xctest-app.tests+2"]:
        asserts.true(
            env,
            "%s/_kt_native/%s/libsrc_test_starlark_internal_native_xctest_app_tests_2.a" % (PACKAGE, name) in files,
            "%s should have its library in %s" % (name, files),
        )

    return analysistest.end(env)

def _xctest_without_srcs_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(env, "kt_native_xctest_library has no sources, in its srcs or its kmp_fragments; the test bundle only runs the tests of its own sources")

    return analysistest.end(env)

_ACTIONS_CONFIG = with_fake_cc_toolchain(for_target("ios_simulator_arm64"))

xctest_link_test = analysistest.make(
    _xctest_link_test_impl,
    attrs = HEADER_KLIBS_ATTRS,
    config_settings = _ACTIONS_CONFIG,
)
xctest_link_header_klibs_test = analysistest.make(
    _xctest_link_test_impl,
    attrs = HEADER_KLIBS_ATTRS,
    config_settings = with_header_klibs(_ACTIONS_CONFIG),
)
xctest_names_test = analysistest.make(
    _xctest_names_test_impl,
    attrs = {"suffix": attr.string()},
    config_settings = _ACTIONS_CONFIG,
)
xctest_same_identifier_test = analysistest.make(_xctest_same_identifier_test_impl, config_settings = _ACTIONS_CONFIG)
xctest_cc_info_test = analysistest.make(_xctest_cc_info_test_impl, config_settings = _ACTIONS_CONFIG)
xctest_fragments_test = analysistest.make(_xctest_fragments_test_impl, config_settings = _ACTIONS_CONFIG)

def _coverage_config(llvm_format):
    """`_ACTIONS_CONFIG` of a coverage build that instruments the package of the tests, in the gcov or the LLVM format."""
    return dict(_ACTIONS_CONFIG, **{
        "//command_line_option:collect_code_coverage": True,
        "//command_line_option:experimental_use_llvm_covmap": llvm_format,
        "//command_line_option:instrumentation_filter": "^//" + PACKAGE + "[/:]",
    })

_COVERAGE_ATTRS = {
    "instrumented_with": attr.string_list(doc = "the coverage features of the fake C++ toolchain whose flags the compilation of the XCTest case has"),
}

xctest_coverage_test = analysistest.make(
    _xctest_coverage_test_impl,
    attrs = _COVERAGE_ATTRS,
    config_settings = _coverage_config(False),
)
xctest_llvm_coverage_test = analysistest.make(
    _xctest_coverage_test_impl,
    attrs = _COVERAGE_ATTRS,
    config_settings = _coverage_config(True),
)
xctest_non_apple_test = analysistest.make(
    _xctest_non_apple_test_impl,
    config_settings = for_target("linux_arm64"),
    expect_failure = True,
)
xctest_without_srcs_test = analysistest.make(
    _xctest_without_srcs_test_impl,
    config_settings = for_target("ios_simulator_arm64"),
    expect_failure = True,
)

def native_xctest_test_suite(name):
    """Declares the targets under test and the analysis tests of kt_native_xctest_library.

    The fake toolchains (common.bzl: define_fake_toolchains) must be declared in the package.

    Args:
      name: the name of the generated test_suite target.
    """

    # Tests of app, which depends on greeter.
    kt_native_library(
        name = "xctest_greeter_ios_simulator_arm64",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
    )
    kt_native_library(
        name = "xctest_app_ios_simulator_arm64",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
        deps = [":xctest_greeter_ios_simulator_arm64"],
    )
    kt_native_xctest_library(
        name = "xctest_app_tests",
        srcs = ["testdata/greeter.kt"],
        associates = [":xctest_app_ios_simulator_arm64"],
        tags = ["manual"],
    )
    kt_native_xctest_library(
        name = "xctest-app.tests+2",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
    )
    kt_native_xctest_library(
        name = "xctest_app_tests_2",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
    )
    native.filegroup(
        name = "xctest_same_identifier_tests",
        srcs = [
            ":xctest-app.tests+2",
            ":xctest_app_tests_2",
        ],
        tags = ["manual"],
        testonly = True,
    )
    kt_native_xctest_library(
        name = "xctest_linux_tests",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
    )
    kt_native_xctest_library(
        name = "xctest_no_srcs_tests",
        associates = [":xctest_app_ios_simulator_arm64"],
        tags = ["manual"],
    )

    # Tests whose sources are fragments: one with srcs of its own, and one whose fragments have no
    # source either.
    kt_kmp_fragment(
        name = "xctest_common_fragment",
        testonly = True,
        srcs = ["testdata/common.kt"],
        fragment_name = "common",
        platforms = [
            "jvm",
            "ios_simulator_arm64",
        ],
        tags = ["manual"],
    )
    kt_kmp_fragment(
        name = "xctest_empty_fragment",
        testonly = True,
        fragment_name = "common",
        platforms = ["ios_simulator_arm64"],
        tags = ["manual"],
    )
    kt_native_xctest_library(
        name = "xctest_fragments_tests",
        testonly = True,
        srcs = ["testdata/actual.kt"],
        associates = [":xctest_app_ios_simulator_arm64"],
        kmp_fragments = [":xctest_common_fragment"],
        tags = ["manual"],
    )
    kt_native_xctest_library(
        name = "xctest_empty_fragments_tests",
        testonly = True,
        associates = [":xctest_app_ios_simulator_arm64"],
        kmp_fragments = [":xctest_empty_fragment"],
        tags = ["manual"],
    )

    xctest_link_test(
        name = "xctest_link_test",
        target_under_test = ":xctest_app_tests",
        target_compatible_with = not_on_windows(),
    )
    xctest_link_header_klibs_test(
        name = "xctest_link_header_klibs_test",
        target_under_test = ":xctest_app_tests",
        header_klibs = True,
        target_compatible_with = not_on_windows(),
    )
    xctest_names_test(
        name = "xctest_names_test",
        suffix = "src_test_starlark_internal_native_xctest_app_tests",
        target_under_test = ":xctest_app_tests",
        target_compatible_with = not_on_windows(),
    )
    xctest_names_test(
        name = "xctest_names_of_other_characters_test",
        suffix = "src_test_starlark_internal_native_xctest_app_tests_2",
        target_under_test = ":xctest-app.tests+2",
        target_compatible_with = not_on_windows(),
    )
    xctest_same_identifier_test(
        name = "xctest_same_identifier_test",
        target_under_test = ":xctest_same_identifier_tests",
        target_compatible_with = not_on_windows(),
    )
    xctest_cc_info_test(
        name = "xctest_cc_info_test",
        target_under_test = ":xctest_app_tests",
        target_compatible_with = not_on_windows(),
    )
    xctest_coverage_test(
        name = "xctest_coverage_test",
        target_under_test = ":xctest_app_tests",
        target_compatible_with = not_on_windows(),
    )
    xctest_llvm_coverage_test(
        name = "xctest_llvm_coverage_test",
        instrumented_with = ["llvm_coverage_map_format"],
        target_under_test = ":xctest_app_tests",
        target_compatible_with = not_on_windows(),
    )
    xctest_fragments_test(
        name = "xctest_fragments_test",
        target_under_test = ":xctest_fragments_tests",
        target_compatible_with = not_on_windows(),
    )
    xctest_non_apple_test(
        name = "xctest_non_apple_fails_test",
        target_under_test = ":xctest_linux_tests",
        target_compatible_with = not_on_windows(),
    )
    xctest_without_srcs_test(
        name = "xctest_without_srcs_fails_test",
        target_under_test = ":xctest_no_srcs_tests",
        target_compatible_with = not_on_windows(),
    )
    xctest_without_srcs_test(
        name = "xctest_without_fragment_sources_fails_test",
        target_under_test = ":xctest_empty_fragments_tests",
        target_compatible_with = not_on_windows(),
    )

    native.test_suite(
        name = name,
        tests = [
            ":xctest_cc_info_test",
            ":xctest_coverage_test",
            ":xctest_fragments_test",
            ":xctest_link_header_klibs_test",
            ":xctest_link_test",
            ":xctest_llvm_coverage_test",
            ":xctest_names_of_other_characters_test",
            ":xctest_names_test",
            ":xctest_same_identifier_test",
            ":xctest_non_apple_fails_test",
            ":xctest_without_fragment_sources_fails_test",
            ":xctest_without_srcs_fails_test",
        ],
    )
