"""Analysis tests for the kmp_fragments of kt_jvm_library: the K2 fragments of the KotlinCompile action."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@rules_java//java:defs.bzl", "java_library", "java_plugin")
load("//kotlin:core.bzl", "kt_ksp_plugin")
load("//kotlin:jvm.bzl", "kt_jvm_library")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:fragment.bzl", "kt_kmp_fragment")

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

    # The sources of the fragments, in the order of the fragments: those of the library, the leaf,
    # last.
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
        "-Xfragments=" + ",".join(ctx.attr.fragments),
    ] + [
        "-Xfragment-sources=%s:%s" % (fragment, path_of.get(source))
        for fragment, source in fragment_sources
    ] + [
        "-Xfragment-refines=" + refinement
        for refinement in ctx.attr.refines
    ]
    passthrough = _values(argv, "--kotlin_passthrough_flags")
    start = passthrough.index("-Xmulti-platform")
    asserts.equals(env, expected, passthrough[start:start + len(expected)])
    asserts.equals(env, expected, [value for value in passthrough if _is_fragment_flag(value)])

    # The fragments have no deps: they compile against those of the library.
    for flag in ["--classpath", "--direct_dependencies"]:
        jars = [_basename(path) for path in _values(argv, flag)]
        for jar in ctx.attr.dep_jars:
            asserts.true(env, jar in jars, "the dep %s of the library should be in %s" % (jar, flag))

    return analysistest.end(env)

def _no_fragments_test_impl(ctx):
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
        # The basenames of the compile jars of the deps of the library.
        "dep_jars": attr.string_list(),
        # The basenames of the sources of each fragment.
        "fragment_sources": attr.string_list_dict(),
        # The fragment names, most shared first, then by name, the leaf last.
        "fragments": attr.string_list(),
        # The refinements, <fragment>:<refined fragment>, in the order of the flags.
        "refines": attr.string_list(),
    },
)
_no_fragments_test = analysistest.make(_no_fragments_test_impl)
_expect_failure_test = analysistest.make(
    _expect_failure_test_impl,
    attrs = {"message": attr.string()},
    expect_failure = True,
)

def _kmp_fragments_contents():
    for name, out, content in [
        ("kf_platform_kt", "Platform.kt", ["package kf", "", "expect fun platformName(): String"]),
        ("kf_greeting_kt", "Greeting.kt", ["package kf", "", "fun greeting(): String = \"Hello from \" + platformName()"]),
        ("kf_jvm_platform_kt", "Platform.jvm.kt", ["package kf", "", "actual fun platformName(): String = \"JVM\""]),
        ("kf_dep_java", "Dep.java", ["package kf;", "", "public class Dep {}"]),
        ("kf_processor_java", "Processor.java", ["package kf;", "", "public class Processor {}"]),
        ("kf_srcjar", "Gen.srcjar", [""]),
    ]:
        write_file(
            name = name,
            out = "kmp_fragments/" + out,
            content = content,
            tags = ["manual"],
        )

    java_library(
        name = "kf_java_dep",
        srcs = [":kf_dep_java"],
        tags = ["manual"],
    )

    # The expect declarations of every platform, and the sources the JVM shares with linux_x64,
    # which use them.
    kt_kmp_fragment(
        name = "kf_common",
        srcs = [":kf_platform_kt"],
        platforms = [
            "android",
            "jvm",
            "linux_x64",
        ],
        tags = ["manual"],
    )
    kt_kmp_fragment(
        name = "kf_jvm_native",
        srcs = [":kf_greeting_kt"],
        platforms = [
            "jvm",
            "linux_x64",
        ],
        refines = [":kf_common"],
        tags = ["manual"],
    )

    kt_jvm_library(
        name = "kf_library",
        srcs = [":kf_jvm_platform_kt"],
        kmp_fragments = [":kf_jvm_native"],
        tags = ["manual"],
    )

    # The actual declarations the JVM shares with Android: the JVM library has no srcs of its own,
    # and compiles the fragments against its deps.
    kt_kmp_fragment(
        name = "kf_jvm_android",
        srcs = [":kf_jvm_platform_kt"],
        platforms = [
            "android",
            "jvm",
        ],
        refines = [":kf_common"],
        tags = ["manual"],
    )
    kt_jvm_library(
        name = "kf_sourceless_library",
        kmp_fragments = [
            ":kf_jvm_android",
            ":kf_jvm_native",
        ],
        tags = ["manual"],
        deps = [":kf_java_dep"],
    )
    kt_jvm_library(
        name = "kf_free_library",
        srcs = [":kf_jvm_platform_kt"],
        tags = ["manual"],
    )

    # What a compilation with kmp_fragments rejects.
    kt_jvm_library(
        name = "kf_srcjar_library",
        srcs = [
            ":kf_jvm_platform_kt",
            ":kf_srcjar",
        ],
        kmp_fragments = [":kf_common"],
        tags = ["manual"],
    )
    java_plugin(
        name = "kf_kapt_processor",
        srcs = [":kf_processor_java"],
        processor_class = "kf.Processor",
        tags = ["manual"],
    )
    kt_jvm_library(
        name = "kf_kapt_library",
        srcs = [":kf_jvm_platform_kt"],
        kmp_fragments = [":kf_common"],
        plugins = [":kf_kapt_processor"],
        tags = ["manual"],
    )
    java_library(
        name = "kf_ksp_processor_lib",
        srcs = [":kf_processor_java"],
        tags = ["manual"],
    )
    kt_ksp_plugin(
        name = "kf_ksp_processor",
        processor_class = "kf.Processor",
        tags = ["manual"],
        deps = [":kf_ksp_processor_lib"],
    )
    kt_jvm_library(
        name = "kf_ksp_library",
        srcs = [":kf_jvm_platform_kt"],
        kmp_fragments = [":kf_common"],
        plugins = [":kf_ksp_processor"],
        tags = ["manual"],
    )

    # The srcs list a source of kf_common.
    kt_jvm_library(
        name = "kf_source_in_two_fragments_library",
        srcs = [":kf_platform_kt"],
        kmp_fragments = [":kf_common"],
        tags = ["manual"],
    )

    # macOS does not share kf_common, which jvm-macos_arm64 cannot refine.
    kt_kmp_fragment(
        name = "kf_not_superset",
        platforms = [
            "jvm",
            "macos_arm64",
        ],
        refines = [":kf_common"],
        tags = ["manual"],
    )
    kt_jvm_library(
        name = "kf_not_superset_library",
        srcs = [":kf_jvm_platform_kt"],
        kmp_fragments = [":kf_not_superset"],
        tags = ["manual"],
    )

    # Another fragment of the platforms of kf_common, with other sources.
    kt_kmp_fragment(
        name = "kf_common_twin",
        srcs = [":kf_greeting_kt"],
        platforms = [
            "android",
            "jvm",
            "linux_x64",
        ],
        tags = ["manual"],
    )
    kt_jvm_library(
        name = "kf_duplicate_fragment_library",
        srcs = [":kf_jvm_platform_kt"],
        kmp_fragments = [
            ":kf_common",
            ":kf_common_twin",
        ],
        tags = ["manual"],
    )

    _fragments_test(
        name = "kmp_fragments_library_test",
        target_under_test = ":kf_library",
        fragment_sources = {
            "android-jvm-linux_x64": ["Platform.kt"],
            "jvm": ["Platform.jvm.kt"],
            "jvm-linux_x64": ["Greeting.kt"],
        },
        fragments = ["android-jvm-linux_x64", "jvm-linux_x64", "jvm"],
        refines = ["jvm-linux_x64:android-jvm-linux_x64", "jvm:jvm-linux_x64"],
    )
    _fragments_test(
        name = "kmp_fragments_sourceless_library_test",
        target_under_test = ":kf_sourceless_library",
        dep_jars = ["libkf_java_dep-hjar.jar"],
        fragment_sources = {
            "android-jvm": ["Platform.jvm.kt"],
            "android-jvm-linux_x64": ["Platform.kt"],
            "jvm-linux_x64": ["Greeting.kt"],
        },
        fragments = ["android-jvm-linux_x64", "android-jvm", "jvm-linux_x64", "jvm"],
        refines = [
            "android-jvm:android-jvm-linux_x64",
            "jvm-linux_x64:android-jvm-linux_x64",
            "jvm:android-jvm",
            "jvm:jvm-linux_x64",
        ],
    )
    _no_fragments_test(
        name = "kmp_fragments_none_test",
        target_under_test = ":kf_free_library",
    )
    _expect_failure_test(
        name = "kmp_fragments_srcjar_fails_test",
        target_under_test = ":kf_srcjar_library",
        message = "kmp_fragments cannot be combined with .srcjar sources",
    )
    _expect_failure_test(
        name = "kmp_fragments_kapt_fails_test",
        target_under_test = ":kf_kapt_library",
        message = "kmp_fragments cannot be combined with kapt",
    )
    _expect_failure_test(
        name = "kmp_fragments_ksp_fails_test",
        target_under_test = ":kf_ksp_library",
        message = "kmp_fragments cannot be combined with the KSP compiler plugin",
    )
    _expect_failure_test(
        name = "kmp_fragments_source_in_two_fragments_fails_test",
        target_under_test = ":kf_source_in_two_fragments_library",
        message = "is in both fragment 'android-jvm-linux_x64' and 'jvm'",
    )
    _expect_failure_test(
        name = "kmp_fragments_not_superset_fails_test",
        target_under_test = ":kf_not_superset_library",
        message = "the fragment 'jvm-macos_arm64' cannot refine 'android-jvm-linux_x64', which is not shared by more platforms, including its own",
    )
    _expect_failure_test(
        name = "kmp_fragments_duplicate_fragment_fails_test",
        target_under_test = ":kf_duplicate_fragment_library",
        message = "fragment names must be unique in a compilation, but two fragments are named 'android-jvm-linux_x64'",
    )

def kmp_fragments_test_suite(name):
    _kmp_fragments_contents()

    native.test_suite(
        name = name,
        tests = [
            ":kmp_fragments_duplicate_fragment_fails_test",
            ":kmp_fragments_kapt_fails_test",
            ":kmp_fragments_ksp_fails_test",
            ":kmp_fragments_library_test",
            ":kmp_fragments_none_test",
            ":kmp_fragments_not_superset_fails_test",
            ":kmp_fragments_source_in_two_fragments_fails_test",
            ":kmp_fragments_sourceless_library_test",
            ":kmp_fragments_srcjar_fails_test",
        ],
    )
