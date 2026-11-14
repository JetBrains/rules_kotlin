"""Tests for kt_multiplatform_library: the fragments it derives, the targets it declares, and the library its alias selects per consumer.

The native tests use the fake toolchains of //src/test/starlark/internal/native (see common.bzl there).
The alias is the native library below the Kotlin/Native rules, which set the Kotlin platform type
to native: the tests of the alias alone set it as such a consumer does.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("@rules_java//java:defs.bzl", "JavaInfo")
load("//kotlin:kmp.bzl", "kt_multiplatform_library")
load("//kotlin:native.bzl", "KtKlibInfo")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:fragment.bzl", "KtFragmentInfo")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:multiplatform.bzl", "konan_targets_compatibility", "multiplatform_declaration_error")
load(
    "//src/test/starlark/internal/native:common.bzl",
    "for_target",
    "not_on_windows",
    "prefixed",
    "single_action",
    "tool_arguments",
)

_PACKAGE = "src/test/starlark/internal/kmp"
_NAMES = "src_test_starlark_internal_kmp-"
_KOTLIN_PLATFORM_TYPE = str(Label("//kotlin/settings:kotlin_platform_type"))

# The sources of the mpp fixture that several platforms list: every platform the common ones, and
# the native platforms those of Gradle's nativeMain.
_COMMON = [
    "testdata/Platform.kt",
    "testdata/Greeting.kt",
]
_NON_JVM = ["testdata/Description.native.kt"]

# The fragments of the mpp fixture: of the common sources, of the non-JVM ones and of the Apple ones.
_ALL = "ios_simulator_arm64-jvm-linux_arm64-macos_arm64"
_NATIVE = "ios_simulator_arm64-linux_arm64-macos_arm64"
_APPLE = "ios_simulator_arm64-macos_arm64"

# The srcs of a platform as a select(), whose branches are only known at analysis.
_SELECTED_SRCS = select({"//conditions:default": ["testdata/Platform.jvm.kt"]})

def _basename(path):
    return path.rpartition("/")[2]

def _fragment_sources(args):
    """The -Xfragment-sources of a compilation, as `<fragment>:<basename>`."""
    return [
        "%s:%s" % (fragment, _basename(path))
        for fragment, _, path in [source.partition(":") for source in prefixed(args, "-Xfragment-sources=")]
    ]

def _assert_fragments(env, args, attr):
    """Asserts the fragment flags of the arguments of a compilation against the expected ones of a test."""
    asserts.equals(env, [",".join(attr.fragments)] if attr.fragments else [], prefixed(args, "-Xfragments="))
    asserts.equals(env, attr.sources, _fragment_sources(args))
    asserts.equals(env, attr.refines, prefixed(args, "-Xfragment-refines="))
    asserts.equals(env, bool(attr.fragments), "-Xmulti-platform" in args, str(args))

def _native_consumer_of(konan_target):
    """The config_settings of a Kotlin/Native consumer building for a konan target: the platform and the platform type the Kotlin/Native rules set."""
    return dict(for_target(konan_target), **{_KOTLIN_PLATFORM_TYPE: "native"})

def _native_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The native library compiles, for the konan target, every fragment of a set of platforms
    # including it, most shared first, then its own leaf, and takes the other attributes of the
    # group of the target.
    tool = tool_arguments(single_action(env, "KotlinNativeKlibCompile").argv)
    _assert_fragments(env, tool, ctx.attr)
    asserts.equals(env, ctx.attr.srcs, [_basename(path) for path in tool[tool.index("-o") + 2:]])
    asserts.equals(env, ctx.attr.opt_in, "-opt-in=kotlin.ExperimentalStdlibApi" in tool, str(tool))

    return analysistest.end(env)

def _jvm_test_impl(ctx):
    env = analysistest.begin(ctx)

    _assert_fragments(env, single_action(env, "KotlinCompile").argv, ctx.attr)

    return analysistest.end(env)

def _alias_native_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    asserts.true(env, KtKlibInfo in target, "the alias should be the native library")
    asserts.false(env, JavaInfo in target, "the alias should not be the JVM library")
    asserts.equals(env, _NAMES + "mpp_native", target[KtKlibInfo].module_name)

    return analysistest.end(env)

def _alias_jvm_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    asserts.false(env, KtKlibInfo in target, "the alias should not be the native library")
    asserts.equals(env, ["mpp_jvm.jar"], [jar.basename for jar in target[JavaInfo].runtime_output_jars])

    return analysistest.end(env)

def _fragment_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The fragment target of a set of platforms refines the fragments directly above it.
    info = analysistest.target_under_test(env)[KtFragmentInfo]
    asserts.equals(env, ctx.attr.fragment, info.name)
    asserts.equals(env, ctx.attr.srcs, [src.basename for src in info.srcs])
    asserts.equals(env, ctx.attr.refines, list(info.refines))
    asserts.equals(env, ctx.attr.transitive, [fragment.name for fragment in info.transitive_fragments.to_list()])

    return analysistest.end(env)

def _files_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.equals(
        env,
        ctx.attr.files,
        sorted([f.basename for f in analysistest.target_under_test(env)[DefaultInfo].files.to_list()]),
    )

    return analysistest.end(env)

def _failure_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(env, ctx.attr.message)

    return analysistest.end(env)

_FRAGMENT_FLAGS_ATTRS = {
    "fragments": attr.string_list(doc = "the expected -Xfragments, in order; none for no fragment flags"),
    "refines": attr.string_list(doc = "the expected -Xfragment-refines, `<fragment>:<refined>`, in order"),
    "sources": attr.string_list(doc = "the expected -Xfragment-sources, `<fragment>:<basename>`, in order"),
}
_NATIVE_ATTRS = dict(_FRAGMENT_FLAGS_ATTRS, **{
    "opt_in": attr.bool(),
    "srcs": attr.string_list(doc = "the basenames of the expected sources, in order"),
})

native_linux_arm64_test = analysistest.make(
    _native_test_impl,
    attrs = _NATIVE_ATTRS,
    config_settings = for_target("linux_arm64"),
)
native_macos_arm64_test = analysistest.make(
    _native_test_impl,
    attrs = _NATIVE_ATTRS,
    config_settings = for_target("macos_arm64"),
)
jvm_test = analysistest.make(_jvm_test_impl, attrs = _FRAGMENT_FLAGS_ATTRS)
alias_native_test = analysistest.make(
    _alias_native_test_impl,
    config_settings = _native_consumer_of("linux_arm64"),
)

# A JVM consumer on a host of a konan target of the groups: the platform alone selects no native library.
alias_jvm_on_native_host_test = analysistest.make(_alias_jvm_test_impl, config_settings = for_target("linux_arm64"))
alias_jvm_test = analysistest.make(
    _alias_jvm_test_impl,
    config_settings = {
        "//command_line_option:platforms": [str(Label("//%s:jvm_platform" % _PACKAGE))],
    },
)

_FRAGMENT_ATTRS = {
    "fragment": attr.string(doc = "the expected name of the fragment"),
    "refines": attr.string_list(doc = "the names of the fragments it is expected to refine"),
    "srcs": attr.string_list(doc = "the basenames of its expected sources, in order"),
    "transitive": attr.string_list(doc = "the names of its expected transitive fragments, in order"),
}

# A fragment of konan targets only is only compatible below a Kotlin/Native consumer building for one
# of its targets: the test is such a consumer, as the native library is (the platform alone would
# skip the test as incompatible). A fragment with the JVM is compatible with any consumer.
konan_fragment_test = analysistest.make(
    _fragment_test_impl,
    attrs = _FRAGMENT_ATTRS,
    config_settings = _native_consumer_of("macos_arm64"),
)
fragment_test = analysistest.make(_fragment_test_impl, attrs = _FRAGMENT_ATTRS)
files_test = analysistest.make(_files_test_impl, attrs = {"files": attr.string_list()})
failure_test = analysistest.make(
    _failure_test_impl,
    attrs = {"message": attr.string()},
    expect_failure = True,
)

def _relative(label):
    """Normalizes the labels of the package as package_relative_label does for the unit tests: `:a.kt` is `a.kt`."""
    return label[1:] if label.startswith(":") else label

def _valid_declaration_test(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, None, multiplatform_declaration_error(dict(srcs = []), None, {}))
    asserts.equals(env, None, multiplatform_declaration_error(None, dict(srcs = ["a.kt"], deps = [":lib"]), {}))
    asserts.equals(
        env,
        None,
        multiplatform_declaration_error(
            None,
            None,
            {
                "apple": dict(srcs = ["a.kt", "b.kt"], targets = ["ios_arm64", "macos_arm64"]),
                # A group names no target: any name of letters, digits and '_' is valid.
                "jvm": dict(srcs = ["a.kt"], targets = ["linux_x64"], opts = ["-opt"], deps = [":klib"]),
            },
        ),
    )

    # The other arguments are attributes of every target.
    asserts.equals(env, None, multiplatform_declaration_error(dict(srcs = []), None, {}, {"features": ["a"]}))

    return unittest.end(env)

def _invalid_declarations_test(ctx):
    env = unittest.begin(ctx)

    for message, jvm, android, native, kwargs in [
        (
            "common_srcs is removed: each platform lists every source it compiles: add the sources to the srcs of " +
            "each platform, e.g. through a list they share, srcs = COMMON + JVM",
            dict(srcs = []),
            None,
            {},
            {"common_srcs": ["a.kt"]},
        ),
        (
            "common_deps is removed: add the deps to the deps of each platform, which compiles the sources it " +
            "shares against its own deps",
            dict(srcs = []),
            None,
            {},
            {"common_deps": [":lib"]},
        ),
        ("it declares no platform: give jvm, android or native", None, None, {}, {}),
        ("jvm must be a dict of attributes of its library, not a list", [], None, {}, {}),
        ("native must be a dict of groups of konan targets, not a list", None, None, ["apple"], {}),
        (
            "the native group 'a-b' must be a name of letters, digits and '_'",
            None,
            None,
            {"a-b": dict(targets = ["linux_x64"])},
            {},
        ),
        ("the native group 'linux' lists no konan targets", None, None, {"linux": dict(srcs = [])}, {}),
        (
            "the native group 'linux' lists the unknown konan target 'linux_riscv64'; the known ones are " +
            "ios_arm64, ios_simulator_arm64, linux_arm64, linux_x64, macos_arm64",
            None,
            None,
            {"linux": dict(targets = ["linux_riscv64"])},
            {},
        ),
        (
            "the konan target 'ios_arm64' is in both native groups 'apple' and 'ios'",
            None,
            None,
            {"apple": dict(targets = ["ios_arm64", "macos_arm64"]), "ios": dict(targets = ["ios_arm64"])},
            {},
        ),
        (
            "jvm sets source_sets, which are removed: add their sources to its srcs; the sources that the same " +
            "platforms list form one fragment",
            dict(srcs = [], source_sets = [":common"]),
            None,
            {},
            {},
        ),
        (
            "the native group 'apple' sets depends_on, which is removed: add the sources of the source sets it " +
            "refined to its srcs; the sources that the same platforms list form one fragment",
            None,
            None,
            {"apple": dict(targets = ["ios_arm64"], depends_on = [":non_jvm"])},
            {},
        ),
        (
            "android sets kmp_fragments, which the macro derives from the srcs of the platforms",
            None,
            dict(srcs = [], kmp_fragments = [":common"]),
            {},
            {},
        ),
        (
            "the srcs of jvm must be a list of labels, not a select: the macro derives the fragments from the srcs " +
            "of the platforms when it is called, before any select() is resolved",
            dict(srcs = _SELECTED_SRCS),
            None,
            {},
            {},
        ),
        (
            "the srcs of jvm must be a list of labels, not a select: the macro derives the fragments from the srcs " +
            "of the platforms when it is called, before any select() is resolved",
            dict(srcs = ["a.kt"] + _SELECTED_SRCS),
            None,
            {},
            {},
        ),
        (
            "the srcs of the native group 'linux' list a.kt twice",
            None,
            None,
            {"linux": dict(srcs = ["a.kt", "b.kt", "a.kt"], targets = ["linux_x64"])},
            {},
        ),
    ]:
        asserts.equals(env, message, multiplatform_declaration_error(jvm, android, native, kwargs))

    # A label written twice in different forms is repeated once normalized, as the macro normalizes it.
    asserts.equals(
        env,
        "the srcs of jvm list a.kt twice",
        multiplatform_declaration_error(dict(srcs = ["a.kt", ":a.kt"]), None, {}, normalize = _relative),
    )

    return unittest.end(env)

def _konan_targets_compatibility_test(ctx):
    env = unittest.begin(ctx)

    # The native library is compatible with the platforms of its konan targets alone, whatever the
    # Kotlin platform type (is_<target>): it transitions itself to native. The labels are resolved as
    # the macro resolves them, in the repository of the rules.
    incompatible = [str(Label("@platforms//:incompatible"))]
    asserts.equals(
        env,
        {
            str(Label("//kotlin/native/platforms:is_ios_arm64")): [],
            str(Label("//kotlin/native/platforms:is_macos_arm64")): [],
            "//conditions:default": incompatible,
        },
        konan_targets_compatibility(["ios_arm64", "macos_arm64"]),
    )
    asserts.equals(
        env,
        {"//conditions:default": incompatible},
        konan_targets_compatibility([]),
    )

    # A fragment of konan targets only is only compatible below a Kotlin/Native consumer building for
    # one of its targets (native_<target>): a build of the package on a macOS host, a JVM consumer,
    # skips the fragment of the Apple targets.
    asserts.equals(
        env,
        {
            str(Label("//kotlin/native/platforms:native_ios_arm64")): [],
            str(Label("//kotlin/native/platforms:native_macos_arm64")): [],
            "//conditions:default": incompatible,
        },
        konan_targets_compatibility(["ios_arm64", "macos_arm64"], native_consumer = True),
    )

    return unittest.end(env)

valid_declaration_test = unittest.make(_valid_declaration_test)
invalid_declarations_test = unittest.make(_invalid_declarations_test)
konan_targets_compatibility_test = unittest.make(_konan_targets_compatibility_test)

def multiplatform_test_suite(name):
    """Declares multiplatform libraries and the tests of what kt_multiplatform_library declares.

    Args:
      name: the name of the generated test_suite target.
    """
    kt_multiplatform_library(
        name = "mpp",
        jvm = dict(srcs = _COMMON + ["testdata/Platform.jvm.kt"]),
        native = {
            "apple": dict(
                srcs = _COMMON + _NON_JVM + ["testdata/Platform.apple.kt"],
                targets = [
                    "ios_simulator_arm64",
                    "macos_arm64",
                ],
            ),
            "linux": dict(
                srcs = _COMMON + _NON_JVM + ["testdata/Platform.linux.kt"],
                opts = ["-opt-in=kotlin.ExperimentalStdlibApi"],
                targets = ["linux_arm64"],
            ),
        },
        tags = ["manual"],
    )

    # Two platforms listing the same sources, one label of them written in another form: they are
    # one fragment, both leaves are empty, and the filegroup of the sources lists each file once.
    kt_multiplatform_library(
        name = "mpp_collapse",
        jvm = dict(srcs = [
            "testdata/Platform.kt",
            "testdata/Platform.linux.kt",
        ]),
        native = {
            "linux": dict(
                srcs = [
                    "testdata/Platform.kt",
                    ":testdata/Platform.linux.kt",
                ],
                targets = ["linux_arm64"],
            ),
        },
        tags = ["manual"],
    )

    # Two fragments of sets of platforms neither of which includes the other: the JVM leaf refines both.
    kt_multiplatform_library(
        name = "mpp_incomparable",
        jvm = dict(srcs = [
            "testdata/Platform.kt",
            "testdata/Description.native.kt",
            "testdata/Platform.apple.kt",
            "testdata/Platform.jvm.kt",
        ]),
        native = {
            "linux": dict(
                srcs = [
                    "testdata/Platform.kt",
                    "testdata/Description.native.kt",
                ],
                targets = ["linux_arm64"],
            ),
            "mac": dict(
                srcs = [
                    "testdata/Platform.kt",
                    "testdata/Platform.apple.kt",
                ],
                targets = ["macos_arm64"],
            ),
        },
        tags = ["manual"],
    )

    # A single platform shares nothing: its library compiles no fragment.
    kt_multiplatform_library(
        name = "mpp_single",
        jvm = dict(srcs = _COMMON + ["testdata/Platform.jvm.kt"]),
        tags = ["manual"],
    )

    # A file the JVM lists through two labels: the one the Linux target lists too is in a fragment,
    # the other in the JVM leaf.
    native.filegroup(
        name = "mpp_platform_file",
        srcs = ["testdata/Platform.kt"],
        tags = ["manual"],
    )
    kt_multiplatform_library(
        name = "mpp_two_labels",
        jvm = dict(srcs = [
            "testdata/Platform.kt",
            ":mpp_platform_file",
        ]),
        native = {
            "linux": dict(
                srcs = ["testdata/Platform.kt"],
                targets = ["linux_arm64"],
            ),
        },
        tags = ["manual"],
    )

    # A platform of no konan target: the alias is the JVM library.
    native.platform(
        name = "jvm_platform",
        constraint_values = [
            "@platforms//cpu:riscv64",
            "@platforms//os:linux",
        ],
    )

    native_linux_arm64_test(
        name = "multiplatform_native_linux_test",
        target_under_test = ":mpp_native",
        fragments = [
            _ALL,
            _NATIVE,
            "linux_arm64",
        ],
        opt_in = True,
        refines = [
            _NATIVE + ":" + _ALL,
            "linux_arm64:" + _NATIVE,
        ],
        sources = [
            _ALL + ":Platform.kt",
            _ALL + ":Greeting.kt",
            _NATIVE + ":Description.native.kt",
            "linux_arm64:Platform.linux.kt",
        ],
        srcs = [
            "Platform.kt",
            "Greeting.kt",
            "Description.native.kt",
            "Platform.linux.kt",
        ],
        target_compatible_with = not_on_windows(),
    )

    # The Apple targets share one more fragment, and their leaves are empty.
    native_macos_arm64_test(
        name = "multiplatform_native_apple_test",
        target_under_test = ":mpp_native",
        fragments = [
            _ALL,
            _NATIVE,
            _APPLE,
            "macos_arm64",
        ],
        opt_in = False,
        refines = [
            _NATIVE + ":" + _ALL,
            _APPLE + ":" + _NATIVE,
            "macos_arm64:" + _APPLE,
        ],
        sources = [
            _ALL + ":Platform.kt",
            _ALL + ":Greeting.kt",
            _NATIVE + ":Description.native.kt",
            _APPLE + ":Platform.apple.kt",
        ],
        srcs = [
            "Platform.kt",
            "Greeting.kt",
            "Description.native.kt",
            "Platform.apple.kt",
        ],
        target_compatible_with = not_on_windows(),
    )
    jvm_test(
        name = "multiplatform_jvm_test",
        target_under_test = ":mpp_jvm",
        fragments = [
            _ALL,
            "jvm",
        ],
        refines = ["jvm:" + _ALL],
        sources = [
            _ALL + ":Platform.kt",
            _ALL + ":Greeting.kt",
            "jvm:Platform.jvm.kt",
        ],
    )
    jvm_test(
        name = "multiplatform_collapse_test",
        target_under_test = ":mpp_collapse_jvm",
        fragments = [
            "jvm-linux_arm64",
            "jvm",
        ],
        refines = ["jvm:jvm-linux_arm64"],
        sources = [
            "jvm-linux_arm64:Platform.kt",
            "jvm-linux_arm64:Platform.linux.kt",
        ],
    )
    jvm_test(
        name = "multiplatform_incomparable_test",
        target_under_test = ":mpp_incomparable_jvm",
        fragments = [
            "jvm-linux_arm64-macos_arm64",
            "jvm-linux_arm64",
            "jvm-macos_arm64",
            "jvm",
        ],
        refines = [
            "jvm-linux_arm64:jvm-linux_arm64-macos_arm64",
            "jvm-macos_arm64:jvm-linux_arm64-macos_arm64",
            "jvm:jvm-linux_arm64",
            "jvm:jvm-macos_arm64",
        ],
        sources = [
            "jvm-linux_arm64-macos_arm64:Platform.kt",
            "jvm-linux_arm64:Description.native.kt",
            "jvm-macos_arm64:Platform.apple.kt",
            "jvm:Platform.jvm.kt",
        ],
    )
    jvm_test(
        name = "multiplatform_single_platform_test",
        target_under_test = ":mpp_single_jvm",
    )
    failure_test(
        name = "multiplatform_file_in_two_fragments_fails_test",
        target_under_test = ":mpp_two_labels_jvm",
        message = "testdata/Platform.kt is in both fragment 'jvm-linux_arm64' and 'jvm'",
    )
    konan_fragment_test(
        name = "multiplatform_konan_fragment_test",
        target_under_test = ":mpp_fragment_" + _APPLE,
        fragment = _APPLE,
        refines = [_NATIVE],
        srcs = ["Platform.apple.kt"],
        transitive = [
            _ALL,
            _NATIVE,
            _APPLE,
        ],
        target_compatible_with = not_on_windows(),
    )
    fragment_test(
        name = "multiplatform_common_fragment_test",
        target_under_test = ":mpp_fragment_" + _ALL,
        fragment = _ALL,
        srcs = [
            "Platform.kt",
            "Greeting.kt",
        ],
        transitive = [_ALL],
    )
    alias_native_test(
        name = "multiplatform_alias_native_test",
        target_under_test = ":mpp",
        target_compatible_with = not_on_windows(),
    )
    alias_jvm_on_native_host_test(
        name = "multiplatform_alias_jvm_on_native_host_test",
        target_under_test = ":mpp",
        target_compatible_with = not_on_windows(),
    )
    alias_jvm_test(
        name = "multiplatform_alias_jvm_test",
        target_under_test = ":mpp",
    )
    files_test(
        name = "multiplatform_srcs_test",
        target_under_test = ":mpp_srcs",
        files = [
            "Description.native.kt",
            "Greeting.kt",
            "Platform.apple.kt",
            "Platform.jvm.kt",
            "Platform.kt",
            "Platform.linux.kt",
        ],
    )
    files_test(
        name = "multiplatform_shared_srcs_test",
        target_under_test = ":mpp_collapse_srcs",
        files = [
            "Platform.kt",
            "Platform.linux.kt",
        ],
    )
    unittest.suite(
        "multiplatform_declarations",
        valid_declaration_test,
        invalid_declarations_test,
        konan_targets_compatibility_test,
    )

    native.test_suite(
        name = name,
        tests = [
            ":multiplatform_alias_jvm_on_native_host_test",
            ":multiplatform_alias_jvm_test",
            ":multiplatform_alias_native_test",
            ":multiplatform_collapse_test",
            ":multiplatform_common_fragment_test",
            ":multiplatform_declarations",
            ":multiplatform_file_in_two_fragments_fails_test",
            ":multiplatform_incomparable_test",
            ":multiplatform_jvm_test",
            ":multiplatform_konan_fragment_test",
            ":multiplatform_native_apple_test",
            ":multiplatform_native_linux_test",
            ":multiplatform_shared_srcs_test",
            ":multiplatform_single_platform_test",
            ":multiplatform_srcs_test",
        ],
    )
