"""Analysis tests for the Kotlin/Native rules without srcs: what still builds, and what fails with what to add.

See common.bzl for the fake toolchains.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//kotlin:native.bzl", "KtKlibInfo", "kt_native_binary", "kt_native_framework", "kt_native_library")
load(
    ":common.bzl",
    "PACKAGE",
    "for_target",
    "launcher_values",
    "libraries",
    "not_on_windows",
    "single_action",
    "tool_arguments",
)

def _library_without_sources_test_impl(ctx):
    env = analysistest.begin(ctx)

    # As a kt_jvm_library with exports alone: the library is what it exports. konanc compiles no
    # sources into a klib of the module name, which a consumer lists like any other, and the
    # exports reach the consumers through the provider.
    action = single_action(env, "KotlinNativeKlibCompile")
    asserts.equals(env, [], launcher_values(action.argv, "--source"))
    asserts.equals(env, [PACKAGE + "/sourceless_exported_linux_arm64.klib"], [
        path[path.index(PACKAGE):]
        for path in libraries(tool_arguments(action.argv))
    ])

    info = analysistest.target_under_test(env)[KtKlibInfo]
    asserts.equals(env, "sourceless_linux_arm64.klib", info.klib.basename)
    asserts.equals(env, ["sourceless_exported_linux_arm64.klib"], [f.basename for f in info.exported_klibs.to_list()])
    asserts.equals(
        env,
        ["sourceless_exported_linux_arm64.klib", "sourceless_linux_arm64.klib"],
        sorted([f.basename for f in info.transitive_klibs.to_list()]),
    )

    return analysistest.end(env)

def _failure_test(message, konan_target):
    def _impl(ctx):
        env = analysistest.begin(ctx)
        asserts.expect_failure(env, message)
        return analysistest.end(env)

    return analysistest.make(_impl, config_settings = for_target(konan_target), expect_failure = True)

library_without_sources_test = analysistest.make(
    _library_without_sources_test_impl,
    config_settings = for_target("linux_arm64"),
)

# konanc links nothing out of no klib ("You have not specified any compilation arguments"): the rule
# says what the target lacks instead of running it.
binary_without_srcs_and_deps_test = _failure_test(
    "kt_native_binary has neither srcs nor deps, so nothing to link; add the srcs with `main`, or the dep with it",
    "linux_arm64",
)

# The header of a framework declares the API of its srcs and exports; konanc refuses to link one of
# deps alone the same way.
framework_without_srcs_and_exports_test = _failure_test(
    "kt_native_framework has neither srcs nor exports, so no API for its header; add srcs, or list the libraries of its API in exports",
    "ios_simulator_arm64",
)

def native_sourceless_test_suite(name):
    """Declares the targets without srcs and their tests.

    Args:
      name: the name of the generated test_suite target.
    """
    kt_native_library(
        name = "sourceless_exported_linux_arm64",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
    )
    kt_native_library(
        name = "sourceless_linux_arm64",
        tags = ["manual"],
        exports = [":sourceless_exported_linux_arm64"],
    )
    kt_native_binary(
        name = "sourceless_binary_linux_arm64",
        tags = ["manual"],
    )
    kt_native_library(
        name = "sourceless_dep_ios_simulator_arm64",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
    )
    kt_native_framework(
        name = "SourcelessKit",
        tags = ["manual"],
        deps = [":sourceless_dep_ios_simulator_arm64"],
    )

    library_without_sources_test(
        name = "library_without_sources_test",
        target_under_test = ":sourceless_linux_arm64",
        target_compatible_with = not_on_windows(),
    )
    binary_without_srcs_and_deps_test(
        name = "binary_without_srcs_and_deps_fails_test",
        target_under_test = ":sourceless_binary_linux_arm64",
        target_compatible_with = not_on_windows(),
    )
    framework_without_srcs_and_exports_test(
        name = "framework_without_srcs_and_exports_fails_test",
        target_under_test = ":SourcelessKit",
        target_compatible_with = not_on_windows(),
    )

    native.test_suite(
        name = name,
        tests = [
            ":binary_without_srcs_and_deps_fails_test",
            ":framework_without_srcs_and_exports_fails_test",
            ":library_without_sources_test",
        ],
    )
