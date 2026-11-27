"""Tests for kt_multiplatform_test: the test fragments it derives, the tests it declares, their friends and what the JVM and Android tests run.

The tests are those of `mpp`, the library of multiplatform_test.bzl, and of an Android library.
The native tests use the fake toolchains of //src/test/starlark/internal/native (see common.bzl
there). The iOS test is a test rule of this file, in the place of rules_apple's ios_unit_test,
which records how the macro calls it: the tests of what the macro declares compare, when they are
analysed, values the macro computed when the package was loaded, as no single platform is
compatible with every test of a test_suite.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("@rules_java//java:defs.bzl", "JavaInfo", "java_library")
load("//kotlin:kmp.bzl", "kt_multiplatform_library", "kt_multiplatform_test")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:declaration.bzl", "TEST_NODES", "TEST_QUALIFIED_ATTRS", "parse_declaration")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:derive.bzl", "derive_fragments")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:test.bzl", "ios_test_konan_targets", "platform_library", "suite_attrs", "tests_error")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/native:targets.bzl", "KONAN_TARGETS")
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
    "with_fake_cc_toolchain",
)
load(":multiplatform_test.bzl", "fragment_test", "fragments_graph_unix_test")

_PACKAGE = "src/test/starlark/internal/kmp"
_SUITE_CLASS = "io.bazel.kotlin.kmp.MultiplatformTestSuite"
_TEST_RUNNER = "com.google.testing.junit.runner.BazelTestRunner"

# The library the alias //src/main/kotlin:kmp_test_suite is in this workspace.
_SUITE = str(Label("//src/main/kotlin/io/bazel/kotlin/kmp:kmp_test_suite"))

_OPT_IN = "-opt-in=kotlin.ExperimentalStdlibApi"

# The deployment target of the iOS tests.
_IOS_VERSION = "15.0"

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
        "minimum_os_version": "string: its minimum_os_version, that of an iOS test.",
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
        minimum_os_version = getattr(attr, "minimum_os_version", ""),
        runtime_deps = _labels(getattr(attr, "runtime_deps", [])),
        size = getattr(attr, "size", ""),
        tags = attr.tags,
        test_class = getattr(attr, "test_class", ""),
        tests = _labels(getattr(attr, "tests", [])),
    )]

_test_attrs_aspect = aspect(implementation = _test_attrs_aspect_impl)

def _fake_ios_unit_test_impl(ctx):
    executable = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(executable, "", is_executable = True)
    return [DefaultInfo(executable = executable)]

# What the macro needs of rules_apple's ios_unit_test: a test that takes the library of the Kotlin
# tests and the other libraries of its bundle in its deps, a deployment target, and whether its
# runner collects coverage, which it does by default. Like it, the rule has no transition; unlike
# it, it builds its deps for its own platform, which an analysis test sets to that of the iOS
# simulator.
_fake_ios_unit_test = rule(
    implementation = _fake_ios_unit_test_impl,
    attrs = {
        "collect_code_coverage": attr.bool(default = True),
        "deps": attr.label_list(providers = [CcInfo]),
        "minimum_os_version": attr.string(mandatory = True),
    },
    test = True,
)

def _fake_objc_library_impl(_ctx):
    return [CcInfo()]

# What the `deps` of `ios` are, in the place of an objc_library: a library that a test bundle links.
_fake_objc_library = rule(implementation = _fake_objc_library_impl)

def _recording_ios_test_rule(calls):
    """An `ios_test_rule` that declares the fake test and adds the arguments of each call to `calls`, by name."""

    def _ios_test_rule(name, **kwargs):
        calls[name] = kwargs
        _fake_ios_unit_test(name = name, **kwargs)

    return _ios_test_rule

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
    asserts.equals(env, [",".join(attr.fragments)] if attr.fragments else [], prefixed(args, "-Xfragments="))
    asserts.equals(env, attr.sources, _fragment_sources(args))
    asserts.equals(env, attr.refines, prefixed(args, "-Xfragment-refines="))
    asserts.equals(env, bool(attr.fragments), "-Xmulti-platform" in args, str(args))

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
    asserts.equals(env, ctx.attr.produce, argument_after(link_tool, "-produce"))
    asserts.true(env, "-generate-test-runner" in link_tool, str(link_tool))
    asserts.equals(env, ["__EXECROOT__/" + compile.outputs.to_list()[0].path], prefixed(link_tool, "-Xinclude="))
    asserts.true(env, ctx.attr.friend_klib in [_basename(path) for path in libraries(link_tool)], str(link_tool))

    target = analysistest.target_under_test(env)
    info = target[_TestAttrsInfo]
    asserts.equals(env, [_label(ctx.attr.associate)], info.associates)
    asserts.equals(env, [_label(fragment) for fragment in ctx.attr.kmp_fragments], info.kmp_fragments)
    asserts.equals(env, ctx.attr.test_size, info.size)
    asserts.equals(env, ["manual"], info.tags)

    # The library of the iOS tests is what a test bundle links.
    asserts.equals(env, ctx.attr.produce == "static", CcInfo in target)

    return analysistest.end(env)

def _ios_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The iOS test is the rule the macro is given, with the library of the Kotlin tests and then
    # the deps of `ios` as its deps, the other attributes of `ios` and those of every test.
    info = analysistest.target_under_test(env)[_TestAttrsInfo]
    asserts.equals(env, [_label(dep) for dep in ctx.attr.deps], info.deps)
    asserts.equals(env, ctx.attr.minimum_os_version, info.minimum_os_version)
    asserts.equals(env, ctx.attr.test_size, info.size)
    asserts.equals(env, ["manual"], info.tags)

    return analysistest.end(env)

def _declared_test(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, ctx.attr.expected, ctx.attr.actual)

    return unittest.end(env)

_FRAGMENT_FLAGS_ATTRS = {
    "associate": attr.string(doc = "the name of the expected associate, in the package"),
    "fragments": attr.string_list(doc = "the expected -Xfragments, in order; none for no fragment flags"),
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
    "produce": attr.string(doc = "what the link produces", default = "program"),
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

# The library of the iOS tests compiles its XCTest case with the C++ toolchain.
_IOS_SIMULATOR = with_fake_cc_toolchain(for_target("ios_simulator_arm64"))
native_ios_simulator_arm64_test = analysistest.make(
    _native_test_impl,
    attrs = _NATIVE_ATTRS,
    config_settings = _IOS_SIMULATOR,
    extra_target_under_test_aspects = [_test_attrs_aspect],
)
ios_test = analysistest.make(
    _ios_test_impl,
    attrs = {
        "deps": attr.string_list(doc = "the names of the expected deps, in the package, in order"),
        "minimum_os_version": attr.string(doc = "the expected minimum_os_version"),
        "test_size": attr.string(doc = "the expected size of the test"),
    },
    config_settings = _IOS_SIMULATOR,
    extra_target_under_test_aspects = [_test_attrs_aspect],
)

# Compares what the macro declared, read when the package is loaded: the tests of a test_suite and
# their compatibility are those of several platforms, which no analysis test builds together.
declared_test = unittest.make(
    _declared_test,
    attrs = {
        "actual": attr.string_list(doc = "what the macro declared"),
        "expected": attr.string_list(doc = "what it should declare"),
    },
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

def _tests_error(platforms, settings = {}, srcs = [], ios_test_rule = None, **kwargs):
    declaration = parse_declaration(
        platforms,
        {"srcs": srcs},
        settings,
        kwargs,
        attrs = TEST_QUALIFIED_ATTRS,
        nodes = TEST_NODES,
        kind = "test",
    )
    return tests_error(declaration, derive_fragments(declaration.lists["srcs"], declaration.qualifiers), ios_test_rule)

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

def _ios_tests_error(platforms, ios, ios_test_rule = _fake_ios_unit_test, **settings):
    return _tests_error(
        platforms,
        settings = dict(settings, ios = ios),
        srcs = ["GreetingTest.kt"],
        ios_test_rule = ios_test_rule,
    )

def _ios_tests_error_test(ctx):
    env = unittest.begin(ctx)

    simulator = ["jvm", "ios_simulator_arm64"]
    version = dict(minimum_os_version = _IOS_VERSION)

    # Without iOS targets, the macro declares no iOS test: a rule for it is unused, so a wrapper of
    # the macro can always pass one. Attributes of the test are an error of the declaration.
    for ios in [None, {}]:
        asserts.equals(env, None, _ios_tests_error(["jvm", "macos_arm64"], ios))
        asserts.equals(env, None, _ios_tests_error(["jvm", "macos_arm64"], ios, ios_test_rule = None))

    # With iOS targets, the macro needs the rule that runs their tests, whatever `ios` sets.
    for ios in [None, version, dict(deps = [":bundled"])]:
        asserts.equals(
            env,
            "platforms lists ios_simulator_arm64, whose tests need ios_test_rule: pass the ios_unit_test of rules_apple, " +
            "loaded from @rules_apple//apple:ios.bzl, or remove ios_simulator_arm64 from platforms",
            _ios_tests_error(simulator, ios, ios_test_rule = None),
        )
    asserts.equals(
        env,
        "platforms lists ios_arm64 and ios_simulator_arm64, whose tests need ios_test_rule: pass the ios_unit_test of " +
        "rules_apple, loaded from @rules_apple//apple:ios.bzl, or remove ios_arm64 and ios_simulator_arm64 from platforms",
        _ios_tests_error(["ios_simulator_arm64", "ios_arm64"], version, ios_test_rule = None),
    )

    # Then the deployment target, which only the caller knows, before any other attribute.
    for ios in [None, {}, dict(runner = ":runner"), dict(deps = [":bundled"]), dict(minimum_os_version = "")]:
        asserts.equals(
            env,
            "platforms lists ios_simulator_arm64, whose test needs a deployment target, which the macro has no default " +
            "for: pass it as ios = dict(minimum_os_version = ...), e.g. \"15.0\"",
            _ios_tests_error(simulator, ios),
        )

    # Then what the macro sets, the associate of the library of the Kotlin tests, which is the
    # native library, before the deps.
    for deps in [[":bundled"], ":bundled"]:
        asserts.equals(
            env,
            "ios sets associates, which the macro sets to the library of the platform",
            _ios_tests_error(simulator, dict(version, associates = [":lib"], deps = deps)),
        )

    # The deps of `ios` are the other libraries of the test bundle, which the macro lists after
    # the library of the Kotlin tests: a list or a select, and nothing else.
    bundled = select({"//conditions:default": [":bundled"]})
    for deps in [[], [":bundled"], bundled, [":other"] + bundled]:
        asserts.equals(env, None, _ios_tests_error(simulator, dict(version, deps = deps)))
    for deps, kind in [(":bundled", "string"), ({":bundled": True}, "dict"), (None, "NoneType")]:
        asserts.equals(
            env,
            "the deps of ios must be a list of labels, not a %s: they are the other libraries that the test bundle " % kind +
            "links, e.g. an objc_library; the deps of the Kotlin tests are deps_ios of the macro",
            _ios_tests_error(simulator, dict(version, deps = deps)),
        )

    # With the rule and the deployment target, the macro declares the iOS test, of any other
    # attribute of its rule.
    for ios in [version, dict(version, env = {"KEY": "value"}, runner = ":runner")]:
        asserts.equals(env, None, _ios_tests_error(simulator, ios))
        asserts.equals(env, None, _ios_tests_error(["ios_arm64", "ios_simulator_arm64"], ios))

    # Without a konan target other than those of iOS, the macro declares no native test: an
    # attribute of `native` that the library of the iOS tests does not take would go nowhere.
    library_attrs = dict(link_opts = ["-opt"], module_name = "tests", opts = ["-opt-in=kotlin.ExperimentalStdlibApi"])
    native_test_attrs = dict(args = ["--ktest_logger=SIMPLE"], data = [":data"])
    asserts.equals(
        env,
        "native sets args and data, attributes of the native test, but platforms lists no konan target other than " +
        "those of iOS, whose tests take only the link_opts, module_name and opts of native: remove args and data from " +
        "native, or add a konan target that has a native test, e.g. macos_arm64; the attributes of the iOS test are " +
        "those of ios",
        _ios_tests_error(simulator, version, native = dict(library_attrs, **native_test_attrs)),
    )
    asserts.equals(
        env,
        "native sets target_compatible_with, an attribute of the native test, but platforms lists no konan target other " +
        "than those of iOS, whose tests take only the link_opts, module_name and opts of native: remove " +
        "target_compatible_with from native, or add a konan target that has a native test, e.g. macos_arm64; the " +
        "attributes of the iOS test are those of ios",
        _ios_tests_error(["ios_arm64", "ios_simulator_arm64"], version, native = dict(target_compatible_with = [":constraint"])),
    )

    # The attributes of the compilation and of the link are those of the library of the iOS tests
    # too, and with another konan target the native test takes the others.
    asserts.equals(env, None, _ios_tests_error(simulator, version, native = library_attrs))
    for platforms in [simulator + ["linux_x64"], ["macos_arm64", "ios_arm64"]]:
        asserts.equals(env, None, _ios_tests_error(platforms, version, native = dict(library_attrs, **native_test_attrs)))

    # The associates of another test come first, then the iOS test, then the attributes of the
    # native test, and the sources of the platforms last.
    asserts.equals(
        env,
        "native sets associates, which the macro sets to the library of the platform",
        _ios_tests_error(simulator, None, ios_test_rule = None, native = dict(associates = [":lib"])),
    )
    asserts.equals(
        env,
        "platforms lists ios_simulator_arm64, whose test needs a deployment target, which the macro has no default " +
        "for: pass it as ios = dict(minimum_os_version = ...), e.g. \"15.0\"",
        _ios_tests_error(simulator, None, native = native_test_attrs),
    )
    asserts.equals(
        env,
        "native sets data, an attribute of the native test, but platforms lists no konan target other than those of " +
        "iOS, whose tests take only the link_opts, module_name and opts of native: remove data from native, or add a " +
        "konan target that has a native test, e.g. macos_arm64; the attributes of the iOS test are those of ios",
        _tests_error(
            simulator,
            settings = {"ios": version, "native": dict(data = [":data"])},
            ios_test_rule = _fake_ios_unit_test,
            srcs_jvm = ["JvmTest.kt"],
        ),
    )
    asserts.equals(
        env,
        "ios_simulator_arm64 has no sources: list some in the srcs of the macro, srcs_native, srcs_apple, srcs_ios or " +
        "srcs_ios_simulator_arm64, or remove ios_simulator_arm64 from platforms",
        _tests_error(simulator, settings = {"ios": version}, ios_test_rule = _fake_ios_unit_test, srcs_jvm = ["JvmTest.kt"]),
    )

    return unittest.end(env)

suite_attrs_test = unittest.make(_suite_attrs_test)
platform_library_test = unittest.make(_platform_library_test)

def _ios_test_konan_targets_test(ctx):
    env = unittest.begin(ctx)

    # The iOS test is a target of the platform of the build: the host that builds its iOS targets,
    # or one of them. Elsewhere, e.g. on Linux, the build skips it.
    asserts.equals(env, ["ios_simulator_arm64", "macos_arm64"], ios_test_konan_targets(["ios_simulator_arm64"]))
    asserts.equals(
        env,
        ["ios_arm64", "ios_simulator_arm64", "macos_arm64"],
        ios_test_konan_targets(["ios_arm64", "ios_simulator_arm64"]),
    )

    return unittest.end(env)

tests_error_test = unittest.make(_tests_error_test)
ios_tests_error_test = unittest.make(_ios_tests_error_test)
ios_test_konan_targets_test = unittest.make(_ios_test_konan_targets_test)

# The constraints a test of the macro adds to those of the konan targets.
_CONSTRAINTS = [":macro_constraint", ":ios_constraint"]

def _compatibility(target_compatible_with):
    """The konan targets a target_compatible_with has a branch for, then its constraints, in their order.

    The value is the one the macro passed to a rule, or the one of an existing rule, which prints
    its labels in another form: both end the label of the setting of a konan target with a quote.
    """
    text = repr(target_compatible_with)
    konan_targets = [target for target in sorted(KONAN_TARGETS) if ":is_%s\"" % target in text]
    constraints = sorted([(text.find(constraint), constraint) for constraint in _CONSTRAINTS if constraint in text])
    return " ".join(konan_targets + [constraint for _, constraint in constraints])

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

    # The constraints of the tests of mpp_ios_test, which nothing builds.
    native.constraint_setting(name = "tm_constraint")
    for constraint in _CONSTRAINTS:
        native.constraint_value(
            name = constraint[1:],
            constraint_setting = ":tm_constraint",
        )

    # The arguments of the calls of the rule of the iOS tests, by the name of the test.
    ios_tests = {}
    ios_test_rule = _recording_ios_test_rule(ios_tests)

    # A library of the test bundles, next to the Kotlin tests.
    _fake_objc_library(
        name = "tm_bundled",
        tags = ["manual"],
        testonly = True,
    )

    # The JVM and the Linux target compile the test sources of an alias; the konan targets those of
    # native, and the iOS simulator has no test source of its own. The arguments of the native test
    # are no attribute of the library of the iOS tests, which the opt-in is. The test bundle links
    # the deps of `ios` too.
    kt_multiplatform_test(
        name = "mpp_test",
        size = "small",
        aliases = {"jvm_linux": [
            "jvm",
            "linux_arm64",
        ]},
        ios = dict(
            minimum_os_version = _IOS_VERSION,
            deps = [":tm_bundled"],
        ),
        ios_test_rule = ios_test_rule,
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
        native = dict(
            args = ["--ktest_logger=SIMPLE"],
            opts = [_OPT_IN],
        ),
        srcs_jvm = ["testdata/test/Expected.jvm.kt"],
        srcs_jvm_linux = ["testdata/test/JvmLinuxTest.kt"],
        srcs_native = ["testdata/test/Expected.native.kt"],
        tags = ["manual"],
    )

    # The tests of the iOS targets alone: the macro declares no native test, and the iOS test has
    # the constraints of the macro and of `ios` after its own, and collects coverage, as `ios` asks.
    # The library of the iOS tests, which builds for another platform, has none of the constraints,
    # and has the options of `native`. The deps of `ios` are a select.
    kt_multiplatform_test(
        name = "mpp_ios_test",
        srcs = ["testdata/test/GreetingTest.kt"],
        ios = dict(
            collect_code_coverage = True,
            minimum_os_version = _IOS_VERSION,
            target_compatible_with = [":ios_constraint"],
            deps = select({"//conditions:default": [":tm_bundled"]}),
        ),
        ios_test_rule = ios_test_rule,
        library = ":mpp",
        native = dict(
            link_opts = ["-opt"],
            opts = [_OPT_IN],
        ),
        platforms = [
            "ios_arm64",
            "ios_simulator_arm64",
        ],
        srcs_native = ["testdata/test/Expected.native.kt"],
        tags = ["manual"],
        target_compatible_with = [":macro_constraint"],
    )

    # A test of the JVM alone that names its test class runs it, without the suite; the rule of the
    # iOS tests is unused.
    kt_multiplatform_test(
        name = "mpp_explicit_test",
        ios_test_rule = ios_test_rule,
        library = ":mpp",
        platforms = ["jvm"],
        srcs = ["testdata/test/GreetingTest.kt"],
        jvm = dict(test_class = "kmp.test.GreetingTest"),
        srcs_jvm = ["testdata/test/Expected.jvm.kt"],
        tags = ["manual"],
    )

    # A test of one platform whose sources are those of one list compiles them as its own, without
    # a fragment, although its library has several platforms.
    kt_multiplatform_test(
        name = "mpp_pruned_test",
        srcs = ["testdata/test/GreetingTest.kt"],
        library = ":mpp",
        platforms = ["jvm"],
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

    jvm_test(
        name = "test_macro_pruned_test",
        target_under_test = ":mpp_pruned_test_jvm",
        associate = "mpp_jvm",
        friend_jar = "mpp_jvm.abi.jar",
        suite = True,
        test_class = _SUITE_CLASS,
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

    # The tests of the iOS simulator link into the library of a test bundle, with the launcher of
    # the rules as a source of their leaf, the native library as associate and the opt-in of
    # `native`; the library is no test and has no size.
    native_ios_simulator_arm64_test(
        name = "test_macro_ios_library_test",
        target_under_test = ":mpp_test_ios_lib",
        associate = "mpp_native",
        fragments = [
            "common",
            "native",
            "ios_simulator_arm64",
        ],
        friend_klib = "mpp_native.klib",
        kmp_fragments = ["mpp_test_fragment_native"],
        produce = "static",
        refines = [
            "native:common",
            "ios_simulator_arm64:native",
        ],
        sources = [
            "common:GreetingTest.kt",
            "native:Expected.native.kt",
            "ios_simulator_arm64:mpp_test_ios_lib_XCTestLauncher.kt",
        ],
        srcs = [
            "GreetingTest.kt",
            "Expected.native.kt",
            "mpp_test_ios_lib_XCTestLauncher.kt",
        ],
        target_compatible_with = not_on_windows(),
    )
    ios_test(
        name = "test_macro_ios_test",
        target_under_test = ":mpp_test_ios",
        deps = [
            "mpp_test_ios_lib",
            "tm_bundled",
        ],
        minimum_os_version = _IOS_VERSION,
        target_compatible_with = not_on_windows(),
        test_size = "small",
    )

    # The iOS targets go to the iOS test and its library, the other konan targets to the native
    # test, which the macro does not declare without any; the test_suite has the tests declared,
    # which an existing rule lists in the order of their labels.
    declared = [
        "mpp_explicit_test",
        "mpp_explicit_test_ios",
        "mpp_explicit_test_ios_lib",
        "mpp_explicit_test_jvm",
        "mpp_explicit_test_native",
        "mpp_ios_test",
        "mpp_ios_test_ios",
        "mpp_ios_test_ios_lib",
        "mpp_ios_test_native",
        "mpp_pruned_test",
        "mpp_pruned_test_fragment_common",
        "mpp_pruned_test_jvm",
        "mpp_test",
        "mpp_test_ios",
        "mpp_test_ios_lib",
        "mpp_test_jvm",
        "mpp_test_native",
    ]
    declared_test(
        name = "test_macro_declared_targets_test",
        actual = [target for target in declared if native.existing_rule(target)],
        expected = [
            "mpp_explicit_test",
            "mpp_explicit_test_jvm",
            "mpp_ios_test",
            "mpp_ios_test_ios",
            "mpp_ios_test_ios_lib",
            "mpp_pruned_test",
            "mpp_pruned_test_jvm",
            "mpp_test",
            "mpp_test_ios",
            "mpp_test_ios_lib",
            "mpp_test_jvm",
            "mpp_test_native",
        ],
    )
    declared_test(
        name = "test_macro_test_suite_test",
        actual = [
            "%s: %s" % (suite, " ".join(native.existing_rule(suite)["tests"]))
            for suite in ["mpp_test", "mpp_ios_test", "mpp_explicit_test"]
        ],
        expected = [
            "mpp_test: :mpp_test_ios :mpp_test_jvm :mpp_test_native",
            "mpp_ios_test: :mpp_ios_test_ios",
            "mpp_explicit_test: :mpp_explicit_test_jvm",
        ],
    )

    # The macro calls the rule of the iOS tests once per test, with the library and then the deps
    # of `ios`, a list or a select, as deps, and the other attributes of `ios`. The test collects
    # no coverage unless `ios` asks for it: the Kotlin tests are not instrumented, and the runner
    # of rules_apple fails a test that wrote no profile.
    declared_test(
        name = "test_macro_ios_test_rule_test",
        actual = [
            "%s: %s" % (test, ", ".join(["%s = %r" % (key, value) for key, value in sorted(kwargs.items()) if key != "target_compatible_with"]))
            for test, kwargs in ios_tests.items()
        ],
        expected = [
            "mpp_test_ios: collect_code_coverage = False, deps = [\":mpp_test_ios_lib\", \":tm_bundled\"], " +
            "minimum_os_version = \"15.0\", size = \"small\", tags = [\"manual\"], visibility = None",
            "mpp_ios_test_ios: collect_code_coverage = True, deps = [\":mpp_ios_test_ios_lib\"] + " +
            "select({\"//conditions:default\": [\":tm_bundled\"]}), minimum_os_version = \"15.0\", tags = [\"manual\"], " +
            "visibility = None",
        ],
    )

    # The native test has every attribute of `native`. The library of the iOS tests has those of
    # the compilation and of the link, also without a native test, and not the arguments of a test.
    declared_test(
        name = "test_macro_native_attrs_test",
        actual = [
            "%s: %s" % (target, ", ".join([
                "%s = %s" % (attr, " ".join(native.existing_rule(target)[attr]))
                for attr in ["args", "link_opts", "opts"]
                if native.existing_rule(target).get(attr)
            ]))
            for target in ["mpp_test_native", "mpp_test_ios_lib", "mpp_ios_test_ios_lib"]
        ],
        expected = [
            "mpp_test_native: args = --ktest_logger=SIMPLE, opts = " + _OPT_IN,
            "mpp_test_ios_lib: opts = " + _OPT_IN,
            "mpp_ios_test_ios_lib: link_opts = -opt, opts = " + _OPT_IN,
        ],
    )

    # The library of the iOS tests is compatible with the listed iOS targets alone, and the native
    # test with the other konan targets. The iOS test is a target of the platform of the build,
    # which its test bundle leaves for an iOS platform: it is compatible with the host that builds
    # the iOS targets too, and skipped when the bundle builds the library for another platform.
    declared_test(
        name = "test_macro_compatibility_test",
        actual = [
            "%s: %s" % (test, _compatibility(kwargs["target_compatible_with"]))
            for test, kwargs in ios_tests.items()
        ] + [
            "%s: %s" % (target, _compatibility(native.existing_rule(target)["target_compatible_with"]))
            for target in ["mpp_test_ios_lib", "mpp_ios_test_ios_lib", "mpp_test_native"]
        ],
        expected = [
            "mpp_test_ios: ios_simulator_arm64 macos_arm64",
            "mpp_ios_test_ios: ios_arm64 ios_simulator_arm64 macos_arm64 :macro_constraint :ios_constraint",
            "mpp_test_ios_lib: ios_simulator_arm64",
            "mpp_ios_test_ios_lib: ios_arm64 ios_simulator_arm64",
            "mpp_test_native: linux_arm64",
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
        ios_tests_error_test,
        ios_test_konan_targets_test,
    )

    native.test_suite(
        name = name,
        tests = [
            ":test_macro_alias_fragment_test",
            ":test_macro_android_test",
            ":test_macro_compatibility_test",
            ":test_macro_declared_targets_test",
            ":test_macro_explicit_test_class_test",
            ":test_macro_fragments_graph_test",
            ":test_macro_helpers",
            ":test_macro_ios_library_test",
            ":test_macro_ios_test",
            ":test_macro_ios_test_rule_test",
            ":test_macro_jvm_test",
            ":test_macro_native_attrs_test",
            ":test_macro_native_linux_test",
            ":test_macro_pruned_test",
            ":test_macro_test_suite_test",
        ],
    )
