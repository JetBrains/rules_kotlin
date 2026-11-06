"""Analysis tests for kt_native_framework: the link of a static Apple framework.

See common.bzl for the fake toolchains.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//kotlin:native.bzl", "kt_native_framework", "kt_native_library")
load(
    ":common.bzl",
    "DEPS",
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

def _basenames(paths):
    return sorted([path.rpartition("/")[2] for path in paths])

def _framework_link_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The srcs compile into the private klib, against the deps and the exports. The klib keeps its
    # module name: the framework, like the prefix of its Objective-C names, is named after the target.
    compile = single_action(env, "KotlinNativeKlibCompile")
    main_klib = compile.outputs.to_list()[0]
    asserts.equals(env, PACKAGE + "/_kt_native/GreeterKit.klib", main_klib.short_path)
    compile_tool = tool_arguments(compile.argv)
    asserts.equals(env, "src_test_starlark_internal_native-GreeterKit", argument_after(compile_tool, "-module-name"))
    closure = [
        "fw_dep_ios_simulator_arm64.klib",
        "fw_exported_ios_simulator_arm64.klib",
        "fw_reexported_ios_simulator_arm64.klib",
    ]
    asserts.equals(env, closure, _basenames(libraries(compile_tool)))

    # The framework is a directory, the only output of the rule.
    link = single_action(env, "KotlinNativeLink")
    framework = link.outputs.to_list()[0]
    asserts.true(env, framework.is_directory, "%s should be a directory" % framework.path)
    asserts.equals(env, "GreeterKit.framework", framework.basename)
    asserts.equals(env, [framework], analysistest.target_under_test(env)[DefaultInfo].files.to_list())

    tool = tool_arguments(link.argv)
    asserts.equals(env, "framework", argument_after(tool, "-produce"))
    asserts.equals(env, "ios_simulator_arm64", argument_after(tool, "-target"))
    for flag in [
        NO_LIGHT_DEBUG,
        "-Xstatic-framework",
        "-Xbinary=bundleId=org.example.GreeterKit",
        "-Xinclude=__EXECROOT__/" + main_klib.path,
        "-Xkonan-data-dir=%s.konan_data" % framework.path,
    ]:
        asserts.true(env, flag in tool, "%s should be in %s" % (flag, tool))
    asserts.false(env, "-module-name" in tool, str(tool))
    asserts.equals(env, ["-o", framework.path], tool[-2:])

    # It exports the exports and their exports, but not the deps, each written as its -l argument,
    # which is how konanc matches them.
    asserts.equals(env, closure, _basenames(libraries(tool)))
    exported = [path for path in libraries(tool) if "/fw_dep_" not in path]
    asserts.equals(env, 2, len(exported))
    asserts.equals(env, sorted(exported), sorted(prefixed(tool, "-Xexport-library=")))

    # An iOS target links with the dependencies of the host only, and the Xcode SDK of the target.
    launcher = launcher_arguments(link.argv)
    asserts.equals(env, framework.path + ".konan_data", argument_after(launcher, "--data-dir"))
    asserts.equals(
        env,
        [DEPS + "/dependencies/libffi-fixture", DEPS + "/dependencies/llvm-fixture"],
        [launcher[i + 1] for i in range(len(launcher)) if launcher[i] == "--staged-deps"],
    )
    inputs = [f.path for f in link.inputs.to_list()]
    asserts.true(env, main_klib.path in inputs, "the private klib should be an input")
    asserts.equals(env, [], [path for path in inputs if path.startswith(DEPS + "/dependencies/gcc-fixture/")])
    asserts.equals(env, "iPhoneSimulator", link.env.get("APPLE_SDK_PLATFORM"), str(link.env))

    return analysistest.end(env)

def _framework_files_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The output group framework_files holds the files rules_apple imports, with the layout of an iOS
    # framework under _kt_native/: the framework directory stays the only default output.
    target = analysistest.target_under_test(env)
    framework = single_action(env, "KotlinNativeLink").outputs.to_list()[0]
    asserts.equals(env, [framework], target[DefaultInfo].files.to_list())
    files = target[OutputGroupInfo].framework_files.to_list()
    prefix = PACKAGE + "/_kt_native/GreeterKit.framework/"
    paths = ["GreeterKit", "Headers/GreeterKit.h", "Modules/module.modulemap", "Info.plist"]
    asserts.equals(env, [prefix + path for path in paths], [file.short_path for file in files])

    # One action copies them out of the framework directory, its only input, which it gets first, then a
    # pair of a path in the framework and an output per file. An iOS framework has its Info.plist at the top.
    copy = single_action(env, "KotlinNativeFrameworkFiles")
    asserts.equals(env, [framework], copy.inputs.to_list())
    asserts.equals(env, files, copy.outputs.to_list())
    arguments = copy.argv[copy.argv.index(framework.path) + 1:]
    expected = []
    for path, file in zip(paths, files):
        expected.extend([path, file.path])
    asserts.equals(env, expected, arguments)

    return analysistest.end(env)

def _framework_without_srcs_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The framework consists of its exports: there is nothing to compile, and nothing to include.
    asserts.equals(env, [], [action for action in analysistest.target_actions(env) if action.mnemonic == "KotlinNativeKlibCompile"])
    tool = tool_arguments(single_action(env, "KotlinNativeLink").argv)
    asserts.equals(env, [], prefixed(tool, "-Xinclude="))
    asserts.true(env, "-Xstatic-framework" in tool, str(tool))
    asserts.equals(
        env,
        ["fw_exported_ios_simulator_arm64.klib", "fw_reexported_ios_simulator_arm64.klib"],
        _basenames(prefixed(tool, "-Xexport-library=")),
    )

    # Without a bundle_id, konanc derives one.
    asserts.equals(env, [], prefixed(tool, "-Xbinary=bundleId="))

    # Its files are named after the target too.
    asserts.equals(
        env,
        ["ExportsOnlyKit", "ExportsOnlyKit.h", "Info.plist", "module.modulemap"],
        _basenames([file.short_path for file in analysistest.target_under_test(env)[OutputGroupInfo].framework_files.to_list()]),
    )

    return analysistest.end(env)

def _framework_non_apple_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(env, "kt_native_framework builds Apple frameworks, but this target is linux_arm64")

    return analysistest.end(env)

def _framework_unstaged_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(env, "the Kotlin/Native link dependencies of macos_arm64 are not staged")

    return analysistest.end(env)

framework_link_test = analysistest.make(_framework_link_test_impl, config_settings = for_target("ios_simulator_arm64"))
framework_files_test = analysistest.make(_framework_files_test_impl, config_settings = for_target("ios_simulator_arm64"))
framework_without_srcs_test = analysistest.make(
    _framework_without_srcs_test_impl,
    config_settings = for_target("ios_simulator_arm64"),
)
framework_non_apple_test = analysistest.make(
    _framework_non_apple_test_impl,
    config_settings = for_target("linux_arm64"),
    expect_failure = True,
)
framework_unstaged_test = analysistest.make(
    _framework_unstaged_test_impl,
    config_settings = for_target("macos_arm64"),
    expect_failure = True,
)

def native_framework_test_suite(name):
    """Declares the targets under test and the analysis tests of kt_native_framework.

    The fake toolchains (common.bzl: define_fake_toolchains) must be declared in the package.

    Args:
      name: the name of the generated test_suite target.
    """

    # GreeterKit: deps = [fw_dep], exports = [fw_exported], which exports fw_reexported.
    for library in ["fw_dep", "fw_reexported"]:
        kt_native_library(
            name = library + "_ios_simulator_arm64",
            srcs = ["testdata/greeter.kt"],
            tags = ["manual"],
        )
    kt_native_library(
        name = "fw_exported_ios_simulator_arm64",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
        exports = [":fw_reexported_ios_simulator_arm64"],
    )
    kt_native_framework(
        name = "GreeterKit",
        srcs = ["testdata/greeter.kt"],
        bundle_id = "org.example.GreeterKit",
        tags = ["manual"],
        exports = [":fw_exported_ios_simulator_arm64"],
        deps = [":fw_dep_ios_simulator_arm64"],
    )
    kt_native_framework(
        name = "ExportsOnlyKit",
        tags = ["manual"],
        exports = [":fw_exported_ios_simulator_arm64"],
    )
    kt_native_framework(
        name = "LinuxKit",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
    )
    kt_native_framework(
        name = "MacKit",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
    )

    framework_link_test(
        name = "framework_link_test",
        target_under_test = ":GreeterKit",
        target_compatible_with = not_on_windows(),
    )
    framework_files_test(
        name = "framework_files_test",
        target_under_test = ":GreeterKit",
        target_compatible_with = not_on_windows(),
    )
    framework_without_srcs_test(
        name = "framework_without_srcs_test",
        target_under_test = ":ExportsOnlyKit",
        target_compatible_with = not_on_windows(),
    )
    framework_non_apple_test(
        name = "framework_non_apple_fails_test",
        target_under_test = ":LinuxKit",
        target_compatible_with = not_on_windows(),
    )

    # Apple, but its bundle does not stage it.
    framework_unstaged_test(
        name = "framework_unstaged_fails_test",
        target_under_test = ":MacKit",
        target_compatible_with = not_on_windows(),
    )

    native.test_suite(
        name = name,
        tests = [
            ":framework_files_test",
            ":framework_link_test",
            ":framework_non_apple_fails_test",
            ":framework_unstaged_fails_test",
            ":framework_without_srcs_test",
        ],
    )
