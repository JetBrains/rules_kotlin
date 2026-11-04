"""Analysis tests for the Kotlin/Native toolchain and the inputs and arguments of its actions.

Fake toolchains over the trees of testdata/ stand in for the distribution and link bundle
repositories of a host building for linux_arm64, whose bundle stages it, and macos_arm64,
whose bundle does not.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//kotlin:native.bzl", "KtNativeInfo", "kt_native_binary", "kt_native_library")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/native:targets.bzl", "KONAN_TARGETS")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/native:toolchains.bzl", "define_kt_native_toolchain")

_PACKAGE = "src/test/starlark/internal/native"
_HOME = _PACKAGE + "/testdata/konan_home"
_DEPS = _PACKAGE + "/testdata/konan_deps"
_DEP_NAMES = ["gcc-fixture", "libffi-fixture", "llvm-fixture"]
_AIRPLANE_MODE = "-Xoverride-konan-properties=airplaneMode=true"

def _for_target(konan_target):
    """Builds the target under test for a konan target, with the fake toolchain of that target."""
    return {
        "//command_line_option:extra_toolchains": [str(Label("//%s:fake_%s_toolchain" % (_PACKAGE, konan_target)))],
        "//command_line_option:platforms": [str(Label("//kotlin/native/platforms:" + konan_target))],
    }

def _action(env, mnemonic):
    actions = [action for action in analysistest.target_actions(env) if action.mnemonic == mnemonic]
    asserts.equals(env, 1, len(actions), "%s actions" % mnemonic)
    return actions[0]

def _argument_after(argv, flag):
    return argv[argv.index(flag) + 1]

def _toolchain_info_test_impl(ctx):
    env = analysistest.begin(ctx)

    info = analysistest.target_under_test(env)[platform_common.ToolchainInfo]
    asserts.equals(env, "linux_arm64", info.konan_target)
    asserts.false(env, info.is_apple)
    asserts.equals(env, _HOME, info.konan_home.path)
    asserts.equals(env, _HOME + "/konan", info.konan.path)
    asserts.equals(env, _HOME + "/klib/common/stdlib", info.stdlib.path)
    asserts.equals(env, _HOME + "/klib/platform/linux_arm64", info.platform_libs.path)

    # Only what klib compilation for linux_arm64 reads: no other target, no bin/, no klib/cache.
    asserts.equals(
        env,
        [
            _HOME + "/klib/common/stdlib/default/manifest",
            _HOME + "/klib/platform/linux_arm64/posix/default/manifest",
            _HOME + "/konan/konan.properties",
            _HOME + "/konan/lib/kotlin-native-compiler-embeddable.jar",
        ],
        sorted([f.path for f in info.compile_inputs.to_list()]),
    )

    asserts.true(env, info.konan_deps.staged)
    asserts.equals(env, "linux_arm64", info.konan_deps.konan_target)
    asserts.equals(env, _DEP_NAMES, info.konan_deps.names)
    asserts.equals(env, [_DEPS + "/dependencies/" + name for name in _DEP_NAMES], [d.path for d in info.konan_deps.dirs])
    asserts.equals(env, 3, len(info.konan_deps.files.to_list()))

    return analysistest.end(env)

def _unstaged_toolchain_info_test_impl(ctx):
    env = analysistest.begin(ctx)

    info = analysistest.target_under_test(env)[platform_common.ToolchainInfo]
    asserts.equals(env, "macos_arm64", info.konan_target)
    asserts.true(env, info.is_apple)
    asserts.false(env, info.konan_deps.staged)
    asserts.equals(env, [], info.konan_deps.dirs)
    asserts.equals(env, [], info.konan_deps.files.to_list())

    return analysistest.end(env)

def _klib_compile_test_impl(ctx):
    env = analysistest.begin(ctx)

    action = _action(env, "KotlinNativeKlibCompile")
    target = ctx.attr.konan_target
    inputs = [f.path for f in action.inputs.to_list()]
    for expected in [
        _HOME + "/konan/lib/kotlin-native-compiler-embeddable.jar",
        _HOME + "/klib/common/stdlib/default/manifest",
        _HOME + "/klib/platform/%s/posix/default/manifest" % target,
    ]:
        asserts.true(env, expected in inputs, "%s should be an input" % expected)
    for path in inputs:
        for excluded in [
            _HOME + "/klib/platform/" + ctx.attr.other_target + "/",
            _HOME + "/klib/cache/",
            _HOME + "/bin/",
            _DEPS + "/",
        ]:
            asserts.false(env, path.startswith(excluded), "%s should not be an input" % path)

    # The launcher gets the in-sandbox konan home first.
    argv = action.argv
    asserts.equals(env, _HOME, argv[1])
    asserts.equals(env, "library", _argument_after(argv, "-produce"))
    asserts.equals(env, target, _argument_after(argv, "-target"))
    asserts.true(env, _AIRPLANE_MODE in argv, "%s should be in %s" % (_AIRPLANE_MODE, argv))

    return analysistest.end(env)

def _link_test_impl(ctx):
    env = analysistest.begin(ctx)

    action = _action(env, "KotlinNativeLink")
    inputs = [f.path for f in action.inputs.to_list()]
    for name in _DEP_NAMES:
        asserts.true(
            env,
            len([path for path in inputs if path.startswith(_DEPS + "/dependencies/" + name + "/")]) == 1,
            "the files of %s should be inputs" % name,
        )
    asserts.true(env, _HOME + "/klib/platform/linux_arm64/posix/default/manifest" in inputs)
    asserts.false(env, _HOME + "/klib/platform/macos_arm64/posix/default/manifest" in inputs)

    # konan home, scratch dirs, then the count and paths of the dependency dirs to stage.
    argv = action.argv
    asserts.equals(
        env,
        [_HOME, "hello_linux_arm64.konan_data", "hello_linux_arm64.autocache", "3"] +
        [_DEPS + "/dependencies/" + name for name in _DEP_NAMES],
        argv[1:8],
    )
    asserts.equals(env, "program", _argument_after(argv, "-produce"))
    asserts.equals(env, "linux_arm64", _argument_after(argv, "-target"))
    asserts.true(env, _AIRPLANE_MODE in argv, "%s should be in %s" % (_AIRPLANE_MODE, argv))

    return analysistest.end(env)

def _unstaged_link_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(env, "the Kotlin/Native link dependencies of macos_arm64 are not staged")
    asserts.expect_failure(env, "add 'macos_arm64' to kotlin_native.targets(...)")

    return analysistest.end(env)

def _klib_target_mismatch_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(env, "is for target linux_x64, but this target is linux_arm64")

    return analysistest.end(env)

_TARGET_ATTRS = {
    "konan_target": attr.string(),
    "other_target": attr.string(),
}

toolchain_info_test = analysistest.make(_toolchain_info_test_impl)
unstaged_toolchain_info_test = analysistest.make(_unstaged_toolchain_info_test_impl)
klib_compile_linux_arm64_test = analysistest.make(
    _klib_compile_test_impl,
    attrs = _TARGET_ATTRS,
    config_settings = _for_target("linux_arm64"),
)
klib_compile_macos_arm64_test = analysistest.make(
    _klib_compile_test_impl,
    attrs = _TARGET_ATTRS,
    config_settings = _for_target("macos_arm64"),
)
link_test = analysistest.make(_link_test_impl, config_settings = _for_target("linux_arm64"))
unstaged_link_test = analysistest.make(
    _unstaged_link_test_impl,
    config_settings = _for_target("macos_arm64"),
    expect_failure = True,
)
klib_target_mismatch_test = analysistest.make(
    _klib_target_mismatch_test_impl,
    config_settings = _for_target("linux_arm64"),
    expect_failure = True,
)

def _fake_klib_impl(ctx):
    klib = ctx.actions.declare_file(ctx.label.name + ".klib")
    ctx.actions.write(klib, "")
    return [
        DefaultInfo(files = depset([klib])),
        KtNativeInfo(
            klib = klib,
            konan_target = ctx.attr.konan_target,
            module_name = ctx.label.name,
            transitive_klibs = depset([klib]),
        ),
    ]

_fake_klib = rule(
    implementation = _fake_klib_impl,
    attrs = {"konan_target": attr.string(mandatory = True)},
    provides = [KtNativeInfo],
)

def native_toolchain_test_suite(name):
    """Declares the fake toolchains, the targets under test and the analysis tests.

    The tests transition to the platform of a konan target and run on Linux and macOS only, as
    the launchers of the rules are bash scripts.

    Args:
      name: the name of the generated test_suite target.
    """
    not_on_windows = select({
        "@platforms//os:windows": ["@platforms//:incompatible"],
        "//conditions:default": [],
    })

    for target in ["linux_arm64", "macos_arm64"]:
        define_kt_native_toolchain(
            name = "fake_%s_toolchain" % target,
            konan_target = target,
            konan_home = "//%s/testdata/konan_home:home" % _PACKAGE,
            konan = "//%s/testdata/konan_home:konan" % _PACKAGE,
            stdlib = "//%s/testdata/konan_home:stdlib" % _PACKAGE,
            platform_libs = "//%s/testdata/konan_home:platform_%s" % (_PACKAGE, target),
            konan_deps = "//%s/testdata/konan_deps:%s" % (_PACKAGE, target),
            exec_compatible_with = [],
            target_compatible_with = KONAN_TARGETS[target].constraints,
        )
        kt_native_library(
            name = "greeter_" + target,
            srcs = ["testdata/greeter.kt"],
            tags = ["manual"],
        )
        kt_native_binary(
            name = "hello_" + target,
            srcs = ["testdata/main.kt"],
            tags = ["manual"],
            deps = [":greeter_" + target],
        )

    _fake_klib(
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

    toolchain_info_test(
        name = "toolchain_info_test",
        target_under_test = ":fake_linux_arm64_toolchain_impl",
        target_compatible_with = not_on_windows,
    )
    unstaged_toolchain_info_test(
        name = "unstaged_toolchain_info_test",
        target_under_test = ":fake_macos_arm64_toolchain_impl",
        target_compatible_with = not_on_windows,
    )
    klib_compile_linux_arm64_test(
        name = "klib_compile_inputs_test",
        target_under_test = ":greeter_linux_arm64",
        konan_target = "linux_arm64",
        other_target = "macos_arm64",
        target_compatible_with = not_on_windows,
    )

    # klibs compile for a target its bundle does not stage.
    klib_compile_macos_arm64_test(
        name = "unstaged_klib_compile_inputs_test",
        target_under_test = ":greeter_macos_arm64",
        konan_target = "macos_arm64",
        other_target = "linux_arm64",
        target_compatible_with = not_on_windows,
    )
    link_test(
        name = "link_inputs_test",
        target_under_test = ":hello_linux_arm64",
        target_compatible_with = not_on_windows,
    )
    unstaged_link_test(
        name = "unstaged_link_fails_test",
        target_under_test = ":hello_macos_arm64",
        target_compatible_with = not_on_windows,
    )
    klib_target_mismatch_test(
        name = "klib_target_mismatch_test",
        target_under_test = ":mismatched_linux_arm64",
        target_compatible_with = not_on_windows,
    )

    native.test_suite(
        name = name,
        tests = [
            ":klib_compile_inputs_test",
            ":klib_target_mismatch_test",
            ":link_inputs_test",
            ":toolchain_info_test",
            ":unstaged_klib_compile_inputs_test",
            ":unstaged_link_fails_test",
            ":unstaged_toolchain_info_test",
        ],
    )
