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
    "DEPS",
    "HOME",
    "PACKAGE",
    "argument_after",
    "fake_klib",
    "for_target",
    "launcher_arguments",
    "libraries",
    "not_on_windows",
    "single_action",
    "tool_arguments",
)

# The prefix of the module names derived from the labels of the package.
_NAMES = "src_test_starlark_internal_native-"

def _basenames(files):
    return sorted([f.basename for f in files])

def _klib_compile_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = ctx.attr.konan_target
    action = single_action(env, "KotlinNativeKlibCompile")
    klib = analysistest.target_under_test(env)[KtKlibInfo].klib
    asserts.equals(env, [klib], action.outputs.to_list())

    inputs = [f.path for f in action.inputs.to_list()]
    for expected in [
        HOME + "/konan/lib/kotlin-native-compiler-embeddable.jar",
        HOME + "/klib/common/stdlib/default/manifest",
        HOME + "/klib/platform/%s/posix/default/manifest" % target,
        PACKAGE + "/testdata/greeter.kt",
    ]:
        asserts.true(env, expected in inputs, "%s should be an input" % expected)
    for path in inputs:
        for excluded in [
            HOME + "/klib/platform/" + ctx.attr.other_target + "/",
            HOME + "/klib/cache/",
            HOME + "/bin/",
            DEPS + "/",
        ]:
            asserts.false(env, path.startswith(excluded), "%s should not be an input" % path)

    # The launcher prepares the scratch dirs next to the klib; a klib needs no link dependencies.
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
        ],
        launcher_arguments(argv),
    )

    tool = tool_arguments(argv)
    asserts.equals(env, "library", argument_after(tool, "-produce"))
    asserts.equals(env, target, argument_after(tool, "-target"))
    asserts.equals(env, "src_test_starlark_internal_native-greeter_" + target, argument_after(tool, "-module-name"))
    for flag in [
        "-Xkonan-data-dir=%s.konan_data" % klib.path,
        "-Xauto-cache-dir=%s.konan_cache" % klib.path,
        AIRPLANE_MODE,
        "-Xklib-relative-path-base=__EXECROOT__",
        "-Xdebug-prefix-map=__EXECROOT__=.",
    ]:
        asserts.true(env, flag in tool, "%s should be in %s" % (flag, tool))
    asserts.equals(env, klib.path, argument_after(tool, "-o"))
    asserts.equals(env, PACKAGE + "/testdata/greeter.kt", tool[-1])
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

    # It compiles against its deps and exports, transitively.
    action = single_action(env, "KotlinNativeKlibCompile")
    tool = tool_arguments(action.argv)
    libraries = [tool[i + 1] for i in range(len(tool)) if tool[i] == "-l"]
    asserts.equals(
        env,
        ["base_linux_arm64.klib", "exported_linux_arm64.klib", "reexported_linux_arm64.klib"],
        sorted([path.rpartition("/")[2] for path in libraries]),
    )
    inputs = [f.basename for f in action.inputs.to_list()]
    for library in libraries:
        asserts.true(env, library.rpartition("/")[2] in inputs, "%s should be an input" % library)

    return analysistest.end(env)

def _consumer_test_impl(ctx):
    env = analysistest.begin(ctx)

    # A dependent of the exporter compiles against the full closure, its exports included.
    tool = tool_arguments(single_action(env, "KotlinNativeKlibCompile").argv)
    asserts.equals(
        env,
        [
            "base_linux_arm64.klib",
            "exported_linux_arm64.klib",
            "exporter_linux_arm64.klib",
            "reexported_linux_arm64.klib",
        ],
        sorted([tool[i + 1].rpartition("/")[2] for i in range(len(tool)) if tool[i] == "-l"]),
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

    # The user options follow the options of the rule.
    asserts.true(env, tool.index("-opt-in=kotlin.ExperimentalStdlibApi") > tool.index(AIRPLANE_MODE))
    asserts.true(env, tool.index("-opt-in=kotlin.ExperimentalStdlibApi") < tool.index("-o"))

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
    asserts.equals(env, [info.klib.path, common, actual, greeter], tool[tool.index("-o") + 1:])
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
            "-o",
        ],
        tool[start:start + 8],
    )

    # The klib compiles the sources of the fragments only.
    asserts.equals(env, [info.klib.path, common, actual], tool[tool.index("-o") + 1:])

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

    asserts.expect_failure(env, "the fragment 'linux_arm64-linux_x64' cannot refine 'jvm-linux_arm64'")

    return analysistest.end(env)

_KLIB_COMPILE_ATTRS = {
    "apple_sdk_platform": attr.string(),
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
provider_test = analysistest.make(_provider_test_impl, config_settings = for_target("linux_arm64"))
consumer_test = analysistest.make(_consumer_test_impl, config_settings = for_target("linux_arm64"))
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

    # frag_bad_refine cannot refine frag_with_actual, which is not shared by more platforms: as many,
    # and not linux_x64.
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
    consumer_test(
        name = "klib_exports_test",
        target_under_test = ":consumer_linux_arm64",
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
            ":klib_compile_inputs_test",
            ":klib_empty_leaf_test",
            ":klib_exports_test",
            ":klib_file_in_two_fragments_test",
            ":klib_fragments_test",
            ":klib_platform_mismatch_test",
            ":klib_plugins_test",
            ":klib_provider_test",
            ":klib_refine_mismatch_test",
            ":klib_target_mismatch_test",
            ":unstaged_klib_compile_inputs_test",
        ],
    )
