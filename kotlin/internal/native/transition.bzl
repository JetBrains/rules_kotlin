"""The rule transitions of the Kotlin platform type (//kotlin/settings:kotlin_platform_type).

The Kotlin/Native rules set it to `native` for themselves and their deps, so a select() on
//kotlin/native/platforms:native or native_<konan target> resolves to a klib below them and to a
JVM library below any other rule. The transition is incoming, so a Kotlin/Native target used at the
top level and as a dep is built once.

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

TRANSITION_ATTRS = {
    "_allowlist_function_transition": attr.label(
        default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
    ),
}
