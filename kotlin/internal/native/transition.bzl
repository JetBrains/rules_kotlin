"""The rule transition of the Kotlin/Native rules: their Kotlin platform type is native.

//kotlin/settings:kotlin_platform_type is the Bazel form of the Gradle attribute
org.jetbrains.kotlin.platform.type: `jvm` by default, which the JVM and Android rules leave as it is,
and `native` for the Kotlin/Native rules, which set it for themselves and their deps. A select() on
the config_settings //kotlin/native/platforms:native and native_<konan target>, like the alias of
kt_multiplatform_library, then resolves to a klib below a Kotlin/Native rule and to a JVM library
below any other rule, on any platform: a platform describes the machine, which a JVM library and a
klib of the konan target of a host share. The transition is incoming, so a Kotlin/Native target
used at the top level and as a dep is built once.
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

# The attribute a rule with kt_native_transition declares, as every rule with a Starlark transition.
TRANSITION_ATTRS = {
    "_allowlist_function_transition": attr.label(
        default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
    ),
}
