"""kt_native_xctest_library: links Kotlin/Native tests into a library that an Apple test bundle runs.

The srcs compile into a private klib, as for kt_native_test, with XCTestLauncher.kt, which gives the
test runner konanc generates a C name. The link includes the klib in a static library,
`_kt_native/<name>/lib<package>_<name>.a` (see link.bzl): the tests, the klibs of the deps and the
Kotlin/Native runtime. The rule compiles XCTestShim.m, an XCTestCase whose test method calls the
launcher, with the Objective-C compiler of the C++ toolchain, and provides both in a CcInfo:
rules_apple's ios_unit_test links its `deps` into the test bundle, where XCTest finds the test case
and the Kotlin tests run in the process of the test.

Only the test case is alwayslink. The static library links as konanc links a binary, an object file
when something refers to it: konanc puts the static libraries that the klibs embed into it, e.g.
those of Skia in a klib of Compose Multiplatform, some of them several times, and loading every
object file of it gives duplicate symbols. The Kotlin code is one object file of the library, with
the launcher, so the call of the test case loads the tests.

One test bundle links several of these libraries, so every global symbol of a library has the
package and the name of its target (see _identifier): both sources are templates, for the names of
the launcher and of the test case, and the static library is named with them, as konanc names the
symbols it exports after its output, e.g. the Objective-C classes `Lib<package>_<name>Base`. The
library is in a directory of the name of the target, so that targets of one package whose
identifiers are equal, `a.b` and `a_b`, declare different files; they only fail to link when one
test bundle takes both, with duplicate symbols.

cc_common.compile skips an Objective-C source unless it gets `language = "objc"`: it then registers
the objc-compile action of the toolchain (seen on Bazel 7.7.3, 8.9.0 and 9.3.2 with the toolchains
of apple_support).
"""

load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//kotlin/internal/kmp:fragment.bzl", "KtFragmentInfo")
load("//kotlin/internal/kmp:fragments.bzl", "collect_fragments")
load(":link.bzl", "LINK_ATTRS", "link_native")
load(":providers.bzl", "KtKlibInfo")
load(":targets.bzl", "KONAN_TARGETS")
load(":toolchains.bzl", "KT_NATIVE_TOOLCHAIN_TYPE")
load(":transition.bzl", "kt_native_transition")

# What konanc links an Apple binary with (linkerKonanFlags of konan.properties): the Kotlin/Native
# runtime is C++ and Objective-C. The linker of the test bundle is not konanc, so the flags travel
# with the library. Each is one argument: Bazel keeps one of two equal link flags.
_RUNTIME_LINK_FLAGS = ["-lc++", "-lobjc", "-Wl,-framework,Foundation"]
_IOS_RUNTIME_LINK_FLAGS = ["-Wl,-framework,UIKit"]

# The feature with which a C++ toolchain instruments what it compiles in the gcov format, the
# default one of a coverage build, of any target. The object file of the XCTest case then needs the
# gcov runtime, which the link of a test bundle does not get from the toolchains of apple_support:
# the bundle would fail to link, with the symbols of that runtime undefined. It gets the runtime of
# the LLVM format (--experimental_use_llvm_covmap), in which the test case stays instrumented, so
# that the process of the test writes the profile the runner of rules_apple reads.
_UNLINKABLE_COVERAGE_FEATURES = ["gcc_coverage_map_format"]

def _identifier(label):
    """What the global symbols of the library of a label are named with.

    It is the package and the name of the label with `_` for every character a C identifier cannot
    have, as rules_swift derives a module name: readable in the test log, and unique but for labels
    that only differ in such characters.
    """
    path = label.package + "/" + label.name if label.package else label.name
    return "".join([c if c.isalnum() else "_" for c in path.elems()])

def _names(label):
    """The substitutions of XCTestLauncher.kt and XCTestShim.m: their names, each with the identifier of the label."""
    return {name: name + "_" + _identifier(label) for name in ["KotlinNativeTests", "rules_kotlin_xctest_run"]}

def _expand(ctx, template):
    """Registers the action writing a source of the rules with the names of this target, and returns the File."""
    output = ctx.actions.declare_file("_kt_native/%s_%s" % (ctx.label.name, template.basename))
    ctx.actions.expand_template(
        template = template,
        output = output,
        substitutions = _names(ctx.label),
    )
    return output

