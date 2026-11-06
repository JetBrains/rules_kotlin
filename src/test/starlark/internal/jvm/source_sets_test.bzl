"""Analysis tests for the source_sets of the JVM rules: the K2 fragments of the KotlinCompile action."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@rules_java//java:defs.bzl", "java_library", "java_plugin")
load("//kotlin:core.bzl", "kt_ksp_plugin")
load("//kotlin:jvm.bzl", "kt_jvm_binary", "kt_jvm_library", "kt_jvm_test")
load("//kotlin:kmp.bzl", "kt_source_set")

# The prefix of the module and fragment names derived from the labels of the package.
_NAMES = "src_test_starlark_internal_jvm-"

def _kotlin_compile(env):
    actions = [action for action in analysistest.target_actions(env) if action.mnemonic == "KotlinCompile"]
    asserts.equals(env, 1, len(actions), "KotlinCompile actions")
    return actions[0]

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

def _basename(path):
    return path.rpartition("/")[2]

def _is_fragment_flag(value):
    return value in ["-Xmulti-platform", "-Xexpect-actual-classes"] or value.startswith("-Xfragment")

def _fragments_test_impl(ctx):
    env = analysistest.begin(ctx)

    action = _kotlin_compile(env)
    argv = action.argv

    # The sources of the fragments, each after those of the fragments it refines, those of the
    # target last.
    fragment_sources = [
        (fragment, source)
        for fragment in ctx.attr.fragments
        for source in ctx.attr.fragment_sources.get(fragment, [])
    ]
    sources = _values(argv, "--sources")
    asserts.equals(env, [source for _, source in fragment_sources], [_basename(path) for path in sources])
    inputs = [f.path for f in action.inputs.to_list()]
    for source in sources:
        asserts.true(env, source in inputs, "%s should be an input" % source)

    # The fragment flags are values of --kotlin_passthrough_flags, with the paths of --sources.
    path_of = {_basename(path): path for path in sources}
    expected = [
        "-Xmulti-platform",
        "-Xexpect-actual-classes",
        "-Xfragments=" + ",".join([_NAMES + fragment for fragment in ctx.attr.fragments]),
    ] + [
        "-Xfragment-sources=%s%s:%s" % (_NAMES, fragment, path_of.get(source))
        for fragment, source in fragment_sources
    ] + [
        "-Xfragment-refines=%s%s:%s%s" % (_NAMES, fragment, _NAMES, refined)
        for fragment, _, refined in [refinement.partition(":") for refinement in ctx.attr.refines]
    ]
    passthrough = _values(argv, "--kotlin_passthrough_flags")
    start = passthrough.index("-Xmulti-platform")
    asserts.equals(env, expected, passthrough[start:start + len(expected)])
    asserts.equals(env, expected, [value for value in passthrough if _is_fragment_flag(value)])

    # The deps of the source sets are direct deps of the compilation.
    for flag in ["--classpath", "--direct_dependencies"]:
        asserts.true(
            env,
            "libss_java_dep-hjar.jar" in [_basename(path) for path in _values(argv, flag)],
            "the dep of the source set should be in %s" % flag,
        )

    return analysistest.end(env)

def _no_source_sets_test_impl(ctx):
    env = analysistest.begin(ctx)

    argv = _kotlin_compile(env).argv
    asserts.equals(env, [], [value for value in argv if _is_fragment_flag(value)])

    return analysistest.end(env)

def _expect_failure_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(env, ctx.attr.message)

    return analysistest.end(env)

_fragments_test = analysistest.make(
    _fragments_test_impl,
    attrs = {
        # The basenames of the sources of each fragment.
        "fragment_sources": attr.string_list_dict(),
        # The fragments, by the name of their target, each after those it refines, the leaf last.
        "fragments": attr.string_list(),
        # The refinements, <fragment>:<refined fragment>, in the order of the flags.
        "refines": attr.string_list(),
    },
)
_no_source_sets_test = analysistest.make(_no_source_sets_test_impl)
_expect_failure_test = analysistest.make(
    _expect_failure_test_impl,
    attrs = {"message": attr.string()},
    expect_failure = True,
)

def _source_sets_contents():
    for name, out, content in [
        ("ss_platform_kt", "Platform.kt", ["package ss", "", "expect fun platformName(): String"]),
        ("ss_greeting_kt", "Greeting.kt", ["package ss", "", "fun greeting(): String = \"Hello from \" + platformName()"]),
        ("ss_jvm_platform_kt", "Platform.jvm.kt", ["package ss", "", "actual fun platformName(): String = \"JVM\""]),
        ("ss_main_kt", "Main.kt", ["package ss", "", "fun main() = println(greeting())"]),
        ("ss_dep_java", "Dep.java", ["package ss;", "", "public class Dep {}"]),
        ("ss_processor_java", "Processor.java", ["package ss;", "", "public class Processor {}"]),
        ("ss_srcjar", "Gen.srcjar", [""]),
    ]:
        write_file(
            name = name,
            out = "source_sets/" + out,
            content = content,
            tags = ["manual"],
        )

    java_library(
        name = "ss_java_dep",
        srcs = [":ss_dep_java"],
        tags = ["manual"],
    )

    # ss_greeting refines ss_common, which has a JVM dep.
    kt_source_set(
        name = "ss_common",
        srcs = [":ss_platform_kt"],
        tags = ["manual"],
        deps = [":ss_java_dep"],
    )
    kt_source_set(
        name = "ss_greeting",
        srcs = [":ss_greeting_kt"],
        depends_on = [":ss_common"],
        tags = ["manual"],
    )

    kt_jvm_library(
        name = "ss_library",
        srcs = [":ss_jvm_platform_kt"],
        source_sets = [":ss_greeting"],
        tags = ["manual"],
    )
    kt_source_set(
        name = "ss_jvm_actual",
        srcs = [":ss_jvm_platform_kt"],
        depends_on = [":ss_greeting"],
        tags = ["manual"],
    )
    kt_jvm_library(
        name = "ss_sourceless_library",
        source_sets = [":ss_jvm_actual"],
        tags = ["manual"],
    )
    kt_jvm_binary(
        name = "ss_binary",
        srcs = [
            ":ss_jvm_platform_kt",
            ":ss_main_kt",
        ],
        main_class = "ss.MainKt",
        source_sets = [":ss_greeting"],
        tags = ["manual"],
    )
    kt_jvm_test(
        name = "ss_test",
        srcs = [":ss_jvm_platform_kt"],
        source_sets = [":ss_greeting"],
        tags = ["manual"],
        test_class = "ss.PlatformTest",
    )
    kt_jvm_library(
        name = "ss_free_library",
        srcs = [":ss_jvm_platform_kt"],
        tags = ["manual"],
        deps = [":ss_java_dep"],
    )

    # What a compilation with source sets rejects.
    kt_jvm_library(
        name = "ss_srcjar_library",
        srcs = [
            ":ss_jvm_platform_kt",
            ":ss_srcjar",
        ],
        source_sets = [":ss_common"],
        tags = ["manual"],
    )
    java_plugin(
        name = "ss_kapt_processor",
        srcs = [":ss_processor_java"],
        processor_class = "ss.Processor",
        tags = ["manual"],
    )
    kt_jvm_library(
        name = "ss_kapt_library",
        srcs = [":ss_jvm_platform_kt"],
        plugins = [":ss_kapt_processor"],
        source_sets = [":ss_common"],
        tags = ["manual"],
    )
    java_library(
        name = "ss_ksp_processor_lib",
        srcs = [":ss_processor_java"],
        tags = ["manual"],
    )
    kt_ksp_plugin(
        name = "ss_ksp_processor",
        processor_class = "ss.Processor",
        tags = ["manual"],
        deps = [":ss_ksp_processor_lib"],
    )
    kt_jvm_library(
        name = "ss_ksp_library",
        srcs = [":ss_jvm_platform_kt"],
        plugins = [":ss_ksp_processor"],
        source_sets = [":ss_common"],
        tags = ["manual"],
    )
    native.filegroup(
        name = "ss_files",
        srcs = [":ss_dep_java"],
        tags = ["manual"],
    )
    kt_source_set(
        name = "ss_files_dep",
        srcs = [":ss_platform_kt"],
        tags = ["manual"],
        deps = [":ss_files"],
    )
    kt_jvm_library(
        name = "ss_files_dep_library",
        srcs = [":ss_jvm_platform_kt"],
        source_sets = [":ss_files_dep"],
        tags = ["manual"],
    )
    kt_jvm_library(
        name = "ss_module_name_library",
        srcs = [":ss_jvm_platform_kt"],
        module_name = _NAMES + "ss_common",
        source_sets = [":ss_common"],
        tags = ["manual"],
    )

    _fragments_test(
        name = "source_sets_library_test",
        target_under_test = ":ss_library",
        fragment_sources = {
            "ss_common": ["Platform.kt"],
            "ss_greeting": ["Greeting.kt"],
            "ss_library": ["Platform.jvm.kt"],
        },
        fragments = ["ss_common", "ss_greeting", "ss_library"],
        refines = ["ss_greeting:ss_common", "ss_library:ss_greeting"],
    )
    _fragments_test(
        name = "source_sets_sourceless_library_test",
        target_under_test = ":ss_sourceless_library",
        fragment_sources = {
            "ss_common": ["Platform.kt"],
            "ss_greeting": ["Greeting.kt"],
            "ss_jvm_actual": ["Platform.jvm.kt"],
        },
        fragments = ["ss_common", "ss_greeting", "ss_jvm_actual", "ss_sourceless_library"],
        refines = [
            "ss_greeting:ss_common",
            "ss_jvm_actual:ss_greeting",
            "ss_sourceless_library:ss_jvm_actual",
        ],
    )
    _fragments_test(
        name = "source_sets_binary_test",
        target_under_test = ":ss_binary",
        fragment_sources = {
            "ss_binary": ["Platform.jvm.kt", "Main.kt"],
            "ss_common": ["Platform.kt"],
            "ss_greeting": ["Greeting.kt"],
        },
        fragments = ["ss_common", "ss_greeting", "ss_binary"],
        refines = ["ss_greeting:ss_common", "ss_binary:ss_greeting"],
    )
    _fragments_test(
        name = "source_sets_test_test",
        target_under_test = ":ss_test",
        fragment_sources = {
            "ss_common": ["Platform.kt"],
            "ss_greeting": ["Greeting.kt"],
            "ss_test": ["Platform.jvm.kt"],
        },
        fragments = ["ss_common", "ss_greeting", "ss_test"],
        refines = ["ss_greeting:ss_common", "ss_test:ss_greeting"],
    )
    _no_source_sets_test(
        name = "source_sets_none_test",
        target_under_test = ":ss_free_library",
    )
    _expect_failure_test(
        name = "source_sets_srcjar_fails_test",
        target_under_test = ":ss_srcjar_library",
        message = "source_sets cannot be combined with .srcjar sources",
    )
    _expect_failure_test(
        name = "source_sets_kapt_fails_test",
        target_under_test = ":ss_kapt_library",
        message = "source_sets cannot be combined with kapt",
    )
    _expect_failure_test(
        name = "source_sets_ksp_fails_test",
        target_under_test = ":ss_ksp_library",
        message = "source_sets cannot be combined with KSP",
    )
    _expect_failure_test(
        name = "source_sets_dep_without_java_info_fails_test",
        target_under_test = ":ss_files_dep_library",
        message = "provides no JavaInfo; a JVM consumer needs JVM deps",
    )
    _expect_failure_test(
        name = "source_sets_duplicate_fragment_fails_test",
        target_under_test = ":ss_module_name_library",
        message = "fragment names must be unique in a compilation, but '%sss_common' is both" % _NAMES,
    )

def source_sets_test_suite(name):
    _source_sets_contents()

    native.test_suite(
        name = name,
        tests = [
            ":source_sets_binary_test",
            ":source_sets_dep_without_java_info_fails_test",
            ":source_sets_duplicate_fragment_fails_test",
            ":source_sets_kapt_fails_test",
            ":source_sets_ksp_fails_test",
            ":source_sets_library_test",
            ":source_sets_none_test",
            ":source_sets_sourceless_library_test",
            ":source_sets_srcjar_fails_test",
            ":source_sets_test_test",
        ],
    )
