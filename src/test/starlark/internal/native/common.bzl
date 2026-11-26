"""Fixtures and helpers of the analysis tests of the Kotlin/Native rules.

Fake toolchains over the trees of testdata/ stand in for the distribution and link bundle
repositories of a linux_arm64 host building for linux_arm64 and ios_simulator_arm64, whose bundle
stages them, and macos_arm64, whose bundle does not. A test transitions to the platform of a konan
target and adds the fake toolchain of that target (see for_target). The two jars of
testdata/btapi_runtime stand in for the Build Tools API runtime repository of the release, and
fake_linux_arm64_without_btapi_toolchain is the linux_arm64 one of a release without a runtime.

fake_ios_simulator_arm64_cc_toolchain stands in for the C++ toolchain apple_support registers on a
Mac: it compiles Objective-C, which kt_native_xctest_library needs, on any host (see
with_fake_cc_toolchain).
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load(
    "@rules_cc//cc:cc_toolchain_config_lib.bzl",
    "action_config",
    "feature",
    "feature_set",
    "flag_group",
    "flag_set",
    "tool",
    "tool_path",
)
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/toolchains:cc_toolchain.bzl", "cc_toolchain")
load("@rules_cc//cc/toolchains:cc_toolchain_config_info.bzl", "CcToolchainConfigInfo")
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

# The jars of the fake Build Tools API runtime, in the order of the toolchain's btapi_classpath.
BTAPI_RUNTIME = [
    PACKAGE + "/testdata/btapi_runtime/kotlin-build-tools-impl.jar",
    PACKAGE + "/testdata/btapi_runtime/kotlin-daemon-client.jar",
]

# The konan target of the exec host of the fake toolchains.
FAKE_HOST = "linux_arm64"

# The Objective-C compiler of the fake C++ toolchain, by which a test tells its actions.
FAKE_OBJC_COMPILER = "fake_objc_compiler"

# The features with which the fake C++ toolchain instruments an Objective-C compilation of a
# coverage build, and the flag of each: those of the toolchains of apple_support, of which Bazel
# requests the one of the coverage format of the build.
FAKE_COVERAGE_FLAGS = {
    "gcc_coverage_map_format": "-ftest-coverage",
    "llvm_coverage_map_format": "-fprofile-instr-generate",
}

def for_target(konan_target):
    """The config_settings building the target under test for a konan target, with its fake toolchain."""
    return {
        "//command_line_option:extra_toolchains": [str(Label("//%s:fake_%s_toolchain" % (PACKAGE, konan_target)))],
        "//command_line_option:platforms": [str(Label("//kotlin/native/platforms:" + konan_target))],
    }

def with_fake_cc_toolchain(config_settings):
    """`config_settings` of for_target("ios_simulator_arm64") with the fake C++ toolchain of that target ahead of the host's."""
    settings = dict(config_settings)
    settings["//command_line_option:extra_toolchains"] = [
        str(Label("//%s:fake_ios_simulator_arm64_cc_toolchain" % PACKAGE)),
    ] + settings["//command_line_option:extra_toolchains"]
    return settings

def with_header_klibs(config_settings):
    """`config_settings` with the build setting experimental_native_header_klibs on."""
    settings = dict(config_settings)
    settings[str(Label("//kotlin/settings:experimental_native_header_klibs"))] = True
    return settings

def with_native_btapi(config_settings, enabled):
    """`config_settings` with the build setting experimental_native_build_tools_api on or off."""
    settings = dict(config_settings)
    settings[str(Label("//kotlin/settings:experimental_native_build_tools_api"))] = enabled
    return settings

# The attributes of a test whose rule runs with header klibs on (see with_header_klibs) or off.
HEADER_KLIBS_ATTRS = {
    "header_klibs": attr.bool(),
}

def compile_klib_of(klib, header_klibs):
    """The path or basename of the klib a compilation reads for `klib`: with header klibs, the header klib beside it."""
    return klib[:-len(".klib")] + ".header.klib" if header_klibs else klib

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

def launcher_values(argv, flag):
    """The values of every occurrence of a KonanLauncher flag, e.g. --source, in order."""
    launcher = launcher_arguments(argv)
    return [launcher[i + 1] for i in range(len(launcher)) if launcher[i] == flag]

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
            compile_klib = klib,
            exported_klibs = depset(),
            klib = klib,
            konan_target = ctx.attr.konan_target,
            transitive_compile_klibs = depset([klib]),
            transitive_klibs = depset([klib]),
        ),
    ]

