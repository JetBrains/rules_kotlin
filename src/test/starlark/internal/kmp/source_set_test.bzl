"""Analysis tests for kt_source_set: the KtSourceSetInfo and DefaultInfo providers."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//kotlin:kmp.bzl", "KtSourceSetInfo", "kt_source_set")

_PACKAGE = "src/test/starlark/internal/kmp"
_NAME_PREFIX = "src_test_starlark_internal_kmp-"

def _names(infos):
    return [info.name for info in infos]

def _basenames(files):
    return [f.basename for f in files]

def _common_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    info = target[KtSourceSetInfo]

    # The name is derived from the label, as module names are.
    asserts.equals(env, _NAME_PREFIX + "common", info.name)
    asserts.equals(env, Label("//%s:common" % _PACKAGE), info.label)
    asserts.equals(env, ["Platform.kt", "Greeting.kt"], _basenames(info.srcs))
    asserts.equals(env, [], info.deps)
    asserts.equals(env, (), info.depends_on)
    asserts.equals(env, [_NAME_PREFIX + "common"], _names(info.transitive_source_sets.to_list()))

    # Building a source set lists its sources, and compiles nothing.
    asserts.equals(env, ["Platform.kt", "Greeting.kt"], _basenames(target[DefaultInfo].files.to_list()))
    asserts.equals(env, [], analysistest.target_actions(env))

    return analysistest.end(env)

def _refining_test_impl(ctx):
    env = analysistest.begin(ctx)

    info = analysistest.target_under_test(env)[KtSourceSetInfo]
    asserts.equals(env, _NAME_PREFIX + "apple", info.name)
    asserts.equals(env, [_NAME_PREFIX + "common"], _names(info.depends_on))

    # Each source set comes after the source sets it refines.
    asserts.equals(
        env,
        [_NAME_PREFIX + "common", _NAME_PREFIX + "apple"],
        _names(info.transitive_source_sets.to_list()),
    )

    return analysistest.end(env)

def _two_packages_test_impl(ctx):
    env = analysistest.begin(ctx)

    info = analysistest.target_under_test(env)[KtSourceSetInfo]

    # The source sets named common in two packages are two fragments, refined once each.
    asserts.equals(
        env,
        [
            _NAME_PREFIX + "common",
            _NAME_PREFIX + "apple",
            "src_test_starlark_internal_kmp_other-common",
            _NAME_PREFIX + "ios",
        ],
        _names(info.transitive_source_sets.to_list()),
    )
    asserts.equals(env, [Label("//%s:source_set_dep" % _PACKAGE)], [dep.label for dep in info.deps])

    return analysistest.end(env)

def _comma_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(env, "contains ',', which separates the fragments of -Xfragments")

    return analysistest.end(env)

common_test = analysistest.make(_common_test_impl)
refining_test = analysistest.make(_refining_test_impl)
two_packages_test = analysistest.make(_two_packages_test_impl)
comma_test = analysistest.make(_comma_test_impl, expect_failure = True)

def source_set_test_suite(name):
    """Declares the source sets under test and the analysis tests of kt_source_set.

    Args:
      name: the name of the generated test_suite target.
    """
    kt_source_set(
        name = "common",
        srcs = [
            "testdata/Platform.kt",
            "testdata/Greeting.kt",
        ],
        tags = ["manual"],
    )
    kt_source_set(
        name = "apple",
        srcs = ["testdata/Platform.apple.kt"],
        depends_on = [":common"],
        tags = ["manual"],
    )
    native.filegroup(
        name = "source_set_dep",
        srcs = ["testdata/Platform.kt"],
        tags = ["manual"],
    )
    kt_source_set(
        name = "ios",
        srcs = ["testdata/Ios.kt"],
        depends_on = [
            ":apple",
            "//%s/other:common" % _PACKAGE,
        ],
        tags = ["manual"],
        deps = [":source_set_dep"],
    )
    kt_source_set(
        name = "a,b",
        srcs = ["testdata/Ios.kt"],
        tags = ["manual"],
    )

    common_test(
        name = "source_set_provider_test",
        target_under_test = ":common",
    )
    refining_test(
        name = "source_set_depends_on_test",
        target_under_test = ":apple",
    )
    two_packages_test(
        name = "source_set_two_packages_test",
        target_under_test = ":ios",
    )
    comma_test(
        name = "source_set_comma_fails_test",
        target_under_test = ":a,b",
    )

    native.test_suite(
        name = name,
        tests = [
            ":source_set_comma_fails_test",
            ":source_set_depends_on_test",
            ":source_set_provider_test",
            ":source_set_two_packages_test",
        ],
    )
