"""Analysis tests for kt_native_binary and kt_native_test: the klib compile and link actions.

See common.bzl for the fake toolchains.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_java//java:defs.bzl", "java_library")
load("//kotlin:core.bzl", "kt_compiler_plugin")
load("//kotlin:kmp.bzl", "kt_source_set")
load("//kotlin:native.bzl", "kt_native_binary", "kt_native_library", "kt_native_test")
load(
    ":common.bzl",
    "AIRPLANE_MODE",
    "DEPS",
    "DEP_NAMES",
    "HOME",
    "NO_LIGHT_DEBUG",
    "PACKAGE",
    "argument_after",
    "for_target",
    "launcher_arguments",
    "libraries",
    "not_on_windows",
    "prefixed",
    "single_action",
    "tool_arguments",
)

# The prefix of the module and fragment names derived from the labels of the package.
_NAMES = "src_test_starlark_internal_native-"

def _basenames(paths):
    return sorted([path.rpartition("/")[2] for path in paths])

def _compile_actions(env):
    return [action for action in analysistest.target_actions(env) if action.mnemonic == "KotlinNativeKlibCompile"]

def _link_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The srcs compile into the private klib, against the deps, without the link dependencies.
    compile = single_action(env, "KotlinNativeKlibCompile")
    main_klib = compile.outputs.to_list()[0]
    asserts.equals(env, PACKAGE + "/_kt_native/hello_linux_arm64.klib", main_klib.short_path)
    asserts.false(env, "--staged-deps" in launcher_arguments(compile.argv), str(compile.argv))
    compile_tool = tool_arguments(compile.argv)
    asserts.equals(env, "library", argument_after(compile_tool, "-produce"))
    asserts.equals(env, "src_test_starlark_internal_native-hello_linux_arm64", argument_after(compile_tool, "-module-name"))
    asserts.equals(env, ["link_greeter_linux_arm64.klib"], _basenames(libraries(compile_tool)))
    asserts.equals(env, main_klib.path, argument_after(compile_tool, "-o"))
    asserts.equals(env, PACKAGE + "/testdata/main.kt", compile_tool[-1])

    link = single_action(env, "KotlinNativeLink")
    binary = link.outputs.to_list()[0]
    asserts.equals(env, "hello_linux_arm64.kexe", binary.basename)

    # The binary is the executable of the rule, and its only output.
    info = analysistest.target_under_test(env)[DefaultInfo]
    asserts.equals(env, binary, info.files_to_run.executable)
    asserts.equals(env, [binary], info.files.to_list())

    inputs = [f.path for f in link.inputs.to_list()]
    asserts.true(env, main_klib.path in inputs, "the private klib should be an input")
    for name in DEP_NAMES:
        asserts.true(
            env,
            len([path for path in inputs if path.startswith(DEPS + "/dependencies/" + name + "/")]) == 1,
            "the files of %s should be inputs" % name,
        )
    asserts.true(env, HOME + "/klib/platform/linux_arm64/posix/default/manifest" in inputs)
    asserts.false(env, HOME + "/klib/platform/macos_arm64/posix/default/manifest" in inputs)

    # The launcher stages the dependency directories of the target into the konan data dir.
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
    # no source and names no module.
    asserts.equals(env, ["link_greeter_linux_arm64.klib"], _basenames(libraries(tool)))
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

def _binary_fragments_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The srcs compile with the source set, as fragments, against the deps of the source set.
    compile = single_action(env, "KotlinNativeKlibCompile")
    main_klib = compile.outputs.to_list()[0]
    compile_tool = tool_arguments(compile.argv)
    common = PACKAGE + "/testdata/common.kt"
    main = PACKAGE + "/testdata/main.kt"
    fragments = [_NAMES + "link_ss_common", _NAMES + "source_sets_binary_linux_arm64"]
    asserts.equals(env, [",".join(fragments)], prefixed(compile_tool, "-Xfragments="))
    asserts.equals(
        env,
        ["%s:%s" % (fragments[0], common), "%s:%s" % (fragments[1], main)],
        prefixed(compile_tool, "-Xfragment-sources="),
    )
    asserts.equals(env, ["%s:%s" % (fragments[1], fragments[0])], prefixed(compile_tool, "-Xfragment-refines="))
    asserts.equals(env, [main_klib.path, common, main], compile_tool[compile_tool.index("-o") + 1:])
    asserts.equals(env, ["link_greeter_linux_arm64.klib"], _basenames(libraries(compile_tool)))

    # The link includes the private klib and links the deps of the source set; it compiles nothing.
    link_tool = tool_arguments(single_action(env, "KotlinNativeLink").argv)
    asserts.true(env, "-Xinclude=__EXECROOT__/" + main_klib.path in link_tool, str(link_tool))
    asserts.equals(env, ["link_greeter_linux_arm64.klib"], _basenames(libraries(link_tool)))
    asserts.equals(
        env,
        [],
        [arg for arg in link_tool if arg.startswith("-Xfragment") or arg in ["-Xmulti-platform", "-Xexpect-actual-classes"]],
    )

    return analysistest.end(env)

def _test_link_test_impl(ctx):
    env = analysistest.begin(ctx)

    compile_tool = tool_arguments(single_action(env, "KotlinNativeKlibCompile").argv)
    link = single_action(env, "KotlinNativeLink")
    link_tool = tool_arguments(link.argv)

    # The associate and its deps are deps of both actions.
    closure = ["link_app_linux_arm64.klib", "link_greeter_linux_arm64.klib"]
    asserts.equals(env, closure, _basenames(libraries(compile_tool)))
    asserts.equals(env, closure, _basenames(libraries(link_tool)))

    # The srcs see the internals of the associate, which konanc matches by the path of its -l
    # argument, but not those of its deps.
    associate = [path for path in libraries(compile_tool) if path.endswith("/link_app_linux_arm64.klib")]
    asserts.equals(env, associate, [argument_after(compile_tool, "-friend-modules")])
    asserts.false(env, "-friend-modules" in link_tool, str(link_tool))

    # The link generates the test runner, which is the executable of the rule.
    asserts.true(env, "-generate-test-runner" in link_tool, str(link_tool))
    asserts.false(env, "-generate-test-runner" in compile_tool, str(compile_tool))
    binary = link.outputs.to_list()[0]
    asserts.equals(env, "app_test_linux_arm64.kexe", binary.basename)
    asserts.equals(env, binary, analysistest.target_under_test(env)[DefaultInfo].files_to_run.executable)

    return analysistest.end(env)

def _test_not_runnable_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(env, "a kt_native_test for macos_arm64 does not run on the exec host, which runs linux_arm64 binaries")

    return analysistest.end(env)

def _test_with_source_sets_only_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The tests of the source set compile into the private klib, the leaf fragment having no sources.
    compile = single_action(env, "KotlinNativeKlibCompile")
    main_klib = compile.outputs.to_list()[0]
    compile_tool = tool_arguments(compile.argv)
    greeter = PACKAGE + "/testdata/greeter.kt"
    fragments = [_NAMES + "link_ss_tests", _NAMES + "ss_only_test_linux_arm64"]
    asserts.equals(env, [",".join(fragments)], prefixed(compile_tool, "-Xfragments="))
    asserts.equals(env, ["%s:%s" % (fragments[0], greeter)], prefixed(compile_tool, "-Xfragment-sources="))
    asserts.equals(env, [main_klib.path, greeter], compile_tool[compile_tool.index("-o") + 1:])

    # The link generates the runner of the tests of the included klib.
    link_tool = tool_arguments(single_action(env, "KotlinNativeLink").argv)
    asserts.true(env, "-generate-test-runner" in link_tool, str(link_tool))
    asserts.true(env, "-Xinclude=__EXECROOT__/" + main_klib.path in link_tool, str(link_tool))

    return analysistest.end(env)

def _test_without_srcs_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(
        env,
        "kt_native_test has no sources in srcs or source_sets; its test runner only runs the tests of its own sources",
    )

    return analysistest.end(env)

link_test = analysistest.make(_link_test_impl, config_settings = for_target("linux_arm64"))
unstaged_link_test = analysistest.make(
    _unstaged_link_test_impl,
    config_settings = for_target("macos_arm64"),
    expect_failure = True,
)
binary_options_test = analysistest.make(_binary_options_test_impl, config_settings = for_target("linux_arm64"))
binary_without_srcs_test = analysistest.make(_binary_without_srcs_test_impl, config_settings = for_target("linux_arm64"))
binary_fragments_test = analysistest.make(_binary_fragments_test_impl, config_settings = for_target("linux_arm64"))
test_with_source_sets_only_test = analysistest.make(
    _test_with_source_sets_only_test_impl,
    config_settings = for_target("linux_arm64"),
)
test_link_test = analysistest.make(_test_link_test_impl, config_settings = for_target("linux_arm64"))
test_not_runnable_test = analysistest.make(
    _test_not_runnable_test_impl,
    config_settings = for_target("macos_arm64"),
    expect_failure = True,
)
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

    # A binary of the srcs and a source set, whose dep it links.
    kt_source_set(
        name = "link_ss_common",
        srcs = ["testdata/common.kt"],
        tags = ["manual"],
        deps = [":link_greeter_linux_arm64"],
    )
    kt_native_binary(
        name = "source_sets_binary_linux_arm64",
        srcs = ["testdata/main.kt"],
        source_sets = [":link_ss_common"],
        tags = ["manual"],
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
        name = "unrunnable_test_macos_arm64",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
    )
    kt_native_test(
        name = "no_srcs_test_linux_arm64",
        associates = [":link_app_linux_arm64"],
        tags = ["manual"],
    )

    # A test whose tests are all in a source set.
    kt_source_set(
        name = "link_ss_tests",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
    )
    kt_native_test(
        name = "ss_only_test_linux_arm64",
        source_sets = [":link_ss_tests"],
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
    binary_fragments_test(
        name = "binary_fragments_test",
        target_under_test = ":source_sets_binary_linux_arm64",
        target_compatible_with = not_on_windows(),
    )
    test_link_test(
        name = "test_link_test",
        target_under_test = ":app_test_linux_arm64",
        target_compatible_with = not_on_windows(),
    )

    # The fake toolchains run on a linux_arm64 host.
    test_not_runnable_test(
        name = "test_not_runnable_test",
        target_under_test = ":unrunnable_test_macos_arm64",
        target_compatible_with = not_on_windows(),
    )
    test_without_srcs_test(
        name = "test_without_srcs_fails_test",
        target_under_test = ":no_srcs_test_linux_arm64",
        target_compatible_with = not_on_windows(),
    )
    test_with_source_sets_only_test(
        name = "test_with_source_sets_only_test",
        target_under_test = ":ss_only_test_linux_arm64",
        target_compatible_with = not_on_windows(),
    )

    native.test_suite(
        name = name,
        tests = [
            ":binary_fragments_test",
            ":binary_options_test",
            ":binary_without_srcs_test",
            ":link_inputs_test",
            ":test_link_test",
            ":test_not_runnable_test",
            ":test_with_source_sets_only_test",
            ":test_without_srcs_fails_test",
            ":unstaged_link_fails_test",
        ],
    )
