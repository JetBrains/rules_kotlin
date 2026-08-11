"""Tests for the fixed UTF-8 source encoding on the Java half of kt_jvm targets."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("//kotlin:jvm.bzl", "kt_jvm_library")

def _javac_action(env):
    actions = analysistest.target_actions(env)
    javac_actions = [
        action
        for action in actions
        if action.mnemonic == "Javac"
    ]
    asserts.equals(env, expected = 1, actual = len(javac_actions))
    return javac_actions[0]

def _value_of(env, argv, flag):
    for i in range(len(argv) - 1):
        if argv[i] == flag:
            return argv[i + 1]
    asserts.true(env, False, msg = "flag %s not found in the Javac action" % flag)
    return None

def _utf8_encoding_always_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The Kotlin compiler reads sources as fixed UTF-8 with no option to change it, so the Java
    # half must be compiled with the same hard-coded encoding even when no options are set.
    asserts.equals(
        env,
        expected = "UTF-8",
        actual = _value_of(env, _javac_action(env).argv, "-encoding"),
    )

    return analysistest.end(env)

_utf8_encoding_always_test = analysistest.make(_utf8_encoding_always_test_impl)

def _javac_encoding_contents():
    write_file(
        name = "javac_encoding_java_source",
        out = "JavacEncodingSource.java",
        content = ["class JavacEncodingSource {}"],
        tags = ["manual"],
    )

    kt_jvm_library(
        name = "javac_encoding_library",
        srcs = ["javac_encoding_java_source"],
        tags = ["manual"],
    )

    _utf8_encoding_always_test(
        name = "utf8_encoding_always_test",
        target_under_test = ":javac_encoding_library",
    )

def javac_encoding_test_suite(name):
    _javac_encoding_contents()

    native.test_suite(
        name = name,
        tests = [
            ":utf8_encoding_always_test",
        ],
    )
