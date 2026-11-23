"""Analysis tests for kt_native_library: the klib action and the KtKlibInfo provider.

See common.bzl for the fake toolchains.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_java//java:defs.bzl", "java_library")
load("//kotlin:core.bzl", "kt_compiler_plugin")
load("//kotlin:native.bzl", "KtKlibInfo", "kt_native_library")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:fragment.bzl", "kt_kmp_fragment")
load(
    ":common.bzl",
    "AIRPLANE_MODE",
    "BTAPI_RUNTIME",
    "DEPS",
    "HEADER_KLIBS_ATTRS",
    "HOME",
    "PACKAGE",
    "argument_after",
    "compile_klib_of",
    "fake_klib",
    "for_target",
    "launcher_arguments",
    "launcher_values",
    "libraries",
    "not_on_windows",
    "prefixed",
    "single_action",
    "tool_arguments",
    "with_header_klibs",
    "with_native_btapi",
)

# The prefix of the module names derived from the labels of the package.
_NAMES = "src_test_starlark_internal_native-"

def _basenames(files):
    return sorted([f.basename for f in files])

def _klib_compile_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = ctx.attr.konan_target
    action = single_action(env, "KotlinNativeKlibCompile")
    target_under_test = analysistest.target_under_test(env)
    info = target_under_test[KtKlibInfo]
    klib = info.klib

    # With header klibs, the action also writes the header klib, which dependents compile against.
    # The library lists its klib only.
    header = info.compile_klib if ctx.attr.header_klib else None
    if header:
        asserts.equals(env, compile_klib_of(klib.path, True), header.path)
        asserts.equals(env, sorted([klib.path, header.path]), sorted([f.path for f in action.outputs.to_list()]))
    else:
        asserts.equals(env, klib, info.compile_klib)
        asserts.equals(env, [klib], action.outputs.to_list())
    asserts.equals(env, [klib], target_under_test[DefaultInfo].files.to_list())

    # With the Build Tools API on, the jars of its implementation are inputs too.
    btapi_classpath = BTAPI_RUNTIME if ctx.attr.btapi else []
    inputs = [f.path for f in action.inputs.to_list()]
    for expected in [
        HOME + "/konan/lib/kotlin-native-compiler-embeddable.jar",
        HOME + "/klib/common/stdlib/default/manifest",
        HOME + "/klib/platform/%s/posix/default/manifest" % target,
        PACKAGE + "/testdata/greeter.kt",
    ] + btapi_classpath:
        asserts.true(env, expected in inputs, "%s should be an input" % expected)
    for jar in BTAPI_RUNTIME:
        asserts.equals(env, ctx.attr.btapi, jar in inputs, jar)
    for path in inputs:
        for excluded in [
            HOME + "/klib/platform/" + ctx.attr.other_target + "/",
            HOME + "/klib/cache/",
            HOME + "/bin/",
            DEPS + "/",
        ]:
            asserts.false(env, path.startswith(excluded), "%s should not be an input" % path)

    # The launcher prepares the scratch dirs next to the klib; a klib needs no link dependencies. It
    # gets the output and the sources of the klib, and the Build Tools API implementation to compile
    # it with when the build setting is on.
    argv = action.argv
    asserts.equals(env, "konan_launcher", argv[0].rpartition("/")[2])
    asserts.equals(
        env,
        [
            "--tool",
            "konanc",
            "--konan-home",
            HOME,
            "--data-dir",
            klib.path + ".konan_data",
            "--auto-cache-dir",
            klib.path + ".konan_cache",
            "--klib-output",
            klib.path,
            "--source",
            PACKAGE + "/testdata/greeter.kt",
        ] + [arg for jar in btapi_classpath for arg in ["--btapi-classpath", jar]],
        launcher_arguments(argv),
    )

    # The launcher adds -produce library, -o and the sources to the konanc flags, or gives them to
    # the Build Tools API apart from them.
    tool = tool_arguments(argv)
    for arg in ["-produce", "-o", PACKAGE + "/testdata/greeter.kt"]:
        asserts.false(env, arg in tool, "%s should not be in %s" % (arg, tool))
    asserts.equals(env, target, argument_after(tool, "-target"))
    asserts.equals(env, _NAMES + target_under_test.label.name, argument_after(tool, "-module-name"))
    for flag in [
        "-Xkonan-data-dir=%s.konan_data" % klib.path,
        "-Xauto-cache-dir=%s.konan_cache" % klib.path,
        AIRPLANE_MODE,
        "-Xklib-relative-path-base=__EXECROOT__",
        "-Xdebug-prefix-map=__EXECROOT__=.",
    ]:
        asserts.true(env, flag in tool, "%s should be in %s" % (flag, tool))

    # The header klib is an option of the rule, the last one without opts.
    asserts.equals(env, [header.path] if header else [], prefixed(tool, "-Xheader-klib-path="))
    if header:
        asserts.equals(env, "-Xheader-klib-path=" + header.path, tool[-1])
    asserts.false(env, "-l" in tool, "a klib without deps compiles against no klibs: %s" % tool)
    asserts.false(env, "-Xmulti-platform" in tool, "a library without kmp_fragments compiles no fragments: %s" % tool)

    asserts.equals(env, "1", action.env.get("LIBCLANG_DISABLE_CRASH_RECOVERY"))

    # Only an Apple target gets the Xcode SDK of the target (its execution requirements are the
    # toolchain's, see toolchain_test.bzl; analysis tests cannot read those of an action).
    asserts.equals(env, ctx.attr.apple_sdk_platform or None, action.env.get("APPLE_SDK_PLATFORM"), str(action.env))

    return analysistest.end(env)

def _provider_test_impl(ctx):
    env = analysistest.begin(ctx)

    info = analysistest.target_under_test(env)[KtKlibInfo]
    asserts.equals(env, "exporter_linux_arm64.klib", info.klib.basename)
    asserts.equals(env, "native", info.platform)
    asserts.equals(env, "linux_arm64", info.konan_target)
    asserts.equals(env, "exporter", info.module_name)
    asserts.equals(env, None, info.cc_info)

    # Its exports and theirs, which its dependents compile against as if they were their deps.
    asserts.equals(
        env,
        ["exported_linux_arm64.klib", "reexported_linux_arm64.klib"],
        _basenames(info.exported_klibs.to_list()),
    )
    asserts.equals(
        env,
        [
            "base_linux_arm64.klib",
            "exported_linux_arm64.klib",
            "exporter_linux_arm64.klib",
            "reexported_linux_arm64.klib",
        ],
        _basenames(info.transitive_klibs.to_list()),
    )

    # What its dependents compile against: the same closure, in the same order, with the header klib
    # of every library when header klibs are on.
    header_klibs = ctx.attr.header_klibs
    asserts.equals(env, compile_klib_of(info.klib.path, header_klibs), info.compile_klib.path)
    asserts.equals(
        env,
        [compile_klib_of(f.path, header_klibs) for f in info.transitive_klibs.to_list()],
        [f.path for f in info.transitive_compile_klibs.to_list()],
    )

    # It compiles against the compile klibs of its deps and exports, transitively, in the order of
    # their closure, and reads no other klib.
    action = single_action(env, "KotlinNativeKlibCompile")
    tool = tool_arguments(action.argv)
    libraries = [tool[i + 1] for i in range(len(tool)) if tool[i] == "-l"]
    asserts.equals(
        env,
        [f.path for f in info.transitive_compile_klibs.to_list() if f != info.compile_klib],
        libraries,
    )
    asserts.equals(
        env,
        [
            compile_klib_of(name, header_klibs)
            for name in ["base_linux_arm64.klib", "exported_linux_arm64.klib", "reexported_linux_arm64.klib"]
        ],
        sorted([path.rpartition("/")[2] for path in libraries]),
    )
    inputs = [f.basename for f in action.inputs.to_list()]
    asserts.equals(
        env,
        sorted([path.rpartition("/")[2] for path in libraries]),
        sorted([name for name in inputs if name.endswith(".klib")]),
    )

    return analysistest.end(env)

def _consumer_test_impl(ctx):
    env = analysistest.begin(ctx)

    # A dependent of the exporter compiles against the full closure, its exports included: against
    # their header klibs, with header klibs on.
    tool = tool_arguments(single_action(env, "KotlinNativeKlibCompile").argv)
    asserts.equals(
        env,
        [
            compile_klib_of(name, ctx.attr.header_klibs)
            for name in [
                "base_linux_arm64.klib",
                "exported_linux_arm64.klib",
                "exporter_linux_arm64.klib",
                "reexported_linux_arm64.klib",
            ]
        ],
        sorted([tool[i + 1].rpartition("/")[2] for i in range(len(tool)) if tool[i] == "-l"]),
    )

    return analysistest.end(env)

def _header_incompatible_dep_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The library in the middle writes no header klib: the top one compiles against its klib, and
    # against the header klib of the one below it. Its links read the klibs of both.
    tool = tool_arguments(single_action(env, "KotlinNativeKlibCompile").argv)
    asserts.equals(
        env,
        ["chain_bottom_linux_arm64.header.klib", "chain_middle_linux_arm64.klib"],
        sorted([path.rpartition("/")[2] for path in libraries(tool)]),
    )
    asserts.equals(
        env,
        ["chain_bottom_linux_arm64.klib", "chain_middle_linux_arm64.klib", "chain_top_linux_arm64.klib"],
        _basenames(analysistest.target_under_test(env)[KtKlibInfo].transitive_klibs.to_list()),
    )

    return analysistest.end(env)

def _plugins_test_impl(ctx):
    env = analysistest.begin(ctx)

    action = single_action(env, "KotlinNativeKlibCompile")
    tool = tool_arguments(action.argv)

    # The compiler is embeddable: the plugin built for the CLI compiler is reshaded to its dialect,
    # the one built for the embeddable compiler is loaded as it is.
    plugin_jars = [arg[len("-Xplugin="):] for arg in tool if arg.startswith("-Xplugin=")]
    asserts.equals(
        env,
        ["libplugin_lib.jar", "plugin_lib_embeddable_reshaded_libplugin_lib.jar"],
        sorted([jar.rpartition("/")[2] for jar in plugin_jars]),
    )
    inputs = [f.path for f in action.inputs.to_list()]
    for jar in plugin_jars:
        asserts.true(env, jar in inputs, "%s should be an input" % jar)

    # The options of the compile-phase plugins; the stubs-only plugin does not run.
    options = [tool[i + 1] for i in range(len(tool)) if tool[i] == "-P"]
    asserts.equals(env, ["plugin:test.cli:enabled=true"], options)

    # The user options follow the options of the rule, last.
    asserts.true(env, tool.index("-opt-in=kotlin.ExperimentalStdlibApi") > tool.index(AIRPLANE_MODE))
    asserts.equals(env, "-opt-in=kotlin.ExperimentalStdlibApi", tool[-1])

    return analysistest.end(env)

def _klib_target_mismatch_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(env, "is for target linux_x64, but this target is linux_arm64")

    return analysistest.end(env)

def _klib_platform_mismatch_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(env, "is a js klib, not a Kotlin/Native one")

    return analysistest.end(env)

def _fragments_test_impl(ctx):
    env = analysistest.begin(ctx)

    action = single_action(env, "KotlinNativeKlibCompile")
    info = analysistest.target_under_test(env)[KtKlibInfo]
    tool = tool_arguments(action.argv)
    common = PACKAGE + "/testdata/common.kt"
    actual = PACKAGE + "/testdata/actual.kt"
    greeter = PACKAGE + "/testdata/greeter.kt"
    fragments = ["jvm-linux_arm64-linux_x64", "linux_arm64-linux_x64", "linux_arm64"]

    # The module name derives from the label; the leaf fragment is named after the konan target.
    asserts.equals(env, _NAMES + "fragments_linux_arm64", argument_after(tool, "-module-name"))

    # The fragments, most shared first, each after those it refines, and the srcs of the library, the
    # leaf fragment. Their flags follow the common ones, before the libraries.
    start = tool.index("-Xmulti-platform")
    asserts.equals(env, "-Xdebug-prefix-map=__EXECROOT__=.", tool[start - 1])
    asserts.equals(
        env,
        [
            "-Xmulti-platform",
            "-Xexpect-actual-classes",
            "-Xfragments=" + ",".join(fragments),
            "-Xfragment-sources=%s:%s" % (fragments[0], common),
            "-Xfragment-sources=%s:%s" % (fragments[1], actual),
            "-Xfragment-sources=%s:%s" % (fragments[2], greeter),
            "-Xfragment-refines=%s:%s" % (fragments[1], fragments[0]),
            "-Xfragment-refines=%s:%s" % (fragments[2], fragments[1]),
            "-l",
        ],
        tool[start:start + 9],
    )

    # Every source of the fragments compiles, those of the leaf last, and is an input.
    asserts.equals(env, [info.klib.path], launcher_values(action.argv, "--klib-output"))
    asserts.equals(env, [common, actual, greeter], launcher_values(action.argv, "--source"))
    inputs = [f.path for f in action.inputs.to_list()]
    for src in [common, actual, greeter]:
        asserts.true(env, src in inputs, "%s should be an input" % src)

    # A fragment has no deps: the library compiles every fragment against its own deps.
    asserts.equals(env, ["fake_linux_arm64_klib.klib"], [path.rpartition("/")[2] for path in libraries(tool)])
    asserts.equals(
        env,
        ["fake_linux_arm64_klib.klib", "fragments_linux_arm64.klib"],
        _basenames(info.transitive_klibs.to_list()),
    )

    return analysistest.end(env)

def _empty_leaf_test_impl(ctx):
    env = analysistest.begin(ctx)

    action = single_action(env, "KotlinNativeKlibCompile")
    info = analysistest.target_under_test(env)[KtKlibInfo]
    asserts.equals(env, [info.klib], action.outputs.to_list())
    tool = tool_arguments(action.argv)
    common = PACKAGE + "/testdata/common.kt"
    actual = PACKAGE + "/testdata/actual.kt"
    fragments = ["jvm-linux_arm64-linux_x64", "linux_arm64-linux_x64", "linux_arm64"]

    # Without srcs the leaf is empty: it is still a fragment refining the others, with no sources.
    # Without deps, plugins and opts, the fragment flags are the last ones.
    start = tool.index("-Xmulti-platform")
    asserts.equals(
        env,
        [
            "-Xmulti-platform",
            "-Xexpect-actual-classes",
            "-Xfragments=" + ",".join(fragments),
            "-Xfragment-sources=%s:%s" % (fragments[0], common),
            "-Xfragment-sources=%s:%s" % (fragments[1], actual),
            "-Xfragment-refines=%s:%s" % (fragments[1], fragments[0]),
            "-Xfragment-refines=%s:%s" % (fragments[2], fragments[1]),
        ],
        tool[start:],
    )

    # The klib compiles the sources of the fragments only.
    asserts.equals(env, [info.klib.path], launcher_values(action.argv, "--klib-output"))
    asserts.equals(env, [common, actual], launcher_values(action.argv, "--source"))

    return analysistest.end(env)

def _file_in_two_fragments_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The shared fragment lists it first, then the leaf, named after the konan target.
    asserts.expect_failure(
        env,
        "the source %s/testdata/actual.kt is in both fragment 'jvm-linux_arm64' and 'linux_arm64'" % PACKAGE,
    )

    return analysistest.end(env)

def _refine_mismatch_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(env, "the fragment 'linux_arm64-linux_x64' cannot refine 'jvm-linux_arm64', which linux_x64 does not compile")

    return analysistest.end(env)

_KLIB_COMPILE_ATTRS = {
    "apple_sdk_platform": attr.string(),
    # Whether the launcher compiles the klib with the Build Tools API implementation of the toolchain.
    "btapi": attr.bool(default = True),
    # Whether the library writes a header klib.
    "header_klib": attr.bool(),
    "konan_target": attr.string(),
    "other_target": attr.string(),
}

klib_compile_linux_arm64_test = analysistest.make(
    _klib_compile_test_impl,
    attrs = _KLIB_COMPILE_ATTRS,
    config_settings = for_target("linux_arm64"),
)
klib_compile_macos_arm64_test = analysistest.make(
    _klib_compile_test_impl,
    attrs = _KLIB_COMPILE_ATTRS,
    config_settings = for_target("macos_arm64"),
)
klib_compile_header_klibs_test = analysistest.make(
    _klib_compile_test_impl,
    attrs = _KLIB_COMPILE_ATTRS,
    config_settings = with_header_klibs(for_target("linux_arm64")),
)
klib_compile_btapi_off_test = analysistest.make(
    _klib_compile_test_impl,
    attrs = _KLIB_COMPILE_ATTRS,
    config_settings = with_native_btapi(for_target("linux_arm64"), False),
)
provider_test = analysistest.make(
    _provider_test_impl,
    attrs = HEADER_KLIBS_ATTRS,
    config_settings = for_target("linux_arm64"),
)
provider_header_klibs_test = analysistest.make(
    _provider_test_impl,
    attrs = HEADER_KLIBS_ATTRS,
    config_settings = with_header_klibs(for_target("linux_arm64")),
)
consumer_test = analysistest.make(
    _consumer_test_impl,
    attrs = HEADER_KLIBS_ATTRS,
    config_settings = for_target("linux_arm64"),
)
consumer_header_klibs_test = analysistest.make(
    _consumer_test_impl,
    attrs = HEADER_KLIBS_ATTRS,
    config_settings = with_header_klibs(for_target("linux_arm64")),
)
header_incompatible_dep_test = analysistest.make(
    _header_incompatible_dep_test_impl,
    config_settings = with_header_klibs(for_target("linux_arm64")),
)
plugins_test = analysistest.make(_plugins_test_impl, config_settings = for_target("linux_arm64"))
klib_target_mismatch_test = analysistest.make(
    _klib_target_mismatch_test_impl,
    config_settings = for_target("linux_arm64"),
    expect_failure = True,
)
klib_platform_mismatch_test = analysistest.make(
    _klib_platform_mismatch_test_impl,
    config_settings = for_target("linux_arm64"),
    expect_failure = True,
)
fragments_test = analysistest.make(_fragments_test_impl, config_settings = for_target("linux_arm64"))
empty_leaf_test = analysistest.make(_empty_leaf_test_impl, config_settings = for_target("linux_arm64"))
file_in_two_fragments_test = analysistest.make(
    _file_in_two_fragments_test_impl,
    config_settings = for_target("linux_arm64"),
    expect_failure = True,
)
refine_mismatch_test = analysistest.make(
    _refine_mismatch_test_impl,
    config_settings = for_target("linux_arm64"),
    expect_failure = True,
)

def native_library_test_suite(name):
    """Declares the targets under test and the analysis tests of kt_native_library.

    The fake toolchains (common.bzl: define_fake_toolchains) must be declared in the package.

    Args:
      name: the name of the generated test_suite target.
    """
    for target in ["linux_arm64", "macos_arm64"]:
        kt_native_library(
            name = "greeter_" + target,
            srcs = ["testdata/greeter.kt"],
            tags = ["manual"],
        )

    # A library that writes no header klib, even with header klibs on.
    kt_native_library(
        name = "greeter_without_header_linux_arm64",
        srcs = ["testdata/greeter.kt"],
        tags = [
            "kt_native_header_klib_incompatible",
            "manual",
        ],
    )

    # exporter: deps = [base], exports = [exported], which exports reexported.
    for library in ["base", "reexported"]:
        kt_native_library(
            name = library + "_linux_arm64",
            srcs = ["testdata/greeter.kt"],
            tags = ["manual"],
        )
    kt_native_library(
        name = "exported_linux_arm64",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
        exports = [":reexported_linux_arm64"],
    )
    kt_native_library(
        name = "exporter_linux_arm64",
        srcs = ["testdata/greeter.kt"],
        module_name = "exporter",
        tags = ["manual"],
        exports = [":exported_linux_arm64"],
        deps = [":base_linux_arm64"],
    )
    kt_native_library(
        name = "consumer_linux_arm64",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
        deps = [":exporter_linux_arm64"],
    )

    # chain_top: deps = [chain_middle], which writes no header klib and depends on chain_bottom.
    kt_native_library(
        name = "chain_bottom_linux_arm64",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
    )
    kt_native_library(
        name = "chain_middle_linux_arm64",
        srcs = ["testdata/greeter.kt"],
        tags = [
            "kt_native_header_klib_incompatible",
            "manual",
        ],
        deps = [":chain_bottom_linux_arm64"],
    )
    kt_native_library(
        name = "chain_top_linux_arm64",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
        deps = [":chain_middle_linux_arm64"],
    )

    java_library(
        name = "plugin_lib",
        srcs = ["testdata/FakePlugin.java"],
        tags = ["manual"],
    )
    kt_compiler_plugin(
        name = "cli_plugin",
        id = "test.cli",
        options = {"enabled": ["true"]},
        tags = ["manual"],
        deps = [":plugin_lib"],
    )
    kt_compiler_plugin(
        name = "embedded_plugin",
        id = "test.embedded",
        tags = ["manual"],
        target_embedded_compiler = True,
        deps = [":plugin_lib"],
    )
    kt_compiler_plugin(
        name = "stubs_plugin",
        compile_phase = False,
        id = "test.stubs",
        options = {"stubs": ["true"]},
        stubs_phase = True,
        tags = ["manual"],
        deps = [":plugin_lib"],
    )
    kt_native_library(
        name = "plugins_linux_arm64",
        srcs = ["testdata/greeter.kt"],
        opts = ["-opt-in=kotlin.ExperimentalStdlibApi"],
        plugins = [
            ":cli_plugin",
            ":embedded_plugin",
            ":stubs_plugin",
        ],
        tags = ["manual"],
    )

    fake_klib(
        name = "fake_linux_x64_klib",
        konan_target = "linux_x64",
        tags = ["manual"],
    )
    kt_native_library(
        name = "mismatched_linux_arm64",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
        deps = [":fake_linux_x64_klib"],
    )
    fake_klib(
        name = "fake_js_klib",
        platform = "js",
        tags = ["manual"],
    )
    kt_native_library(
        name = "js_dep_linux_arm64",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
        deps = [":fake_js_klib"],
    )

    # fragments_linux_arm64: frag_native refines frag_common, shared by more platforms including its
    # own. The library compiles both with its srcs, against its own deps: a fragment has none.
    fake_klib(
        name = "fake_linux_arm64_klib",
        konan_target = "linux_arm64",
        tags = ["manual"],
    )
    kt_kmp_fragment(
        name = "frag_common",
        srcs = ["testdata/common.kt"],
        platforms = ["jvm", "linux_arm64", "linux_x64"],
        tags = ["manual"],
    )
    kt_kmp_fragment(
        name = "frag_native",
        srcs = ["testdata/actual.kt"],
        platforms = ["linux_arm64", "linux_x64"],
        refines = [":frag_common"],
        tags = ["manual"],
    )
    kt_native_library(
        name = "fragments_linux_arm64",
        srcs = ["testdata/greeter.kt"],
        kmp_fragments = [":frag_native"],
        tags = ["manual"],
        deps = [":fake_linux_arm64_klib"],
    )

    # An empty leaf: a library without srcs still compiles its fragments into a klib.
    kt_native_library(
        name = "empty_leaf_linux_arm64",
        kmp_fragments = [":frag_native"],
        tags = ["manual"],
    )

    # A source that both a fragment and the srcs of the library list is in two fragments.
    kt_kmp_fragment(
        name = "frag_with_actual",
        srcs = ["testdata/actual.kt"],
        platforms = ["jvm", "linux_arm64"],
        tags = ["manual"],
    )
    kt_native_library(
        name = "file_in_two_fragments_linux_arm64",
        srcs = ["testdata/actual.kt"],
        kmp_fragments = [":frag_with_actual"],
        tags = ["manual"],
    )

    # frag_bad_refine cannot refine frag_with_actual, which linux_x64, one of its platforms, does not
    # compile.
    kt_kmp_fragment(
        name = "frag_bad_refine",
        srcs = ["testdata/greeter.kt"],
        platforms = ["linux_arm64", "linux_x64"],
        refines = [":frag_with_actual"],
        tags = ["manual"],
    )
    kt_native_library(
        name = "refine_mismatch_linux_arm64",
        srcs = ["testdata/main.kt"],
        kmp_fragments = [":frag_bad_refine"],
        tags = ["manual"],
    )

    klib_compile_linux_arm64_test(
        name = "klib_compile_inputs_test",
        target_under_test = ":greeter_linux_arm64",
        konan_target = "linux_arm64",
        other_target = "macos_arm64",
        target_compatible_with = not_on_windows(),
    )

    # With the Build Tools API off, the launcher compiles the klib with konanc, from the same flags.
    klib_compile_btapi_off_test(
        name = "klib_compile_btapi_off_test",
        target_under_test = ":greeter_linux_arm64",
        btapi = False,
        konan_target = "linux_arm64",
        other_target = "macos_arm64",
        target_compatible_with = not_on_windows(),
    )

    # klibs compile for a target its bundle does not stage.
    klib_compile_macos_arm64_test(
        name = "unstaged_klib_compile_inputs_test",
        target_under_test = ":greeter_macos_arm64",
        apple_sdk_platform = "MacOSX",
        konan_target = "macos_arm64",
        other_target = "linux_arm64",
        target_compatible_with = not_on_windows(),
    )
    provider_test(
        name = "klib_provider_test",
        target_under_test = ":exporter_linux_arm64",
        target_compatible_with = not_on_windows(),
    )

    # With header klibs, a library also writes its header klib, unless its tag opts it out.
    klib_compile_header_klibs_test(
        name = "klib_compile_header_test",
        target_under_test = ":greeter_linux_arm64",
        header_klib = True,
        konan_target = "linux_arm64",
        other_target = "macos_arm64",
        target_compatible_with = not_on_windows(),
    )
    klib_compile_header_klibs_test(
        name = "klib_compile_header_incompatible_test",
        target_under_test = ":greeter_without_header_linux_arm64",
        konan_target = "linux_arm64",
        other_target = "macos_arm64",
        target_compatible_with = not_on_windows(),
    )
    provider_header_klibs_test(
        name = "klib_header_provider_test",
        target_under_test = ":exporter_linux_arm64",
        header_klibs = True,
        target_compatible_with = not_on_windows(),
    )
    consumer_test(
        name = "klib_exports_test",
        target_under_test = ":consumer_linux_arm64",
        target_compatible_with = not_on_windows(),
    )

    # With header klibs, dependents compile against the header klibs of the closure, but against the
    # klib of a library that opts out.
    consumer_header_klibs_test(
        name = "klib_header_exports_test",
        target_under_test = ":consumer_linux_arm64",
        header_klibs = True,
        target_compatible_with = not_on_windows(),
    )
    header_incompatible_dep_test(
        name = "klib_header_incompatible_dep_test",
        target_under_test = ":chain_top_linux_arm64",
        target_compatible_with = not_on_windows(),
    )
    plugins_test(
        name = "klib_plugins_test",
        target_under_test = ":plugins_linux_arm64",
        target_compatible_with = not_on_windows(),
    )
    klib_target_mismatch_test(
        name = "klib_target_mismatch_test",
        target_under_test = ":mismatched_linux_arm64",
        target_compatible_with = not_on_windows(),
    )
    klib_platform_mismatch_test(
        name = "klib_platform_mismatch_test",
        target_under_test = ":js_dep_linux_arm64",
        target_compatible_with = not_on_windows(),
    )
    fragments_test(
        name = "klib_fragments_test",
        target_under_test = ":fragments_linux_arm64",
        target_compatible_with = not_on_windows(),
    )
    empty_leaf_test(
        name = "klib_empty_leaf_test",
        target_under_test = ":empty_leaf_linux_arm64",
        target_compatible_with = not_on_windows(),
    )
    file_in_two_fragments_test(
        name = "klib_file_in_two_fragments_test",
        target_under_test = ":file_in_two_fragments_linux_arm64",
        target_compatible_with = not_on_windows(),
    )
    refine_mismatch_test(
        name = "klib_refine_mismatch_test",
        target_under_test = ":refine_mismatch_linux_arm64",
        target_compatible_with = not_on_windows(),
    )

    native.test_suite(
        name = name,
        tests = [
            ":klib_compile_btapi_off_test",
            ":klib_compile_header_incompatible_test",
            ":klib_compile_header_test",
            ":klib_compile_inputs_test",
            ":klib_empty_leaf_test",
            ":klib_exports_test",
            ":klib_file_in_two_fragments_test",
            ":klib_fragments_test",
            ":klib_header_exports_test",
            ":klib_header_incompatible_dep_test",
            ":klib_header_provider_test",
            ":klib_platform_mismatch_test",
            ":klib_plugins_test",
            ":klib_provider_test",
            ":klib_refine_mismatch_test",
            ":klib_target_mismatch_test",
            ":unstaged_klib_compile_inputs_test",
        ],
    )
