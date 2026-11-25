"""Analysis tests for kt_native_binary and kt_native_test: the klib compile and link actions.

See common.bzl for the fake toolchains.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_java//java:defs.bzl", "java_library")
load("//kotlin:core.bzl", "kt_compiler_plugin")
load("//kotlin:native.bzl", "kt_native_binary", "kt_native_library", "kt_native_test")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:fragment.bzl", "kt_kmp_fragment")
load(
    ":common.bzl",
    "AIRPLANE_MODE",
    "BTAPI_RUNTIME",
    "DEPS",
    "DEP_NAMES",
    "HEADER_KLIBS_ATTRS",
    "HOME",
    "NO_LIGHT_DEBUG",
    "PACKAGE",
    "argument_after",
    "compile_klib_of",
    "for_target",
    "launcher_arguments",
    "launcher_values",
    "libraries",
    "not_on_windows",
    "prefixed",
    "single_action",
    "tool_arguments",
    "with_header_klibs",
)

def _basenames(paths):
    return sorted([path.rpartition("/")[2] for path in paths])

def _compile_actions(env):
    return [action for action in analysistest.target_actions(env) if action.mnemonic == "KotlinNativeKlibCompile"]

def _link_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The srcs compile into the private klib, against the compile klibs of the deps, without the
    # link dependencies. Nothing compiles against the private klib, so it has no header klib.
    header_klibs = ctx.attr.header_klibs
    compile = single_action(env, "KotlinNativeKlibCompile")
    main_klib = compile.outputs.to_list()[0]
    asserts.equals(env, [main_klib], compile.outputs.to_list())
    asserts.equals(env, PACKAGE + "/_kt_native/hello_linux_arm64.klib", main_klib.short_path)
    asserts.false(env, "--staged-deps" in launcher_arguments(compile.argv), str(compile.argv))

    # It is a klib compilation as any other: the launcher gets its output and sources, and compiles
    # it with the Build Tools API implementation of the toolchain.
    asserts.equals(env, [main_klib.path], launcher_values(compile.argv, "--klib-output"))
    asserts.equals(env, [PACKAGE + "/testdata/main.kt"], launcher_values(compile.argv, "--source"))
    asserts.equals(env, BTAPI_RUNTIME, launcher_values(compile.argv, "--btapi-classpath"))
    compile_tool = tool_arguments(compile.argv)
    asserts.false(env, "-produce" in compile_tool, str(compile_tool))
    asserts.false(env, "-o" in compile_tool, str(compile_tool))
    asserts.equals(env, "src_test_starlark_internal_native-hello_linux_arm64", argument_after(compile_tool, "-module-name"))
    asserts.equals(env, [compile_klib_of("link_greeter_linux_arm64.klib", header_klibs)], _basenames(libraries(compile_tool)))
    asserts.equals(env, [], prefixed(compile_tool, "-Xheader-klib-path="))

    link = single_action(env, "KotlinNativeLink")
    binary = link.outputs.to_list()[0]
    asserts.equals(env, "hello_linux_arm64.kexe", binary.basename)

    # The binary is the executable of the rule, and its only output.
    info = analysistest.target_under_test(env)[DefaultInfo]
    asserts.equals(env, binary, info.files_to_run.executable)
    asserts.equals(env, [binary], info.files.to_list())

    inputs = [f.path for f in link.inputs.to_list()]
    asserts.true(env, main_klib.path in inputs, "the private klib should be an input")
    asserts.equals(env, [], [path for path in inputs if path.endswith(".header.klib")])
    for name in DEP_NAMES:
        asserts.true(
            env,
            len([path for path in inputs if path.startswith(DEPS + "/dependencies/" + name + "/")]) == 1,
            "the files of %s should be inputs" % name,
        )
    asserts.true(env, HOME + "/klib/platform/linux_arm64/posix/default/manifest" in inputs)
    asserts.false(env, HOME + "/klib/platform/macos_arm64/posix/default/manifest" in inputs)

    # The launcher stages the dependency directories of the target into the konan data dir. A link
    # runs konanc, whatever the Build Tools API setting: the API has no link operation.
    argv = link.argv
    asserts.equals(env, "konan_launcher", argv[0].rpartition("/")[2])
    staged = []
    for name in DEP_NAMES:
        staged.extend(["--staged-deps", DEPS + "/dependencies/" + name])
    asserts.equals(
        env,
        [
            "--tool",
            "konanc",
            "--konan-home",
            HOME,
            "--data-dir",
            binary.path + ".konan_data",
            "--auto-cache-dir",
            binary.path + ".konan_cache",
        ] + staged,
        launcher_arguments(argv),
    )

    for jar in BTAPI_RUNTIME:
        asserts.false(env, jar in inputs, "%s should not be an input of the link" % jar)

    tool = tool_arguments(argv)
    asserts.equals(env, "program", argument_after(tool, "-produce"))
    asserts.equals(env, "linux_arm64", argument_after(tool, "-target"))
    for flag in [
        AIRPLANE_MODE,
        NO_LIGHT_DEBUG,
        "-Xkonan-data-dir=%s.konan_data" % binary.path,
        "-Xinclude=__EXECROOT__/" + main_klib.path,
    ]:
        asserts.true(env, flag in tool, "%s should be in %s" % (flag, tool))
    asserts.equals(env, ["-o", binary.path], tool[-2:])

    # The private klib is only included (konanc would see it twice with -l), and the link compiles
    # no source and names no module. It links the klibs of the deps, whatever the srcs compiled against.
    asserts.equals(env, ["link_greeter_linux_arm64.klib"], _basenames(libraries(tool)))
    for library in libraries(tool):
        asserts.true(env, library in inputs, "%s should be an input" % library)
    asserts.false(env, "-module-name" in tool, str(tool))
    asserts.equals(env, [], [arg for arg in tool if arg.endswith(".kt")])

    return analysistest.end(env)

def _unstaged_link_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(env, "the Kotlin/Native link dependencies of macos_arm64 are not staged")
    asserts.expect_failure(env, "add 'macos_arm64' to kotlin_native.targets(...)")

    return analysistest.end(env)

def _binary_options_test_impl(ctx):
    env = analysistest.begin(ctx)

    compile_tool = tool_arguments(single_action(env, "KotlinNativeKlibCompile").argv)
    link_tool = tool_arguments(single_action(env, "KotlinNativeLink").argv)

    # The plugins and opts apply to the compilation of the srcs: the link only reads the klib back.
    asserts.equals(env, ["liblink_plugin_lib.jar"], _basenames(prefixed(compile_tool, "-Xplugin=")))
    asserts.equals(env, "plugin:test.link:enabled=true", argument_after(compile_tool, "-P"))
    asserts.true(env, "-opt-in=kotlin.ExperimentalStdlibApi" in compile_tool, str(compile_tool))
    asserts.equals(env, [], prefixed(link_tool, "-Xplugin="))
    asserts.false(env, "-P" in link_tool, str(link_tool))
    asserts.false(env, "-opt-in=kotlin.ExperimentalStdlibApi" in link_tool, str(link_tool))

    # The link_opts apply to the link, after the options of the rule and before the output.
    asserts.false(env, "-opt" in compile_tool, str(compile_tool))
    asserts.equals(env, "-opt", link_tool[-3])
    asserts.true(env, link_tool.index("-opt") > link_tool.index(NO_LIGHT_DEBUG))

    return analysistest.end(env)

def _binary_without_srcs_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The entry point comes from a dep: there is nothing to compile, and nothing to include.
    asserts.equals(env, [], _compile_actions(env))
    tool = tool_arguments(single_action(env, "KotlinNativeLink").argv)
    asserts.equals(env, [], prefixed(tool, "-Xinclude="))
    asserts.equals(env, ["link_greeter_linux_arm64.klib", "link_main_linux_arm64.klib"], _basenames(libraries(tool)))

    return analysistest.end(env)

def _test_link_test_impl(ctx):
    env = analysistest.begin(ctx)

    header_klibs = ctx.attr.header_klibs
    compile_tool = tool_arguments(single_action(env, "KotlinNativeKlibCompile").argv)
    link = single_action(env, "KotlinNativeLink")
    link_tool = tool_arguments(link.argv)

    # The associate and its deps are deps of both actions: the compilation reads their compile klibs,
    # in the order of the klibs the link reads.
    closure = ["link_app_linux_arm64.klib", "link_greeter_linux_arm64.klib"]
    asserts.equals(env, [compile_klib_of(name, header_klibs) for name in closure], _basenames(libraries(compile_tool)))
    asserts.equals(env, closure, _basenames(libraries(link_tool)))
    asserts.equals(env, [compile_klib_of(path, header_klibs) for path in libraries(link_tool)], libraries(compile_tool))
    asserts.equals(env, [], [f.path for f in link.inputs.to_list() if f.path.endswith(".header.klib")])

    # The srcs see the internals of the associate, which konanc matches by the path of its -l
    # argument, but not those of its deps.
    associate_klib = compile_klib_of("link_app_linux_arm64.klib", header_klibs)
    associate = [path for path in libraries(compile_tool) if path.endswith("/" + associate_klib)]
    asserts.equals(env, associate, [argument_after(compile_tool, "-friend-modules")])
    asserts.false(env, "-friend-modules" in link_tool, str(link_tool))

    # The link generates the test runner, which is the executable of the rule.
    asserts.true(env, "-generate-test-runner" in link_tool, str(link_tool))
    asserts.false(env, "-generate-test-runner" in compile_tool, str(compile_tool))
    binary = link.outputs.to_list()[0]
    asserts.equals(env, "app_test_linux_arm64.kexe", binary.basename)
    asserts.equals(env, binary, analysistest.target_under_test(env)[DefaultInfo].files_to_run.executable)

    # A test without kmp_fragments compiles no fragments.
    asserts.false(env, "-Xmulti-platform" in compile_tool, str(compile_tool))
    asserts.equals(env, [], prefixed(compile_tool, "-Xfragment"))

    return analysistest.end(env)

def _test_fragments_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The sources of the fragments compile into the private klib with the srcs, the leaf, named
    # after the konan target, which may be empty: the fragments, each after those it refines, the
    # leaf last.
    compile = single_action(env, "KotlinNativeKlibCompile")
    compile_tool = tool_arguments(compile.argv)
    fragment_sources = [
        (fragment, PACKAGE + "/testdata/" + source)
        for fragment in ctx.attr.fragments
        for source in ctx.attr.fragment_sources.get(fragment, [])
    ]
    asserts.equals(env, [source for _, source in fragment_sources], launcher_values(compile.argv, "--source"))
    asserts.true(env, "-Xmulti-platform" in compile_tool, str(compile_tool))
    asserts.equals(env, [",".join(ctx.attr.fragments)], prefixed(compile_tool, "-Xfragments="))
    asserts.equals(
        env,
        ["%s:%s" % (fragment, source) for fragment, source in fragment_sources],
        prefixed(compile_tool, "-Xfragment-sources="),
    )
    asserts.equals(env, ctx.attr.refines, prefixed(compile_tool, "-Xfragment-refines="))
    inputs = [f.path for f in compile.inputs.to_list()]
    for _, source in fragment_sources:
        asserts.true(env, source in inputs, "%s should be an input" % source)

    # The fragments see the internals of the associate, as the srcs do.
    associate = [path for path in libraries(compile_tool) if path.endswith("/link_app_linux_arm64.klib")]
    asserts.equals(env, associate, [argument_after(compile_tool, "-friend-modules")])

    # The link includes the private klib, whose tests the generated runner runs, and gets no
    # fragment flag.
    main_klib = compile.outputs.to_list()[0]
    link_tool = tool_arguments(single_action(env, "KotlinNativeLink").argv)
    asserts.equals(env, ["__EXECROOT__/" + main_klib.path], prefixed(link_tool, "-Xinclude="))
    asserts.true(env, "-generate-test-runner" in link_tool, str(link_tool))
    asserts.false(env, "-Xmulti-platform" in link_tool, str(link_tool))
    asserts.equals(env, [], prefixed(link_tool, "-Xfragment"))

    return analysistest.end(env)

def _test_for_another_target_test_impl(ctx):
    env = analysistest.begin(ctx)

    # Bazel convention, as for cc_test: a test for a platform the exec host does not run still builds,
    # so `bazel build //...` for that platform does. The fake toolchains run on a linux_arm64 host.
    link = single_action(env, "KotlinNativeLink")
    tool = tool_arguments(link.argv)
    asserts.equals(env, "ios_simulator_arm64", argument_after(tool, "-target"))
    asserts.true(env, "-generate-test-runner" in tool, str(tool))
    binary = link.outputs.to_list()[0]
    asserts.equals(env, binary, analysistest.target_under_test(env)[DefaultInfo].files_to_run.executable)

    return analysistest.end(env)

def _data_test_impl(ctx):
    env = analysistest.begin(ctx)

    # Bazel convention for executables: the data, and the runfiles of the data, are runfiles of the
    # executable. They are no input of its compilation or of its link.
    info = analysistest.target_under_test(env)[DefaultInfo]
    runfiles = [f.short_path for f in info.default_runfiles.files.to_list()]
    for path in [PACKAGE + "/testdata/greeter.kt", PACKAGE + "/testdata/FakePlugin.java"]:
        asserts.true(env, path in runfiles, "%s should be in the runfiles %s" % (path, runfiles))
    asserts.true(env, info.files_to_run.executable.short_path in runfiles, str(runfiles))
    asserts.equals(env, [info.files_to_run.executable], info.files.to_list())
    for mnemonic in ["KotlinNativeKlibCompile", "KotlinNativeLink"]:
        inputs = [f.short_path for f in single_action(env, mnemonic).inputs.to_list()]
        asserts.false(env, PACKAGE + "/testdata/FakePlugin.java" in inputs, "the data should not be an input of " + mnemonic)

    return analysistest.end(env)

def _test_without_srcs_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(env, "kt_native_test has no sources, in its srcs or its kmp_fragments; its test runner only runs the tests of its own sources")

    return analysistest.end(env)

link_test = analysistest.make(_link_test_impl, attrs = HEADER_KLIBS_ATTRS, config_settings = for_target("linux_arm64"))
link_header_klibs_test = analysistest.make(
    _link_test_impl,
    attrs = HEADER_KLIBS_ATTRS,
    config_settings = with_header_klibs(for_target("linux_arm64")),
)
unstaged_link_test = analysistest.make(
    _unstaged_link_test_impl,
    config_settings = for_target("macos_arm64"),
    expect_failure = True,
)
binary_options_test = analysistest.make(_binary_options_test_impl, config_settings = for_target("linux_arm64"))
binary_without_srcs_test = analysistest.make(_binary_without_srcs_test_impl, config_settings = for_target("linux_arm64"))
test_link_test = analysistest.make(_test_link_test_impl, attrs = HEADER_KLIBS_ATTRS, config_settings = for_target("linux_arm64"))
test_link_header_klibs_test = analysistest.make(
    _test_link_test_impl,
    attrs = HEADER_KLIBS_ATTRS,
    config_settings = with_header_klibs(for_target("linux_arm64")),
)
test_fragments_test = analysistest.make(
    _test_fragments_test_impl,
    attrs = {
        # The basenames of the sources of each fragment, in testdata.
        "fragment_sources": attr.string_list_dict(),
        # The fragment names, each after those it refines, the leaf last.
        "fragments": attr.string_list(),
        # The refinements, <fragment>:<refined fragment>, in the order of the flags.
        "refines": attr.string_list(),
    },
    config_settings = for_target("linux_arm64"),
)
test_for_another_target_test = analysistest.make(
    _test_for_another_target_test_impl,
    config_settings = for_target("ios_simulator_arm64"),
)
data_test = analysistest.make(_data_test_impl, config_settings = for_target("linux_arm64"))
test_without_srcs_test = analysistest.make(
    _test_without_srcs_test_impl,
    config_settings = for_target("linux_arm64"),
    expect_failure = True,
)

def native_binary_test_suite(name):
    """Declares the targets under test and the analysis tests of kt_native_binary and kt_native_test.

    The fake toolchains (common.bzl: define_fake_toolchains) must be declared in the package.

    Args:
      name: the name of the generated test_suite target.
    """
    for target in ["linux_arm64", "macos_arm64"]:
        kt_native_library(
            name = "link_greeter_" + target,
            srcs = ["testdata/greeter.kt"],
            tags = ["manual"],
        )
        kt_native_binary(
            name = "hello_" + target,
            srcs = ["testdata/main.kt"],
            tags = ["manual"],
            deps = [":link_greeter_" + target],
        )

    java_library(
        name = "link_plugin_lib",
        srcs = ["testdata/FakePlugin.java"],
        tags = ["manual"],
    )
    kt_compiler_plugin(
        name = "link_plugin",
        id = "test.link",
        options = {"enabled": ["true"]},
        tags = ["manual"],
        target_embedded_compiler = True,
        deps = [":link_plugin_lib"],
    )
    kt_native_binary(
        name = "options_linux_arm64",
        srcs = ["testdata/main.kt"],
        link_opts = ["-opt"],
        opts = ["-opt-in=kotlin.ExperimentalStdlibApi"],
        plugins = [":link_plugin"],
        tags = ["manual"],
        deps = [":link_greeter_linux_arm64"],
    )

    # A binary whose entry point is in a dep.
    kt_native_library(
        name = "link_main_linux_arm64",
        srcs = ["testdata/main.kt"],
        tags = ["manual"],
        deps = [":link_greeter_linux_arm64"],
    )
    kt_native_binary(
        name = "hello_from_dep_linux_arm64",
        tags = ["manual"],
        deps = [":link_main_linux_arm64"],
    )

    # A test of app, which depends on greeter.
    kt_native_library(
        name = "link_app_linux_arm64",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
        deps = [":link_greeter_linux_arm64"],
    )
    kt_native_test(
        name = "app_test_linux_arm64",
        srcs = ["testdata/greeter.kt"],
        associates = [":link_app_linux_arm64"],
        tags = ["manual"],
    )
    kt_native_test(
        name = "test_ios_simulator_arm64",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
    )

    # A binary and a test with data: a file, and a target with runfiles of its own.
    native.filegroup(
        name = "data_with_runfiles",
        srcs = ["testdata/FakePlugin.java"],
        data = ["testdata/greeter.kt"],
        tags = ["manual"],
    )
    kt_native_binary(
        name = "data_binary_linux_arm64",
        srcs = ["testdata/main.kt"],
        data = [":data_with_runfiles"],
        tags = ["manual"],
    )
    kt_native_test(
        name = "data_test_linux_arm64",
        srcs = ["testdata/greeter.kt"],
        data = [":data_with_runfiles"],
        tags = ["manual"],
    )
    kt_native_test(
        name = "no_srcs_test_linux_arm64",
        associates = [":link_app_linux_arm64"],
        tags = ["manual"],
    )

    # Tests of app whose test sources are fragments: one with srcs of its own, one whose leaf is
    # empty, and one whose fragments have no source either.
    kt_kmp_fragment(
        name = "test_common_fragment",
        testonly = True,
        srcs = ["testdata/common.kt"],
        fragment_name = "common",
        platforms = [
            "jvm",
            "linux_arm64",
        ],
        tags = ["manual"],
    )
    kt_kmp_fragment(
        name = "test_native_fragment",
        testonly = True,
        srcs = ["testdata/actual.kt"],
        fragment_name = "native",
        platforms = ["linux_arm64"],
        refines = [":test_common_fragment"],
        tags = ["manual"],
    )
    kt_kmp_fragment(
        name = "test_empty_fragment",
        testonly = True,
        fragment_name = "common",
        platforms = ["linux_arm64"],
        tags = ["manual"],
    )
    kt_native_test(
        name = "fragments_test_linux_arm64",
        srcs = ["testdata/actual.kt"],
        associates = [":link_app_linux_arm64"],
        kmp_fragments = [":test_common_fragment"],
        tags = ["manual"],
    )
    kt_native_test(
        name = "fragments_only_test_linux_arm64",
        associates = [":link_app_linux_arm64"],
        kmp_fragments = [":test_native_fragment"],
        tags = ["manual"],
    )
    kt_native_test(
        name = "empty_fragments_test_linux_arm64",
        associates = [":link_app_linux_arm64"],
        kmp_fragments = [":test_empty_fragment"],
        tags = ["manual"],
    )

    link_test(
        name = "link_inputs_test",
        target_under_test = ":hello_linux_arm64",
        target_compatible_with = not_on_windows(),
    )
    unstaged_link_test(
        name = "unstaged_link_fails_test",
        target_under_test = ":hello_macos_arm64",
        target_compatible_with = not_on_windows(),
    )
    binary_options_test(
        name = "binary_options_test",
        target_under_test = ":options_linux_arm64",
        target_compatible_with = not_on_windows(),
    )
    binary_without_srcs_test(
        name = "binary_without_srcs_test",
        target_under_test = ":hello_from_dep_linux_arm64",
        target_compatible_with = not_on_windows(),
    )
    test_link_test(
        name = "test_link_test",
        target_under_test = ":app_test_linux_arm64",
        target_compatible_with = not_on_windows(),
    )

    # With header klibs, the srcs compile against the header klibs of the deps, the friend among them,
    # and the link reads their klibs.
    link_header_klibs_test(
        name = "link_header_klibs_test",
        target_under_test = ":hello_linux_arm64",
        header_klibs = True,
        target_compatible_with = not_on_windows(),
    )
    test_link_header_klibs_test(
        name = "test_link_header_klibs_test",
        target_under_test = ":app_test_linux_arm64",
        header_klibs = True,
        target_compatible_with = not_on_windows(),
    )

    test_for_another_target_test(
        name = "test_for_another_target_links_test",
        target_under_test = ":test_ios_simulator_arm64",
        target_compatible_with = not_on_windows(),
    )
    data_test(
        name = "binary_data_test",
        target_under_test = ":data_binary_linux_arm64",
        target_compatible_with = not_on_windows(),
    )
    data_test(
        name = "test_data_test",
        target_under_test = ":data_test_linux_arm64",
        target_compatible_with = not_on_windows(),
    )
    test_without_srcs_test(
        name = "test_without_srcs_fails_test",
        target_under_test = ":no_srcs_test_linux_arm64",
        target_compatible_with = not_on_windows(),
    )
    test_without_srcs_test(
        name = "test_without_fragment_sources_fails_test",
        target_under_test = ":empty_fragments_test_linux_arm64",
        target_compatible_with = not_on_windows(),
    )
    test_fragments_test(
        name = "test_fragments_test",
        target_under_test = ":fragments_test_linux_arm64",
        fragment_sources = {
            "common": ["common.kt"],
            "linux_arm64": ["actual.kt"],
        },
        fragments = [
            "common",
            "linux_arm64",
        ],
        refines = ["linux_arm64:common"],
        target_compatible_with = not_on_windows(),
    )
    test_fragments_test(
        name = "test_fragments_only_test",
        target_under_test = ":fragments_only_test_linux_arm64",
        fragment_sources = {
            "common": ["common.kt"],
            "native": ["actual.kt"],
        },
        fragments = [
            "common",
            "native",
            "linux_arm64",
        ],
        refines = [
            "native:common",
            "linux_arm64:native",
        ],
        target_compatible_with = not_on_windows(),
    )

    native.test_suite(
        name = name,
        tests = [
            ":binary_data_test",
            ":binary_options_test",
            ":binary_without_srcs_test",
            ":link_header_klibs_test",
            ":link_inputs_test",
            ":test_link_header_klibs_test",
            ":test_data_test",
            ":test_for_another_target_links_test",
            ":test_fragments_only_test",
            ":test_fragments_test",
            ":test_link_test",
            ":test_without_fragment_sources_fails_test",
            ":test_without_srcs_fails_test",
            ":unstaged_link_fails_test",
        ],
    )
