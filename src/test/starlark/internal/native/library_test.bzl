"""Analysis tests for kt_native_library: the klib action and the KtKlibInfo provider.

See common.bzl for the fake toolchains.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_java//java:defs.bzl", "java_library")
load("//kotlin:core.bzl", "kt_compiler_plugin")
load("//kotlin:native.bzl", "KtKlibInfo", "kt_native_library")
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
    "not_on_windows",
    "single_action",
    "tool_arguments",
)

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

def _source_sets_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(env, "source_sets are reserved for Kotlin Multiplatform source sets")

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
source_sets_test = analysistest.make(
    _source_sets_test_impl,
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
    kt_native_library(
        name = "source_sets_linux_arm64",
        srcs = ["testdata/greeter.kt"],
        source_sets = [":base_linux_arm64"],
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
    source_sets_test(
        name = "klib_source_sets_unsupported_test",
        target_under_test = ":source_sets_linux_arm64",
        target_compatible_with = not_on_windows(),
    )

    native.test_suite(
        name = name,
        tests = [
            ":klib_compile_inputs_test",
            ":klib_exports_test",
            ":klib_platform_mismatch_test",
            ":klib_plugins_test",
            ":klib_provider_test",
            ":klib_source_sets_unsupported_test",
            ":klib_target_mismatch_test",
            ":unstaged_klib_compile_inputs_test",
        ],
    )
