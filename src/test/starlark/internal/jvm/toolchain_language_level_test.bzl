"""Tests for the default language and API version of a toolchain on the configured compiler."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("@com_github_jetbrains_kotlin//:version.bzl", "KOTLINC_VERSION")
load("//kotlin:core.bzl", "define_kt_toolchain")
load("//src/main/starlark/core/repositories:language_level.bzl", "toolchain_language_level")
load("//src/main/starlark/core/repositories:versions.bzl", "versions")

_PINNED = "2.4.21"

def _language_level_test_impl(ctx):
    env = unittest.begin(ctx)

    # An older compiler, the one of a kotlinc_version override, compiles at its own version.
    asserts.equals(env, "2.3", toolchain_language_level("2.3.20", _PINNED))
    asserts.equals(env, "2.2", toolchain_language_level("2.2.21", _PINNED))
    asserts.equals(env, "2.0", toolchain_language_level("2.0.21", _PINNED))
    asserts.equals(env, "2.4", toolchain_language_level(_PINNED, _PINNED))
    asserts.equals(env, "2.4", toolchain_language_level("2.4.30", _PINNED))
    asserts.equals(env, "2.4", toolchain_language_level("2.4.30-RC", _PINNED))

    # A development build compiles at the version it is a build of, also when the rules pin one.
    asserts.equals(env, "2.4", toolchain_language_level("2.4.30-dev-1234", _PINNED))
    asserts.equals(env, "2.5", toolchain_language_level("2.5.20-dev-4986", "2.5.20-dev-4986"))

    # A newer compiler, or one older than the toolchain allows, keeps the default of the rule.
    asserts.equals(env, None, toolchain_language_level("2.6.0", _PINNED))
    asserts.equals(env, None, toolchain_language_level("2.5.20-dev-4986", _PINNED))
    asserts.equals(env, None, toolchain_language_level("3.0.0-Beta1", _PINNED))
    asserts.equals(env, None, toolchain_language_level("1.9.25", _PINNED))
    asserts.equals(env, None, toolchain_language_level("latest", _PINNED))
    return unittest.end(env)

language_level_test = unittest.make(_language_level_test_impl)

def _toolchain_versions_test_impl(ctx):
    env = analysistest.begin(ctx)
    toolchain = analysistest.target_under_test(env)[platform_common.ToolchainInfo]
    asserts.equals(env, ctx.attr.expected, toolchain.language_version)
    asserts.equals(env, ctx.attr.expected, toolchain.api_version)
    return analysistest.end(env)

_toolchain_versions_test = analysistest.make(
    _toolchain_versions_test_impl,
    attrs = {"expected": attr.string(mandatory = True)},
)

def toolchain_language_level_test_suite(name):
    """The toolchain follows the configured compiler, unless it sets the versions itself.

    Args:
        name: the name of the test suite.
    """
    level = toolchain_language_level(
        KOTLINC_VERSION,
        versions.KOTLIN_CURRENT_COMPILER_RELEASE.version,
    )
    if level == None:
        fail("the configured compiler %s has no language level" % KOTLINC_VERSION)

    define_kt_toolchain(name = "language_level_unset_toolchain")
    _toolchain_versions_test(
        name = "toolchain_language_level_unset_test",
        expected = level,
        target_under_test = ":language_level_unset_toolchain_impl",
    )

    define_kt_toolchain(
        name = "language_level_explicit_toolchain",
        api_version = "2.3",
        language_version = "2.3",
    )
    _toolchain_versions_test(
        name = "toolchain_language_level_explicit_test",
        expected = "2.3",
        target_under_test = ":language_level_explicit_toolchain_impl",
    )

    unittest.suite(name + "_unit", language_level_test)
    native.test_suite(
        name = name,
        tests = [
            name + "_unit",
            ":toolchain_language_level_explicit_test",
            ":toolchain_language_level_unset_test",
        ],
    )
