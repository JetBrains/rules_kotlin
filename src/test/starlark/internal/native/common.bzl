"""Fixtures and helpers of the analysis tests of the Kotlin/Native rules.

Fake toolchains over the trees of testdata/ stand in for the distribution and link bundle
repositories of a linux_arm64 host building for linux_arm64 and ios_simulator_arm64, whose bundle
stages them, and macos_arm64, whose bundle does not. A test transitions to the platform of a konan
target and adds the fake toolchain of that target (see for_target).
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//kotlin:native.bzl", "KtKlibInfo")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/native:targets.bzl", "KONAN_TARGETS")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/native:toolchains.bzl", "define_kt_native_toolchain")

PACKAGE = "src/test/starlark/internal/native"
HOME = PACKAGE + "/testdata/konan_home"
DEPS = PACKAGE + "/testdata/konan_deps"
DEP_NAMES = ["gcc-fixture", "libffi-fixture", "llvm-fixture"]
AIRPLANE_MODE = "-Xoverride-konan-properties=airplaneMode=true"
NO_LIGHT_DEBUG = "-Xadd-light-debug=disable"

# The konan target of the exec host of the fake toolchains.
FAKE_HOST = "linux_arm64"

def for_target(konan_target):
    """The config_settings building the target under test for a konan target, with its fake toolchain."""
    return {
        "//command_line_option:extra_toolchains": [str(Label("//%s:fake_%s_toolchain" % (PACKAGE, konan_target)))],
        "//command_line_option:platforms": [str(Label("//kotlin/native/platforms:" + konan_target))],
    }

def not_on_windows():
    """target_compatible_with of the tests: Kotlin/Native has no Windows exec host."""
    return select({
        "@platforms//os:windows": ["@platforms//:incompatible"],
        "//conditions:default": [],
    })

def single_action(env, mnemonic):
    """The one action of the target under test with `mnemonic`."""
    actions = [action for action in analysistest.target_actions(env) if action.mnemonic == mnemonic]
    asserts.equals(env, 1, len(actions), "%s actions" % mnemonic)
    return actions[0]

def argument_after(argv, flag):
    return argv[argv.index(flag) + 1]

def launcher_arguments(argv):
    """The arguments KonanLauncher takes itself: those between its executable and `--`."""
    return argv[1:argv.index("--")]

def tool_arguments(argv):
    """The arguments KonanLauncher passes to the tool: those after `--`."""
    return argv[argv.index("--") + 1:]

def libraries(tool):
    """The paths konanc gets with -l, in order."""
    return [tool[i + 1] for i in range(len(tool)) if tool[i] == "-l"]

def prefixed(tool, prefix):
    """The values of the arguments of the form <prefix><value>, in order."""
    return [arg[len(prefix):] for arg in tool if arg.startswith(prefix)]

def _fake_klib_impl(ctx):
    klib = ctx.actions.declare_file(ctx.label.name + ".klib")
    ctx.actions.write(klib, "")
    return [
        DefaultInfo(files = depset([klib])),
        KtKlibInfo(
            cc_info = None,
            exported_klibs = depset(),
            klib = klib,
            konan_target = ctx.attr.konan_target or None,
            module_name = ctx.label.name,
            platform = ctx.attr.platform,
            transitive_klibs = depset([klib]),
        ),
    ]

fake_klib = rule(
    doc = "A klib that is not compiled: a stand-in for one of another konan target or platform.",
    implementation = _fake_klib_impl,
    attrs = {
        "konan_target": attr.string(),
        "platform": attr.string(default = "native"),
    },
    provides = [KtKlibInfo],
)

# buildifier: disable=unnamed-macro
def define_fake_toolchains():
    """Declares fake_<target>_toolchain for ios_simulator_arm64, linux_arm64 and macos_arm64, over the trees of testdata/."""
    for target in ["ios_simulator_arm64", "linux_arm64", "macos_arm64"]:
        define_kt_native_toolchain(
            name = "fake_%s_toolchain" % target,
            konan_target = target,
            konan_host = FAKE_HOST,
            konan_home = "//%s/testdata/konan_home:home" % PACKAGE,
            konan = "//%s/testdata/konan_home:konan" % PACKAGE,
            stdlib = "//%s/testdata/konan_home:stdlib" % PACKAGE,
            platform_libs = "//%s/testdata/konan_home:platform_%s" % (PACKAGE, target),
            konan_deps = "//%s/testdata/konan_deps:%s" % (PACKAGE, target),
            exec_compatible_with = [],
            target_compatible_with = KONAN_TARGETS[target].constraints,
        )