fake_klib = rule(
    doc = "A klib that is not compiled: a stand-in for one of another konan target.",
    implementation = _fake_klib_impl,
    attrs = {
        "konan_target": attr.string(mandatory = True),
    },
    provides = [KtKlibInfo],
)

def _fake_cc_toolchain_config_impl(ctx):
    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        toolchain_identifier = "fake-objc",
        compiler = "clang",
        action_configs = [action_config(
            action_name = ACTION_NAMES.objc_compile,
            enabled = True,
            tools = [tool(path = FAKE_OBJC_COMPILER)],
        )],
        features = [feature(name = "coverage")] + [
            feature(
                name = name,
                flag_sets = [flag_set(
                    actions = [ACTION_NAMES.objc_compile],
                    flag_groups = [flag_group(flags = [flag])],
                )],
                requires = [feature_set(features = ["coverage"])],
            )
            for name, flag in FAKE_COVERAGE_FLAGS.items()
        ],
        tool_paths = [
            tool_path(name = name, path = "fake_" + name)
            for name in ["ar", "cpp", "gcc", "gcov", "ld", "nm", "objdump", "strip"]
        ],
    )

fake_cc_toolchain_config = rule(
    doc = "The configuration of a C++ toolchain that only registers actions: it has an Objective-C compile action, which its coverage features instrument, and no tools.",
    implementation = _fake_cc_toolchain_config_impl,
    provides = [CcToolchainConfigInfo],
)

def _define_fake_toolchain(name, target, btapi_runtime):
    define_kt_native_toolchain(
        name = name,
        konan_target = target,
        konan_host = FAKE_HOST,
        konan_home = "//%s/testdata/konan_home:home" % PACKAGE,
        konan = "//%s/testdata/konan_home:konan" % PACKAGE,
        stdlib = "//%s/testdata/konan_home:stdlib" % PACKAGE,
        platform_libs = "//%s/testdata/konan_home:platform_%s" % (PACKAGE, target),
        konan_deps = "//%s/testdata/konan_deps:%s" % (PACKAGE, target),
        btapi_runtime = btapi_runtime,
        exec_compatible_with = [],
        target_compatible_with = KONAN_TARGETS[target].constraints,
    )

# buildifier: disable=unnamed-macro
def define_fake_toolchains():
    """Declares fake_<target>_toolchain for ios_simulator_arm64, linux_arm64 and macos_arm64, over the trees of testdata/.

    Also declares fake_linux_arm64_without_btapi_toolchain, of a release without a Build Tools API runtime, and
    fake_ios_simulator_arm64_cc_toolchain, a C++ toolchain for ios_simulator_arm64.
    """
    native.filegroup(
        name = "fake_btapi_runtime",
        srcs = [path[len(PACKAGE) + 1:] for path in BTAPI_RUNTIME],
    )
    native.filegroup(name = "fake_empty_btapi_runtime")
    for target in ["ios_simulator_arm64", "linux_arm64", "macos_arm64"]:
        _define_fake_toolchain("fake_%s_toolchain" % target, target, ":fake_btapi_runtime")
    _define_fake_toolchain("fake_linux_arm64_without_btapi_toolchain", "linux_arm64", ":fake_empty_btapi_runtime")

    native.filegroup(name = "fake_cc_toolchain_files")
    fake_cc_toolchain_config(name = "fake_cc_toolchain_config")
    cc_toolchain(
        name = "fake_cc_toolchain",
        all_files = ":fake_cc_toolchain_files",
        compiler_files = ":fake_cc_toolchain_files",
        dwp_files = ":fake_cc_toolchain_files",
        linker_files = ":fake_cc_toolchain_files",
        objcopy_files = ":fake_cc_toolchain_files",
        strip_files = ":fake_cc_toolchain_files",
        toolchain_config = ":fake_cc_toolchain_config",
    )
    native.toolchain(
        name = "fake_ios_simulator_arm64_cc_toolchain",
        target_compatible_with = KONAN_TARGETS["ios_simulator_arm64"].constraints,
        toolchain = ":fake_cc_toolchain",
        toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
    )
