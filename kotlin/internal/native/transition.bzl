"""The rule transitions of the Kotlin platform type (//kotlin/settings:kotlin_platform_type).

The Kotlin/Native rules set it to `native` for themselves and their deps, so a select() on
//kotlin/native/platforms:native or native_<konan target> resolves to a klib below them and to a
JVM library below any other rule. The transition is incoming, so a Kotlin/Native target used at the
top level and as a dep is built once.

The tools of a Kotlin/Native target, e.g. its compiler plugins and KSP processors, are JVM code and
build with `jvm`: the build setting has the scope `target`, which the exec transition resets, and
their rules have kt_jvm_tool_transition.

The same goes for the host hybrid mode of rules_android, which the rule transition of
android_local_test and kt_android_local_test turns on for the test and its deps, where
//kotlin/settings:android selects the Android variant of a library: the tools of the test are no
Android code, and kt_jvm_tool_transition turns the mode off for them.
"""

KOTLIN_PLATFORM_TYPE = Label("//kotlin/settings:kotlin_platform_type")

# On below android_local_test and kt_android_local_test of rules_android 0.8.0 and newer.
ANDROID_HOST_HYBRID_MODE = Label("@rules_android//rules/flags:android_host_hybrid_mode")

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
    return {
        str(KOTLIN_PLATFORM_TYPE): "jvm",
        str(ANDROID_HOST_HYBRID_MODE): False,
    }

# The rule transition of the rules whose targets are JVM tools of a compilation: kt_compiler_plugin,
# kt_plugin_cfg and kt_ksp_plugin. A Bazel that ignores the scope of a build setting (7 and 8) keeps
# `native` in the exec configuration of a Kotlin/Native target, where the deps of its tools would
# select klibs, and the host hybrid mode in that of an Android local test, where they would select
# Android libraries: an aar_import on the classpath of a compiler plugin fails the build. Both
# outputs are the defaults of their settings, which are no part of a configuration: the transition
# leaves the configuration of a tool of a JVM target as it is, and gives the tools of the other
# targets that one.
kt_jvm_tool_transition = transition(
    implementation = _kt_jvm_tool_transition_impl,
    inputs = [],
    outputs = [
        str(KOTLIN_PLATFORM_TYPE),
        str(ANDROID_HOST_HYBRID_MODE),
    ],
)

TRANSITION_ATTRS = {
    "_allowlist_function_transition": attr.label(
        default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
    ),
}