def _compile_test_case(ctx, cc_toolchain, feature_configuration):
    """Registers the action compiling XCTestShim.m, and returns its compilation outputs."""
    if not cc_common.action_is_enabled(feature_configuration = feature_configuration, action_name = ACTION_NAMES.objc_compile):
        fail(("%s: the C++ toolchain of this target, %s, compiles no Objective-C, which the XCTest case of " +
              "kt_native_xctest_library is written in; build it with the toolchains of apple_support") %
             (ctx.label, cc_toolchain.toolchain_id))
    _, compilation_outputs = cc_common.compile(
        name = ctx.label.name,
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        srcs = [_expand(ctx, ctx.file._test_case)],
        language = "objc",
    )
    return compilation_outputs

def _kt_native_xctest_library_impl(ctx):
    tc = ctx.toolchains[KT_NATIVE_TOOLCHAIN_TYPE]
    if not tc.is_apple:
        fail(("%s: kt_native_xctest_library builds for the test bundles of Apple platforms, but this target is %s; " +
              "set target_compatible_with to skip it") % (ctx.label, tc.konan_target))
    launcher = _expand(ctx, ctx.file._launcher)
    fragments = collect_fragments(ctx, ctx.attr.kmp_fragments, tc.konan_target, ctx.files.srcs + [launcher])
    if fragments.srcs == [launcher]:
        fail(("%s: kt_native_xctest_library has no sources, in its srcs or its kmp_fragments; " +
              "the test bundle only runs the tests of its own sources") % ctx.label)

    # The toolchain is optional: Bazel resolves toolchains before this function runs, so a mandatory
    # one would replace the messages above with a resolution error where the platform has none.
    cc_toolchain = find_cc_toolchain(ctx, mandatory = False)
    if not cc_toolchain:
        fail(("%s: no C++ toolchain is registered for this target, %s, and kt_native_xctest_library compiles " +
              "its XCTest case with one; build it on a Mac, with the toolchains of apple_support, or set " +
              "target_compatible_with to skip it") % (ctx.label, tc.konan_target))

    # konanc names a static library lib<name>.a, writes its C header next to it, and exports symbols
    # named after it, so the basename is the identifier of the label, not the name of the target.
    # The directory is the name of the target, which is unique in the package: two names that
    # have the same identifier, `a.b` and `a_b`, do not declare the same files.
    stem = "_kt_native/%s/lib%s" % (ctx.label.name, _identifier(ctx.label))
    library = ctx.actions.declare_file(stem + ".a")
    link_native(
        ctx,
        produce = "static",
        output = library,
        extra_outputs = [ctx.actions.declare_file(stem + "_api.h")],
        extra_deps = ctx.attr.associates,
        friends = [associate[KtKlibInfo].compile_klib for associate in ctx.attr.associates],
        extra_args = ["-generate-test-runner"],
        fragments = fragments,
        progress_message = "Linking Kotlin/Native tests %{label} (" + tc.konan_target + ")",
    )

    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features + _UNLINKABLE_COVERAGE_FEATURES,
    )
    test_case = _compile_test_case(ctx, cc_toolchain, feature_configuration)

    # alwayslink: nothing refers to the XCTestCase class, which XCTest finds at run time. The static
    # library is not: the launcher that the test case calls is in the one object file of the Kotlin
    # code, with the tests and their initializers, and the other object files are of the static
    # libraries the klibs embed, which repeat symbols and only link when one refers to them.
    test_case_linking_context, _ = cc_common.create_linking_context_from_compilation_outputs(
        name = ctx.label.name,
        actions = ctx.actions,
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
        compilation_outputs = test_case,
        alwayslink = True,
        disallow_dynamic_library = True,
    )
    link_flags = list(_RUNTIME_LINK_FLAGS)
    if KONAN_TARGETS[tc.konan_target].apple_platform.startswith("ios"):
        link_flags.extend(_IOS_RUNTIME_LINK_FLAGS)
    tests_linking_context = cc_common.create_linking_context(
        linker_inputs = depset([cc_common.create_linker_input(
            owner = ctx.label,
            libraries = depset([cc_common.create_library_to_link(
                actions = ctx.actions,
                feature_configuration = feature_configuration,
                cc_toolchain = cc_toolchain,
                static_library = library,
            )]),
            user_link_flags = link_flags,
        )]),
    )
    return [
        DefaultInfo(files = depset([library])),
        CcInfo(linking_context = cc_common.merge_linking_contexts(
            linking_contexts = [test_case_linking_context, tests_linking_context],
        )),
    ]

