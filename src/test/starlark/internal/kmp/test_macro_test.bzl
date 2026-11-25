"""Tests for kt_multiplatform_test: the test fragments it derives, the tests it declares, their friends and what the JVM and Android tests run.

The tests are those of `mpp`, the library of multiplatform_test.bzl, and of an Android library.
The native tests use the fake toolchains of //src/test/starlark/internal/native (see common.bzl
there).
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("@rules_java//java:defs.bzl", "JavaInfo", "java_library")
load("//kotlin:kmp.bzl", "kt_multiplatform_library", "kt_multiplatform_test")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:declaration.bzl", "TEST_QUALIFIED_ATTRS", "parse_declaration")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:derive.bzl", "derive_fragments")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:test.bzl", "platform_library", "suite_attrs", "tests_error")
load(
    "//src/test/starlark/internal/native:common.bzl",
    "argument_after",
    "for_target",
    "launcher_values",
    "libraries",
    "not_on_windows",
    "prefixed",
    "single_action",
    "tool_arguments",
)
load(":multiplatform_test.bzl", "fragment_test", "fragments_graph_unix_test")

_PACKAGE = "src/test/starlark/internal/kmp"
_SUITE_CLASS = "io.bazel.kotlin.kmp.MultiplatformTestSuite"
_TEST_RUNNER = "com.google.testing.junit.runner.BazelTestRunner"

# The library the alias //src/main/kotlin:kmp_test_suite is in this workspace.
_SUITE = str(Label("//src/main/kotlin/io/bazel/kotlin/kmp:kmp_test_suite"))

_OPT_IN = "-opt-in=kotlin.ExperimentalStdlibApi"

# The attributes of the Android library and of its test.
_ANDROID = dict(
    custom_package = "kmp.test",
    manifest = "testdata/AndroidManifest.xml",
)

def _label(name):
    return str(Label("//%s:%s" % (_PACKAGE, name)))

def _basename(path):
    return path.rpartition("/")[2]

def _labels(targets):
    return [str(target.label) for target in targets]

_TestAttrsInfo = provider(
    doc = "The attributes of a test of a platform, or of the test_suite, that the macro sets.",
    fields = {
        "associates": "list of string: the labels of its associates.",
        "deps": "list of string: the labels of its deps.",
        "jvm_flags": "list of string: its jvm_flags, those of a JVM test.",
        "kmp_fragments": "list of string: the labels of its kmp_fragments.",
        "runtime_deps": "list of string: the labels of its runtime_deps, those of a JVM test.",
        "size": "string: its size.",
        "tags": "list of string: its tags.",
        "test_class": "string: its test_class, that of a JVM test.",
        "tests": "list of string: the labels of its tests, those of a test_suite.",
    },
)

def _test_attrs_aspect_impl(_target, ctx):
    attr = ctx.rule.attr
    return [_TestAttrsInfo(
        associates = _labels(getattr(attr, "associates", [])),
        deps = _labels(getattr(attr, "deps", [])),
        jvm_flags = getattr(attr, "jvm_flags", []),
        kmp_fragments = _labels(getattr(attr, "kmp_fragments", [])),
        runtime_deps = _labels(getattr(attr, "runtime_deps", [])),
        size = getattr(attr, "size", ""),
        tags = attr.tags,
        test_class = getattr(attr, "test_class", ""),
        tests = _labels(getattr(attr, "tests", [])),
    )]

_test_attrs_aspect = aspect(implementation = _test_attrs_aspect_impl)

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

def _fragment_sources(args):
    """The -Xfragment-sources of a compilation, as `<fragment>:<basename>`."""
    return [
        "%s:%s" % (fragment, _basename(path))
        for fragment, _, path in [source.partition(":") for source in prefixed(args, "-Xfragment-sources=")]
    ]

def _assert_fragments(env, args, attr):
    asserts.equals(env, [",".join(attr.fragments)], prefixed(args, "-Xfragments="))
    asserts.equals(env, attr.sources, _fragment_sources(args))
    asserts.equals(env, attr.refines, prefixed(args, "-Xfragment-refines="))

def _jvm_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The JVM or Android test compiles the test fragments of the qualifiers covering its platform,
    # and its own sources as the leaf, named after the platform, with the library of the platform
    # as friend: they see its internal declarations.
    target = analysistest.target_under_test(env)
    argv = single_action(env, "KotlinCompile").argv
    _assert_fragments(env, argv, ctx.attr)
    asserts.equals(env, [ctx.attr.friend_jar], [_basename(path) for path in _values(argv, "--kotlin_friend_paths")])

    info = target[_TestAttrsInfo]
    asserts.equals(env, [_label(ctx.attr.associate)], info.associates)
    asserts.equals(env, [_label(dep) for dep in ctx.attr.deps], info.deps)
    asserts.equals(env, [_label(fragment) for fragment in ctx.attr.kmp_fragments], info.kmp_fragments)
    asserts.equals(env, ctx.attr.test_size, info.size)
    asserts.equals(env, ["manual"], info.tags)

    # Without a test class of its own, the test runs the suite over its own jar, which the system
    # property names by its path from the root of the repository.
    jar = target[JavaInfo].runtime_output_jars[0]
    asserts.equals(env, target.label.name + ".jar", jar.basename)
    asserts.equals(env, ctx.attr.test_class, info.test_class)
    if ctx.attr.suite:
        asserts.equals(env, ["-Drules_kotlin.kmp.test_jar=" + jar.short_path] + ctx.attr.jvm_flags, info.jvm_flags)
        asserts.equals(env, [_label(dep) for dep in ctx.attr.runtime_deps] + [_SUITE], info.runtime_deps)
    else:
        asserts.equals(env, ctx.attr.jvm_flags, info.jvm_flags)
        asserts.equals(env, [_label(dep) for dep in ctx.attr.runtime_deps], info.runtime_deps)

    return analysistest.end(env)

def _native_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The native test compiles, for the konan target, the test fragments of the qualifiers covering
    # it and its own sources as the leaf, which may be empty, into the klib its link includes.
    compile = single_action(env, "KotlinNativeKlibCompile")
    tool = tool_arguments(compile.argv)
    _assert_fragments(env, tool, ctx.attr)
    asserts.equals(env, ctx.attr.srcs, [_basename(path) for path in launcher_values(compile.argv, "--source")])
    asserts.true(env, _OPT_IN in tool, str(tool))

    # The native library is the friend, by the path of its -l argument, and a dep of the link.
    friend = [path for path in libraries(tool) if _basename(path) == ctx.attr.friend_klib]
    asserts.equals(env, 1, len(friend), str(libraries(tool)))
    asserts.equals(env, friend, [argument_after(tool, "-friend-modules")])
    link_tool = tool_arguments(single_action(env, "KotlinNativeLink").argv)
    asserts.true(env, "-generate-test-runner" in link_tool, str(link_tool))
    asserts.equals(env, ["__EXECROOT__/" + compile.outputs.to_list()[0].path], prefixed(link_tool, "-Xinclude="))
    asserts.true(env, ctx.attr.friend_klib in [_basename(path) for path in libraries(link_tool)], str(link_tool))

    info = analysistest.target_under_test(env)[_TestAttrsInfo]
    asserts.equals(env, [_label(ctx.attr.associate)], info.associates)
    asserts.equals(env, [_label(fragment) for fragment in ctx.attr.kmp_fragments], info.kmp_fragments)
    asserts.equals(env, ctx.attr.test_size, info.size)
    asserts.equals(env, ["manual"], info.tags)

    return analysistest.end(env)

def _test_suite_test_impl(ctx):
    env = analysistest.begin(ctx)

    info = analysistest.target_under_test(env)[_TestAttrsInfo]
    asserts.equals(env, [_label(test) for test in ctx.attr.tests], info.tests)
    asserts.equals(env, ["manual"], info.tags)

    return analysistest.end(env)

_FRAGMENT_FLAGS_ATTRS = {
    "associate": attr.string(doc = "the name of the expected associate, in the package"),
    "fragments": attr.string_list(doc = "the expected -Xfragments, in order"),
    "kmp_fragments": attr.string_list(doc = "the names of the expected kmp_fragments, in the package, in order"),
    "refines": attr.string_list(doc = "the expected -Xfragment-refines, `<fragment>:<refined>`, in order"),
    "sources": attr.string_list(doc = "the expected -Xfragment-sources, `<fragment>:<basename>`, in order"),
    "test_size": attr.string(doc = "the expected size of the test"),
}
_JVM_ATTRS = dict(_FRAGMENT_FLAGS_ATTRS, **{
    "deps": attr.string_list(doc = "the names of the expected deps, in the package, in order"),
    "friend_jar": attr.string(doc = "the basename of the jar of the associate the compilation gets as friend"),
    "jvm_flags": attr.string_list(doc = "the expected jvm_flags, without the one of the suite"),
    "runtime_deps": attr.string_list(doc = "the names of the expected runtime_deps, in the package, without the suite"),
    "suite": attr.bool(doc = "whether the test runs the suite"),
    "test_class": attr.string(doc = "the expected test_class"),
})
_NATIVE_ATTRS = dict(_FRAGMENT_FLAGS_ATTRS, **{
    "friend_klib": attr.string(doc = "the basename of the klib of the associate"),
    "srcs": attr.string_list(doc = "the basenames of the expected sources, in order"),
})

jvm_test = analysistest.make(
    _jvm_test_impl,
    attrs = _JVM_ATTRS,
    extra_target_under_test_aspects = [_test_attrs_aspect],
)
native_linux_arm64_test = analysistest.make(
    _native_test_impl,
    attrs = _NATIVE_ATTRS,
    config_settings = for_target("linux_arm64"),
    extra_target_under_test_aspects = [_test_attrs_aspect],
)
native_ios_simulator_arm64_test = analysistest.make(
    _native_test_impl,
    attrs = _NATIVE_ATTRS,
    config_settings = for_target("ios_simulator_arm64"),
    extra_target_under_test_aspects = [_test_attrs_aspect],
)

# A rule that depends on a test_suite is incompatible with the platforms one of its tests is: the
# test builds for a konan target of the native test.
test_suite_test = analysistest.make(
    _test_suite_test_impl,
    attrs = {"tests": attr.string_list(doc = "the names of the expected tests, in the package, in order")},
    config_settings = for_target("linux_arm64"),
    extra_target_under_test_aspects = [_test_attrs_aspect],
)

def _suite_attrs_test(ctx):
    env = unittest.begin(ctx)

    # Bazel convention: a JVM test names the class to run. A test of several fragments has no such
    # class, so it runs the suite over its own jar, <package>/<name>.jar, unless it names one.
    suite = Label("//src/main/kotlin:kmp_test_suite")
    asserts.equals(
        env,
        {
            "jvm_flags": ["-Drules_kotlin.kmp.test_jar=shared/tests/shared_test_jvm.jar"],
            "runtime_deps": [suite],
            "test_class": _SUITE_CLASS,
        },
        suite_attrs("shared/tests", "shared_test_jvm", {}),
    )
    asserts.equals(
        env,
        ["-Drules_kotlin.kmp.test_jar=shared_test_jvm.jar"],
        suite_attrs("", "shared_test_jvm", {})["jvm_flags"],
    )

    # The attributes of the test stay: its flags follow the property, the suite its runtime deps.
    asserts.equals(
        env,
        {
            "jvm_flags": ["-Drules_kotlin.kmp.test_jar=shared/shared_test_android.jar", "-Xmx1g"],
            "main_class": _TEST_RUNNER,
            "manifest": "AndroidManifest.xml",
            "runtime_deps": [":robolectric", suite],
            "test_class": _SUITE_CLASS,
        },
        suite_attrs(
            "shared",
            "shared_test_android",
            {
                "jvm_flags": ["-Xmx1g"],
                "main_class": _TEST_RUNNER,
                "manifest": "AndroidManifest.xml",
                "runtime_deps": [":robolectric"],
            },
        ),
    )

    # A test class, or a main class that reads none, is what the test runs.
    for explicit in [
        {"jvm_flags": ["-Xmx1g"], "test_class": "shared.GreetingTest"},
        {"main_class": "shared.TestMain", "runtime_deps": [":runner"]},
    ]:
        asserts.equals(env, explicit, suite_attrs("shared", "shared_test_jvm", explicit))

    return unittest.end(env)

def _platform_library_test(ctx):
    env = unittest.begin(ctx)

    # The libraries of a kt_multiplatform_library are next to its alias, whatever its package.
    asserts.equals(env, Label("//shared:shared_jvm"), platform_library(Label("//shared"), "jvm"))
    asserts.equals(env, Label("//shared/core:lib_native"), platform_library(Label("//shared/core:lib"), "native"))
    asserts.equals(env, Label("@platforms//os:linux_android"), platform_library(Label("@platforms//os:linux"), "android"))

    return unittest.end(env)

def _tests_error(platforms, settings = {}, srcs = [], **kwargs):
    declaration = parse_declaration(platforms, {"srcs": srcs}, settings, kwargs, attrs = TEST_QUALIFIED_ATTRS, kind = "test")
    return tests_error(declaration, derive_fragments(declaration.lists["srcs"], declaration.qualifiers))

def _tests_error_test(ctx):
    env = unittest.begin(ctx)

    # The test sources of every platform are enough for each of them, and so are those of a group.
    asserts.equals(env, None, _tests_error(["jvm", "linux_x64"], srcs = ["GreetingTest.kt"]))
    asserts.equals(
        env,
        None,
        _tests_error(["jvm", "linux_x64", "linux_arm64"], srcs_jvm = ["JvmTest.kt"], srcs_linux = ["LinuxTest.kt"]),
    )

    # A test without sources would run nothing, or, on the JVM, fail when it runs.
    asserts.equals(
        env,
        "linux_x64 has no sources: list some in the srcs of the macro, srcs_native, srcs_linux or srcs_linux_x64, " +
        "or remove linux_x64 from platforms",
        _tests_error(["jvm", "linux_x64"], srcs_jvm = ["JvmTest.kt"]),
    )
    asserts.equals(
        env,
        "jvm has no sources: list some in the srcs of the macro or srcs_jvm, or remove jvm from platforms",
        _tests_error(["jvm"]),
    )

    # The macro sets the associates.
    for node in ["jvm", "native"]:
        asserts.equals(
            env,
            node + " sets associates, which the macro sets to the library of the platform",
            _tests_error(["jvm", "linux_x64"], settings = {node: dict(associates = [":lib"])}, srcs = ["GreetingTest.kt"]),
        )

    return unittest.end(env)

suite_attrs_test = unittest.make(_suite_attrs_test)
platform_library_test = unittest.make(_platform_library_test)
tests_error_test = unittest.make(_tests_error_test)

def test_macro_test_suite(name):
    """Declares multiplatform tests of the library `mpp` and the tests of what kt_multiplatform_test declares.

    Args:
      name: the name of the generated test_suite target.
    """
    for library in ["tm_junit", "tm_runtime"]:
        java_library(
            name = library,
            srcs = ["testdata/PlatformTypeLib.java"],
            tags = ["manual"],
        )

    # The JVM and the Linux target compile the test sources of an alias; the konan targets those of
    # native, and the iOS simulator has no test source of its own.
    kt_multiplatform_test(
        name = "mpp_test",
        size = "small",
        aliases = {"jvm_linux": [
            "jvm",
            "linux_arm64",
        ]},
        library = ":mpp",
        platforms = [
            "jvm",
            "linux_arm64",
            "ios_simulator_arm64",
        ],
        srcs = ["testdata/test/GreetingTest.kt"],
        deps_jvm = [":tm_junit"],
        jvm = dict(
            jvm_flags = ["-Xmx1g"],
            runtime_deps = [":tm_runtime"],
        ),
        native = dict(opts = [_OPT_IN]),
        srcs_jvm = ["testdata/test/Expected.jvm.kt"],
        srcs_jvm_linux = ["testdata/test/JvmLinuxTest.kt"],
        srcs_native = ["testdata/test/Expected.native.kt"],
        tags = ["manual"],
    )

    # A test of the JVM alone that names its test class runs it, without the suite.
    kt_multiplatform_test(
        name = "mpp_explicit_test",
        library = ":mpp",
        platforms = ["jvm"],
        srcs = ["testdata/test/GreetingTest.kt"],
        jvm = dict(test_class = "kmp.test.GreetingTest"),
        srcs_jvm = ["testdata/test/Expected.jvm.kt"],
        tags = ["manual"],
    )

    # The test of Android is a kt_android_local_test of the Android library.
    kt_multiplatform_library(
        name = "tm_android",
        srcs = [
            "testdata/Greeting.kt",
            "testdata/Platform.kt",
        ],
        android = _ANDROID,
        platforms = ["android"],
        srcs_android = ["testdata/Platform.jvm.kt"],
        tags = ["manual"],
    )
    kt_multiplatform_test(
        name = "tm_android_test",
        srcs = ["testdata/test/GreetingTest.kt"],
        android = _ANDROID,
        library = ":tm_android",
        platforms = ["android"],
        srcs_android = ["testdata/test/Expected.jvm.kt"],
        tags = ["manual"],
    )

    jvm_test(
        name = "test_macro_jvm_test",
        target_under_test = ":mpp_test_jvm",
        associate = "mpp_jvm",
        deps = ["tm_junit"],
        fragments = [
            "common",
            "jvm_linux",
            "jvm",
        ],
        friend_jar = "mpp_jvm.abi.jar",
        jvm_flags = ["-Xmx1g"],
        kmp_fragments = ["mpp_test_fragment_jvm_linux"],
        refines = [
            "jvm_linux:common",
            "jvm:jvm_linux",
        ],
        runtime_deps = ["tm_runtime"],
        sources = [
            "common:GreetingTest.kt",
            "jvm_linux:JvmLinuxTest.kt",
            "jvm:Expected.jvm.kt",
        ],
        suite = True,
        test_class = _SUITE_CLASS,
        test_size = "small",
    )
    jvm_test(
        name = "test_macro_explicit_test_class_test",
        target_under_test = ":mpp_explicit_test_jvm",
        associate = "mpp_jvm",
        fragments = [
            "common",
            "jvm",
        ],
        friend_jar = "mpp_jvm.abi.jar",
        kmp_fragments = ["mpp_explicit_test_fragment_common"],
        refines = ["jvm:common"],
        sources = [
            "common:GreetingTest.kt",
            "jvm:Expected.jvm.kt",
        ],
        suite = False,
        test_class = "kmp.test.GreetingTest",
        test_size = "medium",
    )

    # The Android SDK of the workspace is not known to resolve on Windows.
    jvm_test(
        name = "test_macro_android_test",
        target_under_test = ":tm_android_test_android",
        associate = "tm_android_android",
        fragments = [
            "common",
            "android",
        ],
        friend_jar = "tm_android_android.abi.jar",
        kmp_fragments = ["tm_android_test_fragment_common"],
        refines = ["android:common"],
        sources = [
            "common:GreetingTest.kt",
            "android:Expected.jvm.kt",
        ],
        suite = True,
        target_compatible_with = not_on_windows(),
        test_class = _SUITE_CLASS,
        test_size = "medium",
    )

    # The leaf of the Linux target refines the fragments of the alias and of native, and is empty.
    native_linux_arm64_test(
        name = "test_macro_native_linux_test",
        target_under_test = ":mpp_test_native",
        associate = "mpp_native",
        fragments = [
            "common",
            "jvm_linux",
            "native",
            "linux_arm64",
        ],
        friend_klib = "mpp_native.klib",
        kmp_fragments = [
            "mpp_test_fragment_jvm_linux",
            "mpp_test_fragment_native",
        ],
        refines = [
            "jvm_linux:common",
            "native:common",
            "linux_arm64:jvm_linux",
            "linux_arm64:native",
        ],
        sources = [
            "common:GreetingTest.kt",
            "jvm_linux:JvmLinuxTest.kt",
            "native:Expected.native.kt",
        ],
        srcs = [
            "GreetingTest.kt",
            "JvmLinuxTest.kt",
            "Expected.native.kt",
        ],
        target_compatible_with = not_on_windows(),
        test_size = "small",
    )
    native_ios_simulator_arm64_test(
        name = "test_macro_native_ios_test",
        target_under_test = ":mpp_test_native",
        associate = "mpp_native",
        fragments = [
            "common",
            "native",
            "ios_simulator_arm64",
        ],
        friend_klib = "mpp_native.klib",
        kmp_fragments = ["mpp_test_fragment_native"],
        refines = [
            "native:common",
            "ios_simulator_arm64:native",
        ],
        sources = [
            "common:GreetingTest.kt",
            "native:Expected.native.kt",
        ],
        srcs = [
            "GreetingTest.kt",
            "Expected.native.kt",
        ],
        target_compatible_with = not_on_windows(),
        test_size = "small",
    )
    test_suite_test(
        name = "test_macro_test_suite_test",
        target_under_test = ":mpp_test",
        target_compatible_with = not_on_windows(),
        tests = [
            "mpp_test_jvm",
            "mpp_test_native",
        ],
    )
    fragment_test(
        name = "test_macro_alias_fragment_test",
        target_under_test = ":mpp_test_fragment_jvm_linux",
        fragment = "jvm_linux",
        refines = ["common"],
        srcs = ["JvmLinuxTest.kt"],
        transitive = [
            "common",
            "jvm_linux",
        ],
    )
    fragments_graph_unix_test(
        name = "test_macro_fragments_graph_test",
        target_under_test = ":mpp_test.fragments",
        graph = """\
