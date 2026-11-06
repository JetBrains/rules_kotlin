"""The Kotlin/Native targets and exec hosts rules_kotlin supports.

`KONAN_TARGETS` maps a konan target to the constraints of the platform it builds for and, for an
Apple target, the name of its `apple_common.platform`, which selects the Xcode SDK of its actions.
`EXEC_HOSTS` maps a distribution host (the suffix of the `kotlin-native-prebuilt-<host>-<version>`
archives) to its konan name, the constraints of the exec platform it runs on and the konan targets
its distribution compiles for. Platforms, toolchains and repositories are all generated from these
tables, so a target or host is added here once.
"""

load(":transition.bzl", "KOTLIN_PLATFORM_TYPE")

_OS_IOS = Label("@platforms//os:ios")
_OS_LINUX = Label("@platforms//os:linux")
_OS_MACOS = Label("@platforms//os:macos")
_CPU_AARCH64 = Label("@platforms//cpu:aarch64")
_CPU_X86_64 = Label("@platforms//cpu:x86_64")

# apple_support tells an iOS device from a simulator with these, and marks its own Apple platforms
# (@build_bazel_apple_support//platforms) with APPLE_VENDOR_CONSTRAINT.
_APPLE_DEVICE = Label("@build_bazel_apple_support//constraints:device")
_APPLE_SIMULATOR = Label("@build_bazel_apple_support//constraints:simulator")
APPLE_VENDOR_CONSTRAINT = Label("@build_bazel_apple_support//constraints:apple")

KONAN_TARGETS = {
    "ios_arm64": struct(
        is_apple = True,
        apple_platform = "ios_device",
        constraints = [_OS_IOS, _CPU_AARCH64, _APPLE_DEVICE],
    ),
    "ios_simulator_arm64": struct(
        is_apple = True,
        apple_platform = "ios_simulator",
        constraints = [_OS_IOS, _CPU_AARCH64, _APPLE_SIMULATOR],
    ),
    "linux_arm64": struct(
        is_apple = False,
        apple_platform = None,
        constraints = [_OS_LINUX, _CPU_AARCH64],
    ),
    "linux_x64": struct(
        is_apple = False,
        apple_platform = None,
        constraints = [_OS_LINUX, _CPU_X86_64],
    ),
    "macos_arm64": struct(
        is_apple = True,
        apple_platform = "macos",
        constraints = [_OS_MACOS, _CPU_AARCH64],
    ),
}

EXEC_HOSTS = {
    "linux-x86_64": struct(
        konan_host = "linux_x64",
        repo_suffix = "linux_x86_64",
        constraints = [_OS_LINUX, _CPU_X86_64],
        targets = ["linux_arm64", "linux_x64"],
    ),
    "macos-aarch64": struct(
        konan_host = "macos_arm64",
        repo_suffix = "macos_aarch64",
        constraints = [_OS_MACOS, _CPU_AARCH64],
        targets = ["ios_arm64", "ios_simulator_arm64", "linux_arm64", "linux_x64", "macos_arm64"],
    ),
}

def konan_platform_constraints(konan_target):
    """The constraint values of the platform of `konan_target`.

    Apple platforms also carry APPLE_VENDOR_CONSTRAINT, like apple_support's own platforms, so they
    select the same Apple toolchains. Toolchains and config_settings match on the target's
    constraints only, so a platform without it still resolves.
    """
    target = KONAN_TARGETS[konan_target]
    return target.constraints + ([APPLE_VENDOR_CONSTRAINT] if target.is_apple else [])

# buildifier: disable=unnamed-macro
def define_konan_platforms():
    """Declares the platform and the config_settings of each konan target, and `native`.

    Per konan target:
    - `<target>`, the platform to pass to `--platforms` to build for the target;
    - `is_<target>`, a config_setting of the constraints of the target: it matches any build for its
      OS and CPU, a JVM one on a host of the target included;
    - `native_<target>`, a config_setting of the constraints of the target and of
      //kotlin/settings:kotlin_platform_type `native`: it matches the Kotlin/Native rules building
      for the target, and their deps, which the rules transition to `native`.

    `native` matches the Kotlin/Native rules and their deps, whatever their target. An alias that
    selects a klib for a Kotlin/Native consumer and a JVM library otherwise selects on
    `native_<target>`.
    """
    native.config_setting(
        name = "native",
        flag_values = {KOTLIN_PLATFORM_TYPE: "native"},
        visibility = ["//visibility:public"],
    )
    for name in KONAN_TARGETS:
        native.platform(
            name = name,
            constraint_values = konan_platform_constraints(name),
            visibility = ["//visibility:public"],
        )
        native.config_setting(
            name = "is_" + name,
            constraint_values = KONAN_TARGETS[name].constraints,
            visibility = ["//visibility:public"],
        )
        native.config_setting(
            name = "native_" + name,
            constraint_values = KONAN_TARGETS[name].constraints,
            flag_values = {KOTLIN_PLATFORM_TYPE: "native"},
            visibility = ["//visibility:public"],
        )
