"""The rule transition of the Kotlin/Native rules: their Kotlin platform type is native.

//kotlin/settings:kotlin_platform_type is the Bazel form of the Gradle attribute
org.jetbrains.kotlin.platform.type: `jvm` by default, which the JVM and Android rules leave as it is,
and `native` for the Kotlin/Native rules, which set it for themselves and their deps. A select() on
the config_settings //kotlin/native/platforms:native and native_<konan target>, like the alias of
kt_multiplatform_library, then resolves to a klib below a Kotlin/Native rule and to a JVM library
below any other rule, on any platform: a platform describes the machine, which a JVM library and a
klib of the konan target of a host share. The transition is incoming, so a Kotlin/Native target
used at the top level and as a dep is built once.

The tools of a Kotlin/Native target, e.g. its compiler plugins and KSP processors, are JVM code and
build with `jvm`: the build setting has the scope `target`, which the exec transition resets, and
their rules have kt_jvm_tool_transition.
"""

KOTLIN_PLATFORM_TYPE = Label("//kotlin/settings:kotlin_platform_type")

def _kt_native_transition_impl(
        settings,  # @unused
        attr):  # @unused
    return {str(KOTLIN_PLATFORM_TYPE): "native"}

kt_native_transition = transition(
    implementation = _kt_native_transition_impl,
    inputs = [],
    outputs = [str(KOTLIN_PLATFORM_TYPE)],
)

def _kt_jvm_tool_transition_impl(
        settings,  # @unused
        attr):  # @unused
    return {str(KOTLIN_PLATFORM_TYPE): "jvm"}

# The rule transition of the rules whose targets are JVM tools of a compilation: kt_compiler_plugin,
# kt_plugin_cfg and kt_ksp_plugin. A Bazel that ignores the scope of the build setting (7 and 8) keeps
# `native` in the exec configuration of a Kotlin/Native target, where the deps of its tools would
# select klibs. It leaves the configuration of a tool of a JVM target as it is.
kt_jvm_tool_transition = transition(
    implementation = _kt_jvm_tool_transition_impl,
    inputs = [],
    outputs = [str(KOTLIN_PLATFORM_TYPE)],
)

# The attribute a rule with one of the transitions declares, as every rule with a Starlark transition.
TRANSITION_ATTRS = {
    "_allowlist_function_transition": attr.label(
        default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
    ),
}
