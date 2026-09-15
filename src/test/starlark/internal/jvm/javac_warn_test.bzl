"""Tests for deriving the javac warning mode from the Kotlin warn option."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("//kotlin:core.bzl", "kt_kotlinc_options")
load("//kotlin:jvm.bzl", "kt_javac_options", "kt_jvm_library")

def _javac_action(env):
    actions = analysistest.target_actions(env)
    javac_actions = [
        action
        for action in actions
        if action.mnemonic == "Javac"
    ]
    asserts.equals(env, expected = 1, actual = len(javac_actions))
    return javac_actions[0]

def _make_warn_flags_test(expected_present, expected_absent):
    def _impl(ctx):
        env = analysistest.begin(ctx)

        argv = _javac_action(env).argv
        for flag in expected_present:
            asserts.true(
                env,
                flag in argv,
                msg = "expected %s on the Javac action" % flag,
            )
        for flag in expected_absent:
            asserts.false(
                env,
                flag in argv,
                msg = "did not expect %s on the Javac action" % flag,
            )

        return analysistest.end(env)

    return analysistest.make(_impl)

# The Java half follows the Kotlin `warn` option when the javac options set none: a single warn
# value governs the whole target.
_warn_derived_from_kotlinc_error_test = _make_warn_flags_test(["-Werror"], ["-nowarn"])
_warn_derived_from_kotlinc_off_test = _make_warn_flags_test(["-nowarn"], ["-Werror"])

# An explicit javac-side warn wins over the derivation.
_javac_warn_wins_test = _make_warn_flags_test(["-Werror"], ["-nowarn"])

# Without options on either side (toolchain defaults are "report") no warn flag is emitted.
_no_warn_flags_by_default_test = _make_warn_flags_test([], ["-nowarn", "-Werror"])

# A per-diagnostic level limits the derivation. javac has no `-Xwarning-level`, so a Kotlin
# diagnostic kept at `warning` under `warn = "error"` blocks `-Werror` for the Java half, and a
# diagnostic raised to `warning` under `warn = "off"` blocks `-nowarn`.
_warn_error_with_kept_level_test = _make_warn_flags_test([], ["-nowarn", "-Werror"])
_warn_off_with_raised_level_test = _make_warn_flags_test([], ["-nowarn", "-Werror"])

# A level that only raises a diagnostic to `error` keeps the `-Werror` derivation.
_warn_error_with_raised_level_test = _make_warn_flags_test(["-Werror"], ["-nowarn"])

# An explicit javac-side warn still wins over a limited derivation.
_javac_warn_wins_over_level_test = _make_warn_flags_test(["-Werror"], ["-nowarn"])

def _javac_warn_contents():
    write_file(
        name = "javac_warn_java_source",
        out = "JavacWarnSource.java",
        content = ["class JavacWarnSource {}"],
        tags = ["manual"],
    )

    kt_kotlinc_options(
        name = "warn_error_kotlinc_options",
        tags = ["manual"],
        warn = "error",
    )

    kt_kotlinc_options(
        name = "warn_off_kotlinc_options",
        tags = ["manual"],
        warn = "off",
    )

    kt_kotlinc_options(
        name = "warn_error_kept_level_kotlinc_options",
        tags = ["manual"],
        warn = "error",
        x_warning_level = {"DEPRECATION": "warning"},
    )

    kt_kotlinc_options(
        name = "warn_error_raised_level_kotlinc_options",
        tags = ["manual"],
        warn = "error",
        x_warning_level = {"UNUSED_VARIABLE": "error"},
    )

    kt_kotlinc_options(
        name = "warn_off_raised_level_kotlinc_options",
        tags = ["manual"],
        warn = "off",
        x_warning_level = {"DEPRECATION": "warning"},
    )

    kt_javac_options(
        name = "warn_error_javac_options",
        tags = ["manual"],
        warn = "error",
    )

    kt_jvm_library(
        name = "javac_warn_error_derived_library",
        srcs = ["javac_warn_java_source"],
        kotlinc_opts = ":warn_error_kotlinc_options",
        tags = ["manual"],
    )

    kt_jvm_library(
        name = "javac_warn_off_derived_library",
        srcs = ["javac_warn_java_source"],
        kotlinc_opts = ":warn_off_kotlinc_options",
        tags = ["manual"],
    )

    kt_jvm_library(
        name = "javac_warn_wins_library",
        srcs = ["javac_warn_java_source"],
        javac_opts = ":warn_error_javac_options",
        kotlinc_opts = ":warn_off_kotlinc_options",
        tags = ["manual"],
    )

    kt_jvm_library(
        name = "javac_warn_default_library",
        srcs = ["javac_warn_java_source"],
        tags = ["manual"],
    )

    kt_jvm_library(
        name = "javac_warn_error_kept_level_library",
        srcs = ["javac_warn_java_source"],
        kotlinc_opts = ":warn_error_kept_level_kotlinc_options",
        tags = ["manual"],
    )

    kt_jvm_library(
        name = "javac_warn_error_raised_level_library",
        srcs = ["javac_warn_java_source"],
        kotlinc_opts = ":warn_error_raised_level_kotlinc_options",
        tags = ["manual"],
    )

    kt_jvm_library(
        name = "javac_warn_off_raised_level_library",
        srcs = ["javac_warn_java_source"],
        kotlinc_opts = ":warn_off_raised_level_kotlinc_options",
        tags = ["manual"],
    )

    kt_jvm_library(
        name = "javac_warn_wins_over_level_library",
        srcs = ["javac_warn_java_source"],
        javac_opts = ":warn_error_javac_options",
        kotlinc_opts = ":warn_error_kept_level_kotlinc_options",
        tags = ["manual"],
    )

    _warn_derived_from_kotlinc_error_test(
        name = "warn_derived_from_kotlinc_error_test",
        target_under_test = ":javac_warn_error_derived_library",
    )

    _warn_derived_from_kotlinc_off_test(
        name = "warn_derived_from_kotlinc_off_test",
        target_under_test = ":javac_warn_off_derived_library",
    )

    _javac_warn_wins_test(
        name = "javac_warn_wins_test",
        target_under_test = ":javac_warn_wins_library",
    )

    _no_warn_flags_by_default_test(
        name = "no_warn_flags_by_default_test",
        target_under_test = ":javac_warn_default_library",
    )

    _warn_error_with_kept_level_test(
        name = "warn_error_with_kept_level_test",
        target_under_test = ":javac_warn_error_kept_level_library",
    )

    _warn_error_with_raised_level_test(
        name = "warn_error_with_raised_level_test",
        target_under_test = ":javac_warn_error_raised_level_library",
    )

    _warn_off_with_raised_level_test(
        name = "warn_off_with_raised_level_test",
        target_under_test = ":javac_warn_off_raised_level_library",
    )

    _javac_warn_wins_over_level_test(
        name = "javac_warn_wins_over_level_test",
        target_under_test = ":javac_warn_wins_over_level_library",
    )

def javac_warn_test_suite(name):
    _javac_warn_contents()

    native.test_suite(
        name = name,
        tests = [
            ":warn_derived_from_kotlinc_error_test",
            ":warn_derived_from_kotlinc_off_test",
            ":javac_warn_wins_test",
            ":no_warn_flags_by_default_test",
            ":warn_error_with_kept_level_test",
            ":warn_error_with_raised_level_test",
            ":warn_off_with_raised_level_test",
            ":javac_warn_wins_over_level_test",
        ],
    )
