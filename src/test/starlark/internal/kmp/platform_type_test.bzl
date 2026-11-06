"""Analysis tests for the Kotlin platform type: an alias selecting a klib for the Kotlin/Native rules and a JVM library for the others.

The alias has the shape of those of kmp_maven: it selects, for the Kotlin/Native rules
(//kotlin/native/platforms:native), an alias of the klib of each konan target
(//kotlin/native/platforms:native_<konan target>), here an imported klib of linux_arm64, and the
JVM library by default. Every consumer builds for the linux_arm64 platform, a host of that konan
target: the Kotlin/Native ones get the klib, as they set //kotlin/settings:kotlin_platform_type to
native for themselves and their deps, and the JVM ones get the JVM library, whose platform type
stays jvm, also through a source set. (A Kotlin/Native consumer of another konan target gets the
no_match_error of the alias, a configuration error that analysistest cannot expect.) The native
consumers use the fake toolchains of //src/test/starlark/internal/native (see common.bzl there).
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_java//java:defs.bzl", "java_library")
load("//kotlin:jvm.bzl", "kt_jvm_library")
load("//kotlin:kmp.bzl", "kt_source_set")
load("//kotlin:native.bzl", "kt_klib_import", "kt_native_library")
load(
    "//src/test/starlark/internal/native:common.bzl",
    "for_target",
    "libraries",
    "not_on_windows",
    "single_action",
    "tool_arguments",
)

_KLIB = "imported.klib"
_JAR = "libpt_jvm_lib-hjar.jar"

def _basename(path):
    return path.rpartition("/")[2]

def _values(argv, flag):
    """The values of every occurrence of a KotlinBuilder flag, which the worker concatenates."""
    values = []
    current = None
    for arg in argv:
        if arg.startswith("--"):
            current = arg
        elif current == flag:
            values.append(arg)
    return values

def _native_consumer_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The consumer compiles against the klib of the alias, which is an input.
    action = single_action(env, "KotlinNativeKlibCompile")
    asserts.equals(env, [_KLIB], [_basename(path) for path in libraries(tool_arguments(action.argv))])
    inputs = [f.basename for f in action.inputs.to_list()]
    asserts.true(env, _KLIB in inputs, "%s should be an input" % _KLIB)
    asserts.false(env, _JAR in inputs, "%s should not be an input" % _JAR)

    return analysistest.end(env)

def _jvm_consumer_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The consumer compiles against the JVM library of the alias, and no klib.
    actions = [action for action in analysistest.target_actions(env) if action.mnemonic == "KotlinCompile"]
    asserts.equals(env, 1, len(actions), "KotlinCompile actions")
    classpath = [_basename(path) for path in _values(actions[0].argv, "--classpath")]
    asserts.true(env, _JAR in classpath, "%s should be in --classpath %s" % (_JAR, classpath))
    inputs = [f.basename for f in actions[0].inputs.to_list()]
    asserts.false(env, _KLIB in inputs, "%s should not be an input" % _KLIB)

    return analysistest.end(env)

native_consumer_test = analysistest.make(_native_consumer_test_impl, config_settings = for_target("linux_arm64"))
jvm_consumer_test = analysistest.make(_jvm_consumer_test_impl, config_settings = for_target("linux_arm64"))

def platform_type_test_suite(name):
    """Declares an alias of a klib and a JVM library, its consumers and the tests of what they get.

    The fake toolchains of //src/test/starlark/internal/native are registered by for_target.

    Args:
      name: the name of the generated test_suite target.
    """
    kt_klib_import(
        name = "pt_klib",
        klib = "//src/test/starlark/internal/native:testdata/imported.klib",
        konan_target = "linux_arm64",
        tags = ["manual"],
    )
    java_library(
        name = "pt_jvm_lib",
        srcs = ["testdata/PlatformTypeLib.java"],
        tags = ["manual"],
    )

    # The aliases of a library resolved for the JVM and linux_arm64, as kmp_maven declares them.
    native.alias(
        name = "pt_lib",
        actual = select({
            str(Label("//kotlin/native/platforms:native")): ":pt_lib_native",
            "//conditions:default": ":pt_jvm_lib",
        }),
        tags = ["manual"],
    )
    native.alias(
        name = "pt_lib_native",
        actual = select(
            {str(Label("//kotlin/native/platforms:native_linux_arm64")): ":pt_klib"},
            no_match_error = "pt_lib has no klib for the konan target of this Kotlin/Native target",
        ),
        tags = ["manual"],
    )

    kt_native_library(
        name = "pt_native_consumer",
        srcs = ["testdata/Platform.linux.kt"],
        tags = ["manual"],
        deps = [":pt_lib"],
    )
    kt_jvm_library(
        name = "pt_jvm_consumer",
        srcs = ["testdata/Platform.jvm.kt"],
        tags = ["manual"],
        deps = [":pt_lib"],
    )

    # The deps of a source set resolve in the configuration of each rule compiling it.
    kt_source_set(
        name = "pt_common",
        srcs = ["testdata/Platform.kt"],
        tags = ["manual"],
        deps = [":pt_lib"],
    )
    kt_native_library(
        name = "pt_native_source_set_consumer",
        srcs = ["testdata/Platform.linux.kt"],
        source_sets = [":pt_common"],
        tags = ["manual"],
    )
    kt_jvm_library(
        name = "pt_jvm_source_set_consumer",
        srcs = ["testdata/Platform.jvm.kt"],
        source_sets = [":pt_common"],
        tags = ["manual"],
    )

    native_consumer_test(
        name = "platform_type_native_consumer_test",
        target_under_test = ":pt_native_consumer",
        target_compatible_with = not_on_windows(),
    )
    jvm_consumer_test(
        name = "platform_type_jvm_consumer_test",
        target_under_test = ":pt_jvm_consumer",
        target_compatible_with = not_on_windows(),
    )
    native_consumer_test(
        name = "platform_type_native_source_set_test",
        target_under_test = ":pt_native_source_set_consumer",
        target_compatible_with = not_on_windows(),
    )
    jvm_consumer_test(
        name = "platform_type_jvm_source_set_test",
        target_under_test = ":pt_jvm_source_set_consumer",
        target_compatible_with = not_on_windows(),
    )

    native.test_suite(
        name = name,
        tests = [
            ":platform_type_jvm_consumer_test",
            ":platform_type_jvm_source_set_test",
            ":platform_type_native_consumer_test",
            ":platform_type_native_source_set_test",
        ],
    )
