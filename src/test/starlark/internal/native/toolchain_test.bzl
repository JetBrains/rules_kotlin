"""Analysis tests for the Kotlin/Native toolchain and the link action of kt_native_binary.

See common.bzl for the fake toolchains.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//kotlin:native.bzl", "kt_native_binary", "kt_native_library")
load(
    ":common.bzl",
    "AIRPLANE_MODE",
    "DEPS",
    "DEP_NAMES",
    "HOME",
    "argument_after",
    "for_target",
    "launcher_arguments",
    "not_on_windows",
    "single_action",
    "tool_arguments",
)

def _toolchain_info_test_impl(ctx):
    env = analysistest.begin(ctx)

    info = analysistest.target_under_test(env)[platform_common.ToolchainInfo]
    asserts.equals(env, "linux_arm64", info.konan_target)
    asserts.false(env, info.is_apple)
    asserts.equals(env, HOME, info.konan_home.path)
    asserts.equals(env, HOME + "/konan", info.konan.path)
    asserts.equals(env, HOME + "/klib/common/stdlib", info.stdlib.path)
    asserts.equals(env, HOME + "/klib/platform/linux_arm64", info.platform_libs.path)

    # Only what klib compilation for linux_arm64 reads: no other target, no bin/, no klib/cache.
    asserts.equals(
        env,
        [
            HOME + "/klib/common/stdlib/default/manifest",
            HOME + "/klib/platform/linux_arm64/posix/default/manifest",
            HOME + "/konan/konan.properties",
            HOME + "/konan/lib/kotlin-native-compiler-embeddable.jar",
        ],
        sorted([f.path for f in info.compile_inputs.to_list()]),
    )

    asserts.true(env, info.konan_deps.staged)
    asserts.equals(env, "linux_arm64", info.konan_deps.konan_target)
    asserts.equals(env, DEP_NAMES, info.konan_deps.names)
    asserts.equals(env, [DEPS + "/dependencies/" + name for name in DEP_NAMES], [d.path for d in info.konan_deps.dirs])
    asserts.equals(env, 3, len(info.konan_deps.files.to_list()))

    # Every action runs the KonanLauncher; a non-Apple target needs nothing of Xcode.
    asserts.equals(env, "konan_launcher", info.launcher.executable.basename)
    asserts.equals(env, {}, info.action_env)
    asserts.equals(env, {}, info.execution_requirements)

    return analysistest.end(env)

def _unstaged_toolchain_info_test_impl(ctx):
    env = analysistest.begin(ctx)

    info = analysistest.target_under_test(env)[platform_common.ToolchainInfo]
    asserts.equals(env, "macos_arm64", info.konan_target)
    asserts.true(env, info.is_apple)
    asserts.false(env, info.konan_deps.staged)
    asserts.equals(env, [], info.konan_deps.dirs)
    asserts.equals(env, [], info.konan_deps.files.to_list())

    # The actions of an Apple target run on darwin, with the Xcode SDK of the target.
    asserts.true(env, "requires-darwin" in info.execution_requirements, str(info.execution_requirements))
    asserts.equals(env, "MacOSX", info.action_env.get("APPLE_SDK_PLATFORM"), str(info.action_env))

    return analysistest.end(env)

def _link_test_impl(ctx):
    env = analysistest.begin(ctx)

    action = single_action(env, "KotlinNativeLink")
    binary = action.outputs.to_list()[0]
    asserts.equals(env, "hello_linux_arm64.kexe", binary.basename)

    inputs = [f.path for f in action.inputs.to_list()]
    for name in DEP_NAMES:
        asserts.true(
            env,
            len([path for path in inputs if path.startswith(DEPS + "/dependencies/" + name + "/")]) == 1,
            "the files of %s should be inputs" % name,
        )
    asserts.true(env, HOME + "/klib/platform/linux_arm64/posix/default/manifest" in inputs)
    asserts.false(env, HOME + "/klib/platform/macos_arm64/posix/default/manifest" in inputs)

    # The launcher stages the dependency directories of the target into the konan data dir.
    argv = action.argv
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
    asserts.equals(env, binary.path, argument_after(tool, "-o"))
    asserts.true(env, AIRPLANE_MODE in tool, "%s should be in %s" % (AIRPLANE_MODE, tool))
    asserts.true(env, "-Xkonan-data-dir=%s.konan_data" % binary.path in tool, str(tool))

    return analysistest.end(env)

def _unstaged_link_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(env, "the Kotlin/Native link dependencies of macos_arm64 are not staged")
    asserts.expect_failure(env, "add 'macos_arm64' to kotlin_native.targets(...)")

    return analysistest.end(env)

toolchain_info_test = analysistest.make(_toolchain_info_test_impl)
unstaged_toolchain_info_test = analysistest.make(_unstaged_toolchain_info_test_impl)
link_test = analysistest.make(_link_test_impl, config_settings = for_target("linux_arm64"))
unstaged_link_test = analysistest.make(
    _unstaged_link_test_impl,
    config_settings = for_target("macos_arm64"),
    expect_failure = True,
)

def native_toolchain_test_suite(name):
    """Declares the targets under test and the analysis tests of the toolchain and the link action.

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

    toolchain_info_test(
        name = "toolchain_info_test",
        target_under_test = ":fake_linux_arm64_toolchain_impl",
        target_compatible_with = not_on_windows(),
    )
    unstaged_toolchain_info_test(
        name = "unstaged_toolchain_info_test",
        target_under_test = ":fake_macos_arm64_toolchain_impl",
        target_compatible_with = not_on_windows(),
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

    native.test_suite(
        name = name,
        tests = [
            ":link_inputs_test",
            ":toolchain_info_test",
            ":unstaged_link_fails_test",
            ":unstaged_toolchain_info_test",
        ],
    )
