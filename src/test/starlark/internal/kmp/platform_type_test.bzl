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
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@rules_java//java:defs.bzl", "JavaInfo", "java_library")
load("//kotlin:core.bzl", "kt_compiler_plugin", "kt_ksp_plugin", "kt_plugin_cfg")
load("//kotlin:jvm.bzl", "kt_jvm_library")
load("//kotlin:kmp.bzl", "kt_multiplatform_library", "kt_native_ksp_sources")
load("//kotlin:native.bzl", "KtKlibInfo", "kt_klib_import", "kt_native_library")
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

_PLATFORM_TYPE = Label("//kotlin/settings:kotlin_platform_type")

_PlatformTypeInfo = provider(
    doc = "The Kotlin platform type of the configuration of a target.",
    fields = {"value": "The value of //kotlin/settings:kotlin_platform_type."},
)

def _platform_type_aspect_impl(
        target,  # @unused
        ctx):
    return [_PlatformTypeInfo(value = ctx.attr._platform_type[BuildSettingInfo].value)]

# Reads the build setting in the configuration of the target under test, after its rule transition.
_platform_type_aspect = aspect(
    implementation = _platform_type_aspect_impl,
    attrs = {"_platform_type": attr.label(default = _PLATFORM_TYPE)},
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
