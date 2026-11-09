"""Analysis tests for the KSP rules of Kotlin Multiplatform: the declared outputs and the libraries of each platform.

kt_jvm_ksp_sources declares its generated files as individual outputs of the target and compiles against the
JVM libraries of its deps. kt_native_ksp_sources, built for a konan target, runs on the klibs of that target
and never on the JVM library of the same alias (see platform_type_test.bzl). Both run the KSP tool of the
toolchain on the processor classpath. The action itself is tested by ksp_run_test.sh, and the whole by the
examples/kmp fixture. The native tests use the fake toolchains of //src/test/starlark/internal/native.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_java//java:defs.bzl", "java_library")
load("//kotlin:core.bzl", "kt_ksp_plugin")
load("//kotlin:kmp.bzl", "kt_jvm_ksp_sources", "kt_native_ksp_sources")
load("//kotlin:native.bzl", "kt_klib_import")
load(
    "//src/test/starlark/internal/native:common.bzl",
    "for_target",
    "not_on_windows",
    "single_action",
)

_KLIB = "imported.klib"
_JAR = "libksp_jvm_lib-hjar.jar"

def _input_names(action):
    return [f.basename for f in action.inputs.to_list()]

def _source_roots(action):
    """The base names of the `-source-roots` of the KSP command line, in its order."""
    for arg in action.argv:
        if arg.startswith("-source-roots="):
            return [path.rsplit("/", 1)[-1] for path in arg[len("-source-roots="):].split(":")]
    return None

def _jvm_test_impl(ctx):
    env = analysistest.begin(ctx)
    action = single_action(env, "KspJvm")

    # The generated files are the outputs: a directory of the target, then the path KSP writes them under.
    outputs = [f.short_path for f in action.outputs.to_list()]
    asserts.equals(env, 2, len(outputs), "outputs %s" % outputs)
    for output in outputs:
        asserts.true(env, "/ksp_jvm/gen/" in output, "%s should be under the directory of the target" % output)
    asserts.equals(env, ["Gen.kt", "Other.kt"], sorted([f.basename for f in action.outputs.to_list()]))

    # The JVM library of the dep is a library of the tool, with the classpath of the processor and of the tool.
    inputs = _input_names(action)
    asserts.true(env, _JAR in inputs, "%s should be an input: %s" % (_JAR, inputs))
    asserts.true(env, "libksp_processor_lib.jar" in inputs, "the processor should be an input: %s" % inputs)
    asserts.true(env, "Platform.jvm.kt" in inputs, "the sources should be inputs")
    asserts.false(env, _KLIB in inputs, "no klib is an input of the JVM rule")

    # The sources of the platform come before the common ones, once each, as the KSP Gradle plugin orders them:
    # the `actual` declarations of the platform are the ones KSP resolves a type to. No -common-source-roots: the
    # tool would only add them to the roots again.
    asserts.equals(env, ["Platform.jvm.kt", "Greeting.kt"], _source_roots(action))
    asserts.false(env, any([arg.startswith("-common-source-roots") for arg in action.argv]), str(action.argv))
    return analysistest.end(env)

def _native_test_impl(ctx):
    env = analysistest.begin(ctx)
    action = single_action(env, "KspNative")
    inputs = _input_names(action)
    asserts.true(env, _KLIB in inputs, "%s should be an input: %s" % (_KLIB, inputs))
    asserts.false(env, _JAR in inputs, "the JVM library of the alias must not be an input of the native rule: %s" % inputs)
    asserts.equals(env, ["Gen.kt"], [f.basename for f in action.outputs.to_list()])
    return analysistest.end(env)

def _failure_test(message):
    def _impl(ctx):
        env = analysistest.begin(ctx)
        asserts.expect_failure(env, message)
        return analysistest.end(env)

    return analysistest.make(_impl, expect_failure = True)

jvm_test = analysistest.make(_jvm_test_impl)
native_test = analysistest.make(_native_test_impl, config_settings = for_target("linux_arm64"))
empty_generated_test = _failure_test("generated lists no file")
not_kotlin_test = _failure_test("must be a relative path of a .kt file")
absolute_test = _failure_test("must be a relative path of a .kt file")
parent_test = _failure_test("must be a relative path of a .kt file")
duplicate_test = _failure_test("generated lists 'a/Gen.kt' twice")

def ksp_test_suite(name):
    """Declares KSP targets, and the tests of their outputs and libraries.

    Args:
      name: the name of the generated test_suite target.
    """
    java_library(
        name = "ksp_jvm_lib",
        srcs = ["testdata/PlatformTypeLib.java"],
        tags = ["manual"],
    )
    java_library(
        name = "ksp_processor_lib",
        srcs = ["testdata/PlatformTypeLib.java"],
        tags = ["manual"],
    )
    kt_ksp_plugin(
        name = "ksp_processor",
        processor_class = "example.Provider",
        deps = [":ksp_processor_lib"],
        tags = ["manual"],
    )
    kt_klib_import(
        name = "ksp_klib",
        klib = "//src/test/starlark/internal/native:testdata/imported.klib",
        konan_target = "linux_arm64",
        tags = ["manual"],
    )
    native.alias(
        name = "ksp_lib",
        actual = select({
            str(Label("//kotlin/native/platforms:native")): ":ksp_lib_native",
            "//conditions:default": ":ksp_jvm_lib",
        }),
        tags = ["manual"],
    )
    native.alias(
        name = "ksp_lib_native",
        actual = select(
            {str(Label("//kotlin/native/platforms:native_linux_arm64")): ":ksp_klib"},
            no_match_error = "ksp_lib has no klib for the konan target of this Kotlin/Native target",
        ),
        tags = ["manual"],
    )

    kt_jvm_ksp_sources(
        name = "ksp_jvm",
        # The common sources first, as a BUILD file may list them: the rule orders the platform's before them.
        srcs = [
            "testdata/Greeting.kt",
            "testdata/Platform.jvm.kt",
        ],
        common_srcs = ["testdata/Greeting.kt"],
        generated = ["gen/Gen.kt", "gen/Other.kt"],
        processors = [":ksp_processor"],
        tags = ["manual"],
        deps = [":ksp_lib"],
    )
    kt_native_ksp_sources(
        name = "ksp_native",
        srcs = ["testdata/Platform.apple.kt"],
        generated = ["Gen.kt"],
        processors = [":ksp_processor"],
        tags = ["manual"],
        deps = [":ksp_lib"],
    )

    for test_name, invalid, rule in [
        ("empty", [], empty_generated_test),
        ("not_kotlin", ["a/Gen.java"], not_kotlin_test),
        ("absolute", ["/a/Gen.kt"], absolute_test),
        ("parent", ["../Gen.kt"], parent_test),
        ("duplicate", ["a/Gen.kt", "a/Gen.kt"], duplicate_test),
    ]:
        kt_jvm_ksp_sources(
            name = "ksp_invalid_" + test_name,
            srcs = ["testdata/Platform.jvm.kt"],
            generated = invalid,
            processors = [":ksp_processor"],
            tags = ["manual"],
        )
        rule(
            name = "ksp_%s_test" % test_name,
            target_under_test = ":ksp_invalid_" + test_name,
            target_compatible_with = not_on_windows(),
        )

    jvm_test(
        name = "ksp_jvm_test",
        target_under_test = ":ksp_jvm",
        target_compatible_with = not_on_windows(),
    )
    native_test(
        name = "ksp_native_test",
        target_under_test = ":ksp_native",
        target_compatible_with = not_on_windows(),
    )

    native.test_suite(
        name = name,
        tests = [
            ":ksp_absolute_test",
            ":ksp_duplicate_test",
            ":ksp_empty_test",
            ":ksp_jvm_test",
            ":ksp_native_test",
            ":ksp_not_kotlin_test",
            ":ksp_parent_test",
        ],
    )
