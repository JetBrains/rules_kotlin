"""Analysis tests for kt_klib_import: the KtKlibInfo of a prebuilt klib, and the klib actions of its consumers.

See common.bzl for the fake toolchains. The klibs of testdata/ are empty placeholders, which analysis
does not read. An import needs no toolchain, so the tests of the imports alone run on every host.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//kotlin:native.bzl", "KtKlibInfo", "kt_klib_import", "kt_native_library")
load(
    ":common.bzl",
    "HOME",
    "PACKAGE",
    "fake_klib",
    "for_target",
    "libraries",
    "not_on_windows",
    "single_action",
    "tool_arguments",
)

_KLIB = PACKAGE + "/testdata/imported.klib"

# The imported klib, its cinterop klib and its export.
_CLOSURE = ["imported-cinterop.klib", "imported.klib", "imported_export_linux_arm64.klib"]

def _basenames(files):
    return sorted([f.basename for f in files])

def _provider_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    info = target[KtKlibInfo]
    asserts.equals(env, _KLIB, info.klib.path)
    asserts.equals(env, [info.klib], target[DefaultInfo].files.to_list())
    asserts.equals(env, "native", info.platform)
    asserts.equals(env, "linux_arm64", info.konan_target)
    asserts.equals(env, "org.example:imported", info.module_name)
    asserts.equals(env, None, info.cc_info)

    # Its export, which its consumers compile against as if they listed it, and the closure of its
    # deps and exports, which they compile against and link.
    asserts.equals(env, ["imported_export_linux_arm64.klib"], _basenames(info.exported_klibs.to_list()))
    asserts.equals(env, _CLOSURE, _basenames(info.transitive_klibs.to_list()))

    # The klib is used as it is.
    asserts.equals(env, [], analysistest.target_actions(env))

    return analysistest.end(env)

def _consumer_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The consumer compiles against the imported klib and the closure of its deps and exports, which
    # are inputs, with the toolchain files of its own konan target only.
    action = single_action(env, "KotlinNativeKlibCompile")
    tool = tool_arguments(action.argv)
    asserts.equals(env, _CLOSURE, sorted([path.rpartition("/")[2] for path in libraries(tool)]))
    asserts.true(env, _KLIB in libraries(tool), "%s should be compiled against as it is: %s" % (_KLIB, tool))
    inputs = [f.path for f in action.inputs.to_list()]
    for library in libraries(tool):
        asserts.true(env, library in inputs, "%s should be an input" % library)
    for path in inputs:
        asserts.false(
            env,
            path.startswith(HOME + "/klib/platform/") and not path.startswith(HOME + "/klib/platform/linux_arm64/"),
            "%s should not be an input" % path,
        )

    return analysistest.end(env)

def _target_mismatch_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(env, "imported_linux_x64 is for target linux_x64, but this target is linux_arm64")

    return analysistest.end(env)

provider_test = analysistest.make(_provider_test_impl)
consumer_test = analysistest.make(_consumer_test_impl, config_settings = for_target("linux_arm64"))
consumer_target_mismatch_test = analysistest.make(
    _target_mismatch_test_impl,
    config_settings = for_target("linux_arm64"),
    expect_failure = True,
)
import_target_mismatch_test = analysistest.make(_target_mismatch_test_impl, expect_failure = True)

def native_import_test_suite(name):
    """Declares the imports under test, their consumers and the analysis tests of kt_klib_import.

    The fake toolchains (common.bzl: define_fake_toolchains) must be declared in the package.

    Args:
      name: the name of the generated test_suite target.
    """

    # imported: deps = [its cinterop klib], exports = [a klib of the same target].
    kt_klib_import(
        name = "imported_cinterop_linux_arm64",
        klib = "testdata/imported-cinterop.klib",
        konan_target = "linux_arm64",
        tags = ["manual"],
    )
    fake_klib(
        name = "imported_export_linux_arm64",
        konan_target = "linux_arm64",
        tags = ["manual"],
    )
    kt_klib_import(
        name = "imported_linux_arm64",
        klib = "testdata/imported.klib",
        konan_target = "linux_arm64",
        module_name = "org.example:imported",
        tags = ["manual"],
        exports = [":imported_export_linux_arm64"],
        deps = [":imported_cinterop_linux_arm64"],
    )
    kt_native_library(
        name = "import_consumer_linux_arm64",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
        deps = [":imported_linux_arm64"],
    )

    # The same klib imported for another konan target, for a consumer and in an import.
    kt_klib_import(
        name = "imported_linux_x64",
        klib = "testdata/imported.klib",
        konan_target = "linux_x64",
        tags = ["manual"],
    )
    kt_native_library(
        name = "import_mismatched_consumer_linux_arm64",
        srcs = ["testdata/greeter.kt"],
        tags = ["manual"],
        deps = [":imported_linux_x64"],
    )
    kt_klib_import(
        name = "import_mismatched_dep_linux_arm64",
        klib = "testdata/imported.klib",
        konan_target = "linux_arm64",
        tags = ["manual"],
        deps = [":imported_linux_x64"],
    )

    provider_test(
        name = "import_provider_test",
        target_under_test = ":imported_linux_arm64",
    )
    consumer_test(
        name = "import_consumer_test",
        target_under_test = ":import_consumer_linux_arm64",
        target_compatible_with = not_on_windows(),
    )
    consumer_target_mismatch_test(
        name = "import_consumer_target_mismatch_test",
        target_under_test = ":import_mismatched_consumer_linux_arm64",
        target_compatible_with = not_on_windows(),
    )
    import_target_mismatch_test(
        name = "import_dep_target_mismatch_test",
        target_under_test = ":import_mismatched_dep_linux_arm64",
    )

    native.test_suite(
        name = name,
        tests = [
            ":import_consumer_target_mismatch_test",
            ":import_consumer_test",
            ":import_dep_target_mismatch_test",
            ":import_provider_test",
        ],
    )