fragment common
  platforms: jvm, linux_arm64, ios_simulator_arm64
  srcs:
    testdata/test/GreetingTest.kt
fragment jvm_linux
  refines: common
  platforms: jvm, linux_arm64
  srcs:
    testdata/test/JvmLinuxTest.kt
fragment native
  refines: common
  platforms: linux_arm64, ios_simulator_arm64
  srcs:
    testdata/test/Expected.native.kt
leaf ios_simulator_arm64
  refines: native
leaf jvm
  refines: jvm_linux
  srcs:
    testdata/test/Expected.jvm.kt
leaf linux_arm64
  refines: jvm_linux, native
""",
        header = "#!/usr/bin/env sh\n",
        launcher = "mpp_test.fragments.sh",
    )
    unittest.suite(
        "test_macro_helpers",
        suite_attrs_test,
        platform_library_test,
        tests_error_test,
    )

    native.test_suite(
        name = name,
        tests = [
            ":test_macro_alias_fragment_test",
            ":test_macro_android_test",
            ":test_macro_explicit_test_class_test",
            ":test_macro_fragments_graph_test",
            ":test_macro_helpers",
            ":test_macro_jvm_test",
            ":test_macro_native_ios_test",
            ":test_macro_native_linux_test",
            ":test_macro_test_suite_test",
        ],
    )