kt_native_xctest_library = rule(
    doc = """Links the tests of the srcs into a static library that the test bundle of an Apple platform runs.

    Experimental. The tests use kotlin.test, e.g. `@kotlin.test.Test`, like those of `kt_native_test`, which runs the
    tests of the exec host; this rule is for the tests of a platform a test bundle runs on, e.g. the iOS simulator. It
    provides a `CcInfo` with the tests, the klibs of the deps, the Kotlin/Native runtime and an XCTest case,
    `KotlinNativeTests_<package>_<name>`, whose one test method runs the Kotlin tests in the process of the test and
    fails when one of them fails; the output of the Kotlin test runner, with the name and the result of every test, is
    in the test log. rules_apple's `ios_unit_test` takes it in `deps` and builds it for the platform of the test
    (`--ios_multi_cpus`; by default, on an arm64 Mac, the iOS simulator), so the test needs no `--platforms`:

    ```bzl
    load("@rules_apple//apple:ios.bzl", "ios_unit_test")
    load("@rules_kotlin//kotlin:native.bzl", "kt_native_xctest_library")

    kt_native_xctest_library(
        name = "greeter_test_lib",
        testonly = True,
        srcs = ["GreeterTest.kt"],
        associates = [":greeter"],
        # A build of //... for the host skips it; the test builds it for iOS.
        target_compatible_with = ["@platforms//os:ios"],
    )

    ios_unit_test(
        name = "greeter_test",
        minimum_os_version = "15.0",
        deps = [":greeter_test_lib"],
    )
    ```

    The link dependencies of the target must be staged: see kotlin_native.targets(...). A test bundle takes several
    of these libraries, also ones of the same name in different packages: the test case and the other symbols a
    library exports are named after its package and name, with `_` for every character that is not a letter or a
    digit, so only two libraries whose labels differ in such characters alone, e.g. `//a:b_c` and `//a/b:c`, fail to
    link in one bundle, with duplicate symbols. Each links its own copy of the Kotlin/Native runtime and of the klibs
    of its deps, so they share no Kotlin state. The test bundle links the static library like any other one, the
    object files that something refers to, and only the XCTest case whole; a native library that a klib refers to,
    e.g. an Objective-C or Swift SDK, is a dep of the test next to this library, `ios_unit_test(deps = [...])`, with
    `linkopts = ["-ObjC"]` when the Objective-C categories of a static library have to load. XCTest sees the one
    test case of a library, not the Kotlin tests, and the Kotlin test runner gets no options, e.g. no
    `--ktest_filter`: it runs every test. Kotlin/Native compiles for the iOS version `minVersion.ios` of its
    `konan.properties`; with a lower `minimum_os_version`, the test bundle links with the warning that an object file
    was built for a newer version. Kotlin/Native code is not instrumented: in a build of `bazel coverage`, the test
    of a bundle with Kotlin tests alone sets `collect_code_coverage = False`, or the build
    `--experimental_use_llvm_covmap`, as the runner of rules_apple fails a test whose process wrote no profile.""",
    implementation = _kt_native_xctest_library_impl,
    attrs = dict(LINK_ATTRS, **{
        "associates": attr.label_list(
            doc = """kt_native_library targets whose internal declarations the srcs see. They are deps of the library
            too. The srcs compile against their header klibs when they write one (see the build setting
            experimental_native_header_klibs): a header klib keeps internal declarations.""",
            providers = [KtKlibInfo],
        ),
        "kmp_fragments": attr.label_list(
            doc = """The K2 fragments of a `kt_multiplatform_test` that the srcs refine, as for `kt_native_test`:
            `kt_multiplatform_test` sets it, it is not set by hand. The test bundle runs the tests of the fragments
            too.""",
            providers = [KtFragmentInfo],
        ),
        "srcs": attr.label_list(
            doc = "Kotlin sources with the tests.",
            allow_files = [".kt"],
        ),
        "_launcher": attr.label(
            default = "//kotlin/internal/native:XCTestLauncher.kt",
            allow_single_file = True,
        ),
        "_test_case": attr.label(
            default = "//kotlin/internal/native:XCTestShim.m",
            allow_single_file = True,
        ),
    }),
    cfg = kt_native_transition,
    fragments = ["cpp"],
    provides = [CcInfo],
    toolchains = [KT_NATIVE_TOOLCHAIN_TYPE] + use_cc_toolchain(mandatory = False),
)
