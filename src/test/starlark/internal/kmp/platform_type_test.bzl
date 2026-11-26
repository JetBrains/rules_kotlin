"""Analysis tests for the Kotlin platform type: an alias selecting a klib for the Kotlin/Native rules and a JVM library for the others.

The alias has the shape of those of kmp_maven: it selects, for the Kotlin/Native rules
(//kotlin/native/platforms:native), an alias of the klib of each konan target
(//kotlin/native/platforms:native_<konan target>), here an imported klib of linux_arm64, and the
JVM library by default. Every consumer builds for the linux_arm64 platform, a host of that konan
target: the Kotlin/Native ones get the klib, as they set //kotlin/settings:kotlin_platform_type to
native for themselves and their deps, and the JVM ones get the JVM library, whose platform type
stays jvm, also as the platforms of a kt_multiplatform_library listing the alias in their deps.
(A Kotlin/Native consumer of another konan target gets the no_match_error of the alias, a
configuration error that analysistest cannot expect.) The native consumers use the fake toolchains
of //src/test/starlark/internal/native (see common.bzl there).

The tools of a Kotlin/Native target, a compiler plugin, a plugin configuration and a KSP processor
with the alias in their deps, get the JVM library: below a Kotlin/Native consumer, and built
directly with the platform type native, which checks the rule transition of the tool rules alone.

The alias also has the Android library of `alias_branches`, the branches of the alias of a
kt_multiplatform_library, which a consumer gets on an Android platform and in the host hybrid mode
of rules_android: below a kt_android_local_test, and built directly with the mode on. A
Kotlin/Native consumer built with the mode on still gets the klib, and the tools the JVM library,
in the configuration they have without the mode.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@rules_java//java:defs.bzl", "JavaInfo", "java_library")
load("//kotlin:android.bzl", "kt_android_local_test")
load("//kotlin:core.bzl", "kt_compiler_plugin", "kt_ksp_plugin", "kt_plugin_cfg")
load("//kotlin:jvm.bzl", "kt_jvm_library")
load("//kotlin:kmp.bzl", "kt_multiplatform_library", "kt_native_ksp_sources")
load("//kotlin:native.bzl", "KtKlibInfo", "kt_klib_import", "kt_native_library")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:multiplatform.bzl", "alias_branches")
load("//src/main/starlark/core/plugin:providers.bzl", "KspPluginInfo", "KtCompilerPluginInfo", "KtPluginConfiguration")
load(
    "//src/test/starlark/internal/native:common.bzl",
    "for_target",
    "libraries",
    "not_on_windows",
    "prefixed",
    "single_action",
    "tool_arguments",
)

_KLIB = "imported.klib"
_JAR = "libpt_jvm_lib-hjar.jar"
_RUNTIME_JAR = "libpt_jvm_lib.jar"

# The copy of the runtime jar in the embeddable compiler dialect, which the Kotlin/Native compiler loads.
_PLUGIN_JAR = "pt_jvm_lib_embeddable_reshaded_" + _RUNTIME_JAR

# The Android library of the alias.
_ANDROID_JAR = "libpt_lib_android-hjar.jar"
_ANDROID_RUNTIME_JAR = "libpt_lib_android.jar"

_PLATFORM_TYPE = Label("//kotlin/settings:kotlin_platform_type")
_HOST_HYBRID_MODE = Label("@rules_android//rules/flags:android_host_hybrid_mode")
_ANDROID_PLATFORM = Label("//src/test/starlark/internal/kmp:pt_android_arm64")

_PlatformTypeInfo = provider(
    doc = "The Kotlin platform type, the Android host hybrid mode and the output root of the configuration of a target.",
    fields = {
        "android_host_hybrid_mode": "The value of @rules_android//rules/flags:android_host_hybrid_mode.",
        "bin_dir": "The path of the output root of the binaries.",
        "value": "The value of //kotlin/settings:kotlin_platform_type.",
    },
)

def _platform_type_aspect_impl(
        target,  # @unused
        ctx):
    return [_PlatformTypeInfo(
        android_host_hybrid_mode = ctx.attr._android_host_hybrid_mode[BuildSettingInfo].value,
        bin_dir = ctx.bin_dir.path,
        value = ctx.attr._platform_type[BuildSettingInfo].value,
    )]

# Reads the build settings in the configuration of the target under test, after its rule transition.
_platform_type_aspect = aspect(
    implementation = _platform_type_aspect_impl,
    attrs = {
        "_android_host_hybrid_mode": attr.label(default = _HOST_HYBRID_MODE),
        "_platform_type": attr.label(default = _PLATFORM_TYPE),
    },
)

_InHostHybridModeInfo = provider(
    doc = "A target built in the host hybrid mode of rules_android.",
    fields = {"target": "The Target, with the providers of its rule and the _PlatformTypeInfo of its configuration."},
)

def _host_hybrid_mode_transition_impl(
        settings,  # @unused
        attr):  # @unused
    return {str(_HOST_HYBRID_MODE): True}

_host_hybrid_mode_transition = transition(
    implementation = _host_hybrid_mode_transition_impl,
    inputs = [],
    outputs = [str(_HOST_HYBRID_MODE)],
)

def _in_host_hybrid_mode_impl(ctx):
    return [_InHostHybridModeInfo(target = ctx.attr.target[0])]

# Asks for a target with the host hybrid mode on, as kt_android_local_test asks for its deps. Unlike
# the config_settings of an analysis test, whose configurations Bazel marks as such, it changes the
# mode alone: a target that turns the mode off again is in the configuration of the test.
_in_host_hybrid_mode = rule(
    implementation = _in_host_hybrid_mode_impl,
    attrs = {
        "target": attr.label(
            aspects = [_platform_type_aspect],
            cfg = _host_hybrid_mode_transition,
            mandatory = True,
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

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

def _native_plugin_test_impl(ctx):
    env = analysistest.begin(ctx)

    # A compiler plugin runs in the JVM of the compiler, whatever the compilation targets, so its deps are
    # JVM libraries: the plugin of a Kotlin/Native library gets the JVM library of the alias, as the plugin
    # of a JVM library does, and never the klib.
    action = single_action(env, "KotlinNativeKlibCompile")
    plugin_jars = [_basename(path) for path in prefixed(tool_arguments(action.argv), "-Xplugin=")]
    asserts.equals(env, [_PLUGIN_JAR], plugin_jars)
    inputs = [f.basename for f in action.inputs.to_list()]
    asserts.true(env, _PLUGIN_JAR in inputs, "%s should be an input" % _PLUGIN_JAR)
    asserts.false(env, _KLIB in inputs, "%s should not be an input" % _KLIB)

    return analysistest.end(env)

def _native_processor_test_impl(ctx):
    env = analysistest.begin(ctx)

    # A KSP processor runs in the JVM of KSP, like a compiler plugin: the processor of a Kotlin/Native
    # target gets the JVM library of the alias.
    action = single_action(env, "KspNative")
    inputs = [f.basename for f in action.inputs.to_list()]
    asserts.true(env, _RUNTIME_JAR in inputs, "%s should be an input" % _RUNTIME_JAR)
    asserts.false(env, _KLIB in inputs, "%s should not be an input" % _KLIB)

    return analysistest.end(env)

def _native_setting_alias_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The control of the tool tests below: their configuration has the platform type native, where the
    # alias is the klib, as below a Kotlin/Native rule.
    target = analysistest.target_under_test(env)
    asserts.equals(env, "native", target[_PlatformTypeInfo].value, "the Kotlin platform type of the alias")
    asserts.true(env, KtKlibInfo in target, "the alias should be the klib")
    asserts.false(env, JavaInfo in target, "the alias should not be the JVM library")

    return analysistest.end(env)

def _assert_jvm_tool(env, classpath, jar):
    """A tool asked for with the platform type native builds with jvm, and its classpath is the JVM library of the alias.

    A tool is JVM code whatever the compilation it serves targets, so its rule sets the platform type
    to jvm for itself and its deps. The exec configuration of a Kotlin/Native target keeps native on
    a Bazel that ignores the scope of the build setting (7 and 8), which the configuration of these
    tests stands for on any Bazel. Where the exec transition to the deps resets the setting (Bazel 9),
    the classpath is the same without the rule transition, and only the platform type tells it is there.
    """
    target = analysistest.target_under_test(env)
    asserts.equals(env, "jvm", target[_PlatformTypeInfo].value, "the Kotlin platform type of the tool")
    asserts.equals(env, [jar], [f.basename for f in classpath.to_list()])

def _native_setting_plugin_test_impl(ctx):
    env = analysistest.begin(ctx)
    _assert_jvm_tool(env, analysistest.target_under_test(env)[KtCompilerPluginInfo].embeddable_classpath, _PLUGIN_JAR)
    return analysistest.end(env)

def _native_setting_plugin_cfg_test_impl(ctx):
    env = analysistest.begin(ctx)
    _assert_jvm_tool(env, analysistest.target_under_test(env)[KtPluginConfiguration].classpath, _RUNTIME_JAR)
    return analysistest.end(env)

def _native_setting_processor_test_impl(ctx):
    env = analysistest.begin(ctx)
    _assert_jvm_tool(env, analysistest.target_under_test(env)[KspPluginInfo].plugins[0].plugins.processor_jars, _RUNTIME_JAR)
    return analysistest.end(env)

def _android_consumer_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The consumer compiles against the Android library of the alias, and neither the JVM one nor a klib.
    actions = [action for action in analysistest.target_actions(env) if action.mnemonic == "KotlinCompile"]
    asserts.equals(env, 1, len(actions), "KotlinCompile actions")
    classpath = [_basename(path) for path in _values(actions[0].argv, "--classpath")]
    asserts.true(env, _ANDROID_JAR in classpath, "%s should be in --classpath %s" % (_ANDROID_JAR, classpath))
    asserts.false(env, _JAR in classpath, "%s should not be in --classpath %s" % (_JAR, classpath))
    inputs = [f.basename for f in actions[0].inputs.to_list()]
    asserts.false(env, _KLIB in inputs, "%s should not be an input" % _KLIB)

    # Its tools are JVM code, whatever the compilation they serve targets: its compiler plugin, with
    # and without a configuration, and its KSP processor get the JVM library of the alias, the very
    # file the tools of a JVM target get, so they build once for both.
    if ctx.attr.tools:
        payload = json.decode(_values(actions[0].argv, "--plugins_payload")[0])
        asserts.equals(env, [[_RUNTIME_JAR]], [[_basename(path) for path in plugin["classpath"]] for plugin in payload["plugins"]])
        ksp = single_action(env, "KotlinKsp2")
        processor_classpath = [_basename(path) for path in _values(ksp.argv, "--processor_classpath")]
        asserts.true(env, _RUNTIME_JAR in processor_classpath, "%s should be in --processor_classpath %s" % (_RUNTIME_JAR, processor_classpath))
        tool_jar = [jar.path for jar in ctx.attr._tool_library[JavaInfo].runtime_output_jars]
        for action in [actions[0], ksp]:
            asserts.equals(
                env,
                tool_jar,
                [f.path for f in action.inputs.to_list() if f.basename == _RUNTIME_JAR],
                "the JVM library among the inputs of %s" % action.mnemonic,
            )
            tool_inputs = [f.basename for f in action.inputs.to_list()]
            asserts.false(env, _ANDROID_RUNTIME_JAR in tool_inputs, "%s should not be an input of %s" % (_ANDROID_RUNTIME_JAR, action.mnemonic))

    return analysistest.end(env)

def _host_hybrid_mode_alias_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The control of the tool tests below: where they are asked for, the host hybrid mode is on and the
    # alias is the Android library, as below a kt_android_local_test, in a configuration of its own.
    target = analysistest.target_under_test(env)[_InHostHybridModeInfo].target
    asserts.equals(env, "jvm", target[_PlatformTypeInfo].value, "the Kotlin platform type of the alias")
    asserts.equals(env, True, target[_PlatformTypeInfo].android_host_hybrid_mode, "the host hybrid mode of the alias")
    asserts.equals(env, [_ANDROID_RUNTIME_JAR], [jar.basename for jar in target[JavaInfo].runtime_output_jars])
    asserts.true(
        env,
        ctx.bin_dir.path != target[_PlatformTypeInfo].bin_dir,
        "the host hybrid mode should give the alias an output root of its own, not %s" % ctx.bin_dir.path,
    )

    return analysistest.end(env)

def _host_tool(env):
    """The tool under test, asked for in the configuration of the test or, through _in_host_hybrid_mode, with the host hybrid mode on."""
    target = analysistest.target_under_test(env)
    return target[_InHostHybridModeInfo].target if _InHostHybridModeInfo in target else target

def _assert_host_tool(env, classpath, jar):
    """A tool asked for with the host hybrid mode on builds with it off, in the configuration of a tool of a JVM target.

    The exec configuration of a kt_android_local_test keeps the mode on a Bazel that ignores the
    scope of the build setting (7 and 8), which _in_host_hybrid_mode stands for on any Bazel: the
    rule of the tool turns it off, so its classpath is the JVM library of the alias and never the
    Android one. A build setting at its default is no part of a configuration, so the tool builds
    where it does without the mode, in the output root of the test: the rule transition adds no
    configuration to a build, also not to one without Android, where the tool is asked for in the
    configuration of the test.
    """
    info = _host_tool(env)[_PlatformTypeInfo]
    asserts.equals(env, "jvm", info.value, "the Kotlin platform type of the tool")
    asserts.equals(env, False, info.android_host_hybrid_mode, "the host hybrid mode of the tool")
    asserts.equals(env, [jar], [f.basename for f in classpath.to_list()])
    asserts.equals(env, env.ctx.bin_dir.path, info.bin_dir, "the output root of the tool")

def _host_plugin_test_impl(ctx):
    env = analysistest.begin(ctx)
    _assert_host_tool(env, _host_tool(env)[KtCompilerPluginInfo].embeddable_classpath, _PLUGIN_JAR)
    return analysistest.end(env)

def _host_plugin_cfg_test_impl(ctx):
    env = analysistest.begin(ctx)
    _assert_host_tool(env, _host_tool(env)[KtPluginConfiguration].classpath, _RUNTIME_JAR)
    return analysistest.end(env)

def _host_processor_test_impl(ctx):
    env = analysistest.begin(ctx)
    _assert_host_tool(env, _host_tool(env)[KspPluginInfo].plugins[0].plugins.processor_jars, _RUNTIME_JAR)
    return analysistest.end(env)

def _jvm_without_sources_test_impl(ctx):
    env = analysistest.begin(ctx)

    # A platform that lists no source compiles nothing, as a target without sources of a Kotlin
    # Multiplatform module of Gradle: the JVM library is empty, and the deps of every platform are its
    # runtime deps, where kt_jvm_library takes the deps of a library without srcs.
    target = analysistest.target_under_test(env)
    asserts.equals(env, [], [action.mnemonic for action in analysistest.target_actions(env) if action.mnemonic == "KotlinCompile"])
    runtime_jars = [jar.basename for jar in target[JavaInfo].transitive_runtime_jars.to_list()]
    asserts.true(env, _RUNTIME_JAR in runtime_jars, "%s should be in the runtime classpath %s" % (_RUNTIME_JAR, runtime_jars))
    compile_jars = [jar.basename for jar in target[JavaInfo].transitive_compile_time_jars.to_list()]
    asserts.false(env, _JAR in compile_jars, "%s should not be in the compile classpath %s" % (_JAR, compile_jars))

    return analysistest.end(env)

native_consumer_test = analysistest.make(_native_consumer_test_impl, config_settings = for_target("linux_arm64"))
native_plugin_test = analysistest.make(_native_plugin_test_impl, config_settings = for_target("linux_arm64"))
native_processor_test = analysistest.make(_native_processor_test_impl, config_settings = for_target("linux_arm64"))
jvm_consumer_test = analysistest.make(_jvm_consumer_test_impl, config_settings = for_target("linux_arm64"))
jvm_without_sources_test = analysistest.make(_jvm_without_sources_test_impl, config_settings = for_target("linux_arm64"))

# The configuration of a target below a Kotlin/Native rule, asked for directly.
_NATIVE_SETTING = dict(for_target("linux_arm64"), **{str(_PLATFORM_TYPE): "native"})

native_setting_alias_test = analysistest.make(
    _native_setting_alias_test_impl,
    config_settings = _NATIVE_SETTING,
    extra_target_under_test_aspects = [_platform_type_aspect],
)
native_setting_plugin_test = analysistest.make(
    _native_setting_plugin_test_impl,
    config_settings = _NATIVE_SETTING,
    extra_target_under_test_aspects = [_platform_type_aspect],
)
native_setting_plugin_cfg_test = analysistest.make(
    _native_setting_plugin_cfg_test_impl,
    config_settings = _NATIVE_SETTING,
    extra_target_under_test_aspects = [_platform_type_aspect],
)
native_setting_processor_test = analysistest.make(
    _native_setting_processor_test_impl,
    config_settings = _NATIVE_SETTING,
    extra_target_under_test_aspects = [_platform_type_aspect],
)

# The tools of a consumer: a compiler plugin, a plugin configuration and a KSP processor.
_TOOLS = [
    ":pt_plugin",
    ":pt_plugin_cfg",
    ":pt_processor",
]

# The configuration of a target below a kt_android_local_test, asked for directly.
_HOST_HYBRID_SETTING = {str(_HOST_HYBRID_MODE): True}

_CONSUMER_ATTRS = {
    "tools": attr.bool(doc = "whether the consumer has the plugin, the plugin configuration and the KSP processor"),
    # The JVM library of the alias as the tools of a target of the configuration of the test get it.
    "_tool_library": attr.label(default = Label("//src/test/starlark/internal/kmp:pt_jvm_lib"), cfg = "exec"),
}

# The rule transition of kt_android_local_test turns the host hybrid mode on.
android_local_test_consumer_test = analysistest.make(_android_consumer_test_impl, attrs = _CONSUMER_ATTRS)
android_setting_consumer_test = analysistest.make(
    _android_consumer_test_impl,
    attrs = _CONSUMER_ATTRS,
    config_settings = _HOST_HYBRID_SETTING,
)
android_platform_consumer_test = analysistest.make(
    _android_consumer_test_impl,
    attrs = _CONSUMER_ATTRS,
    config_settings = {"//command_line_option:platforms": [str(_ANDROID_PLATFORM)]},
)

# A Kotlin/Native target below a kt_android_local_test: both the mode and the platform type are set.
android_setting_native_consumer_test = analysistest.make(
    _native_consumer_test_impl,
    config_settings = dict(for_target("linux_arm64"), **_HOST_HYBRID_SETTING),
)
host_hybrid_mode_alias_test = analysistest.make(_host_hybrid_mode_alias_test_impl)

# The tools of a JVM target, asked for in the configuration of the test, and those of a
# kt_android_local_test, asked for through _in_host_hybrid_mode.
host_plugin_test = analysistest.make(_host_plugin_test_impl, extra_target_under_test_aspects = [_platform_type_aspect])
host_plugin_cfg_test = analysistest.make(_host_plugin_cfg_test_impl, extra_target_under_test_aspects = [_platform_type_aspect])
host_processor_test = analysistest.make(_host_processor_test_impl, extra_target_under_test_aspects = [_platform_type_aspect])

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

    java_library(
        name = "pt_lib_android",
        srcs = ["testdata/PlatformTypeAndroidLib.java"],
        tags = ["manual"],
    )
    native.alias(
        name = "pt_lib_jvm",
        actual = ":pt_jvm_lib",
        tags = ["manual"],
    )
    native.platform(
        name = _ANDROID_PLATFORM.name,
        constraint_values = [
            "@platforms//cpu:arm64",
            "@platforms//os:android",
        ],
    )

    # The aliases of a library resolved for the JVM, Android and linux_arm64, as kmp_maven declares
    # them, with the conditions of the alias of a kt_multiplatform_library of these platforms.
    native.alias(
        name = "pt_lib",
        actual = select(alias_branches("pt_lib", {"android": ["android"], "jvm": ["jvm"], "native": ["linux_arm64"]})),
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

    # Each platform of a multiplatform library resolves the deps of every platform in its own
    # configuration, and compiles the fragment of the sources they share against them.
    kt_multiplatform_library(
        name = "pt_mpp",
        platforms = [
            "jvm",
            "linux_arm64",
        ],
        srcs = ["testdata/Platform.kt"],
        deps = [":pt_lib"],
        srcs_jvm = ["testdata/Platform.jvm.kt"],
        srcs_linux = ["testdata/Platform.linux.kt"],
        tags = ["manual"],
    )

    # Only linux_arm64 lists sources: the JVM has none, and the deps of every platform.
    kt_multiplatform_library(
        name = "pt_mpp_native_sources",
        platforms = [
            "jvm",
            "linux_arm64",
        ],
        deps = [":pt_lib"],
        srcs_linux = ["testdata/Platform.linux.kt"],
        tags = ["manual"],
    )
    jvm_without_sources_test(
        name = "platform_type_jvm_without_sources_test",
        target_under_test = ":pt_mpp_native_sources_jvm",
        target_compatible_with = not_on_windows(),
    )

    # The tools of a Kotlin/Native target with the alias in their deps, directly and through a kt_plugin_cfg.
    kt_compiler_plugin(
        name = "pt_plugin",
        id = "pt.plugin",
        tags = ["manual"],
        deps = [":pt_lib"],
    )
    kt_plugin_cfg(
        name = "pt_plugin_cfg",
        options = {"key": ["value"]},
        plugin = ":pt_plugin",
        tags = ["manual"],
        deps = [":pt_lib"],
    )
    kt_ksp_plugin(
        name = "pt_processor",
        processor_class = "example.Provider",
        tags = ["manual"],
        deps = [":pt_lib"],
    )
    kt_native_library(
        name = "pt_native_with_plugin",
        srcs = ["testdata/Platform.linux.kt"],
        plugins = [":pt_plugin"],
        tags = ["manual"],
    )
    kt_native_library(
        name = "pt_native_with_plugin_cfg",
        srcs = ["testdata/Platform.linux.kt"],
        plugins = [":pt_plugin_cfg"],
        tags = ["manual"],
    )
    kt_native_ksp_sources(
        name = "pt_native_with_processor",
        srcs = ["testdata/Platform.linux.kt"],
        generated = ["Gen.kt"],
        processors = [":pt_processor"],
        tags = ["manual"],
    )

    # The consumers of the Android library: a local test, whose rule turns the host hybrid mode on, and
    # a JVM library asked for with the mode on or for an Android platform, each with the tools above.
    kt_android_local_test(
        name = "pt_android_local_test",
        srcs = ["testdata/Platform.jvm.kt"],
        custom_package = "kmp.test",
        manifest = "testdata/AndroidManifest.xml",
        plugins = _TOOLS,
        tags = ["manual"],
        test_class = "kmp.test.PlatformTest",
        deps = [":pt_lib"],
    )
    kt_jvm_library(
        name = "pt_jvm_consumer_with_tools",
        srcs = ["testdata/Platform.jvm.kt"],
        plugins = _TOOLS,
        tags = ["manual"],
        deps = [":pt_lib"],
    )

    # The Android SDK of the workspace is not known to resolve on Windows.
    android_local_test_consumer_test(
        name = "platform_type_android_local_test_consumer_test",
        target_under_test = ":pt_android_local_test",
        tools = True,
        target_compatible_with = not_on_windows(),
    )
    android_setting_consumer_test(
        name = "platform_type_android_setting_consumer_test",
        target_under_test = ":pt_jvm_consumer_with_tools",
        tools = True,
        target_compatible_with = not_on_windows(),
    )
    android_platform_consumer_test(
        name = "platform_type_android_platform_consumer_test",
        target_under_test = ":pt_jvm_consumer",
        target_compatible_with = not_on_windows(),
    )
    android_setting_native_consumer_test(
        name = "platform_type_android_setting_native_consumer_test",
        target_under_test = ":pt_native_consumer",
        target_compatible_with = not_on_windows(),
    )

    # The alias and the tools, asked for with the host hybrid mode on.
    for target in ["pt_lib", "pt_plugin", "pt_plugin_cfg", "pt_processor"]:
        _in_host_hybrid_mode(
            name = target + "_in_host_hybrid_mode",
            tags = ["manual"],
            target = ":" + target,
        )
    host_hybrid_mode_alias_test(
        name = "platform_type_host_hybrid_mode_alias_test",
        target_under_test = ":pt_lib_in_host_hybrid_mode",
        target_compatible_with = not_on_windows(),
    )
    host_plugin_test(
        name = "platform_type_host_hybrid_mode_plugin_test",
        target_under_test = ":pt_plugin_in_host_hybrid_mode",
        target_compatible_with = not_on_windows(),
    )
    host_plugin_cfg_test(
        name = "platform_type_host_hybrid_mode_plugin_cfg_test",
        target_under_test = ":pt_plugin_cfg_in_host_hybrid_mode",
        target_compatible_with = not_on_windows(),
    )
    host_processor_test(
        name = "platform_type_host_hybrid_mode_processor_test",
        target_under_test = ":pt_processor_in_host_hybrid_mode",
        target_compatible_with = not_on_windows(),
    )
    host_plugin_test(
        name = "platform_type_host_plugin_test",
        target_under_test = ":pt_plugin",
        target_compatible_with = not_on_windows(),
    )
    host_plugin_cfg_test(
        name = "platform_type_host_plugin_cfg_test",
        target_under_test = ":pt_plugin_cfg",
        target_compatible_with = not_on_windows(),
    )
    host_processor_test(
        name = "platform_type_host_processor_test",
        target_under_test = ":pt_processor",
        target_compatible_with = not_on_windows(),
    )

    native_plugin_test(
        name = "platform_type_native_plugin_test",
        target_under_test = ":pt_native_with_plugin",
        target_compatible_with = not_on_windows(),
    )
    native_plugin_test(
        name = "platform_type_native_plugin_cfg_test",
        target_under_test = ":pt_native_with_plugin_cfg",
        target_compatible_with = not_on_windows(),
    )
    native_processor_test(
        name = "platform_type_native_processor_test",
        target_under_test = ":pt_native_with_processor",
        target_compatible_with = not_on_windows(),
    )
    native_setting_alias_test(
        name = "platform_type_native_setting_alias_test",
        target_under_test = ":pt_lib",
        target_compatible_with = not_on_windows(),
    )
    native_setting_plugin_test(
        name = "platform_type_native_setting_plugin_test",
        target_under_test = ":pt_plugin",
        target_compatible_with = not_on_windows(),
    )
    native_setting_plugin_cfg_test(
        name = "platform_type_native_setting_plugin_cfg_test",
        target_under_test = ":pt_plugin_cfg",
        target_compatible_with = not_on_windows(),
    )
    native_setting_processor_test(
        name = "platform_type_native_setting_processor_test",
        target_under_test = ":pt_processor",
        target_compatible_with = not_on_windows(),
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
        name = "platform_type_native_multiplatform_test",
        target_under_test = ":pt_mpp_native",
        target_compatible_with = not_on_windows(),
    )
    jvm_consumer_test(
        name = "platform_type_jvm_multiplatform_test",
        target_under_test = ":pt_mpp_jvm",
        target_compatible_with = not_on_windows(),
    )

    native.test_suite(
        name = name,
        tests = [
            ":platform_type_android_local_test_consumer_test",
            ":platform_type_android_platform_consumer_test",
            ":platform_type_android_setting_consumer_test",
            ":platform_type_android_setting_native_consumer_test",
            ":platform_type_host_hybrid_mode_alias_test",
            ":platform_type_host_hybrid_mode_plugin_cfg_test",
            ":platform_type_host_hybrid_mode_plugin_test",
            ":platform_type_host_hybrid_mode_processor_test",
            ":platform_type_host_plugin_cfg_test",
            ":platform_type_host_plugin_test",
            ":platform_type_host_processor_test",
            ":platform_type_jvm_consumer_test",
            ":platform_type_jvm_multiplatform_test",
            ":platform_type_jvm_without_sources_test",
            ":platform_type_native_consumer_test",
            ":platform_type_native_multiplatform_test",
            ":platform_type_native_plugin_cfg_test",
            ":platform_type_native_plugin_test",
            ":platform_type_native_processor_test",
            ":platform_type_native_setting_alias_test",
            ":platform_type_native_setting_plugin_cfg_test",
            ":platform_type_native_setting_plugin_test",
            ":platform_type_native_setting_processor_test",
        ],
    )
