"""Analysis tests for the Kotlin/Native toolchain.

See common.bzl for the fake toolchains, and binary_test.bzl for the link action.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load(
    ":common.bzl",
    "DEPS",
    "DEP_NAMES",
    "FAKE_HOST",
    "HOME",
    "not_on_windows",
)

def _toolchain_info_test_impl(ctx):
    env = analysistest.begin(ctx)

    info = analysistest.target_under_test(env)[platform_common.ToolchainInfo]
    asserts.equals(env, "linux_arm64", info.konan_target)
    asserts.equals(env, FAKE_HOST, info.konan_host)
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
    asserts.equals(env, FAKE_HOST, info.konan_host)
    asserts.true(env, info.is_apple)
    asserts.false(env, info.konan_deps.staged)
    asserts.equals(env, [], info.konan_deps.dirs)
    asserts.equals(env, [], info.konan_deps.files.to_list())

    # The actions of an Apple target run on darwin, with the Xcode SDK of the target.
    asserts.true(env, "requires-darwin" in info.execution_requirements, str(info.execution_requirements))
    asserts.equals(env, "MacOSX", info.action_env.get("APPLE_SDK_PLATFORM"), str(info.action_env))

    return analysistest.end(env)

toolchain_info_test = analysistest.make(_toolchain_info_test_impl)
unstaged_toolchain_info_test = analysistest.make(_unstaged_toolchain_info_test_impl)

def native_toolchain_test_suite(name):
    """Declares the analysis tests of the toolchain.

    The fake toolchains (common.bzl: define_fake_toolchains) must be declared in the package.

    Args:
      name: the name of the generated test_suite target.
    """
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

    native.test_suite(
        name = name,
        tests = [
            ":toolchain_info_test",
            ":unstaged_toolchain_info_test",
        ],
    )
