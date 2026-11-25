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
load("//kotlin/internal/kmp:fragment.bzl", "KtFragmentInfo", "KtFragmentsGraphInfo", "kt_kmp_fragments_graph")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:multiplatform.bzl", "alias_branches", "display_label", "konan_targets_compatibility")
load(
    "//src/test/starlark/internal/native:common.bzl",
    "for_target",
    "launcher_values",
    "not_on_windows",
    "prefixed",
    "single_action",
    "tool_arguments",
)

_PACKAGE = "src/test/starlark/internal/kmp"
_KOTLIN_PLATFORM_TYPE = str(Label("//kotlin/settings:kotlin_platform_type"))

# The sources of the mpp fixture that several platforms list: every platform the common ones, and
# the native platforms those of Gradle's nativeMain.
_COMMON = [
    "testdata/Platform.kt",
    "testdata/Greeting.kt",
]
_NON_JVM = ["testdata/Description.native.kt"]

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
    argv = single_action(env, "KotlinNativeKlibCompile").argv
    tool = tool_arguments(argv)
    _assert_fragments(env, tool, ctx.attr)
    asserts.equals(env, ctx.attr.srcs, [_basename(path) for path in launcher_values(argv, "--source")])
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
    asserts.equals(env, "mpp_native.klib", target[KtKlibInfo].klib.basename)

    return analysistest.end(env)

def _alias_native_only_test_impl(ctx):
    env = analysistest.begin(ctx)

    # `bazel build` of the alias of a library with a single kind of platform builds the library there
    # is, as for a library of the JVM alone, whatever asks: here nothing set the platform type native.
    target = analysistest.target_under_test(env)
    asserts.true(env, KtKlibInfo in target, "the alias should be the native library")
    asserts.equals(env, "mpp_ios_only_native.klib", target[KtKlibInfo].klib.basename)

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

def _fragments_graph_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    asserts.equals(env, ctx.attr.graph, target[KtFragmentsGraphInfo].graph)
    executable = target[DefaultInfo].files_to_run.executable
    asserts.equals(env, [executable], target[DefaultInfo].files.to_list())
    asserts.equals(env, ctx.attr.launcher, executable.basename)
    action = single_action(env, "FileWrite")
    asserts.true(env, action.content.startswith(ctx.attr.header), action.content)
    if ctx.attr.expected_content:
        asserts.equals(env, ctx.attr.expected_content, action.content)

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
native_ios_simulator_arm64_test = analysistest.make(
    _native_test_impl,
    attrs = _NATIVE_ATTRS,
    config_settings = for_target("ios_simulator_arm64"),
)
jvm_test = analysistest.make(_jvm_test_impl, attrs = _FRAGMENT_FLAGS_ATTRS)
alias_native_test = analysistest.make(
    _alias_native_test_impl,
    config_settings = _native_consumer_of("linux_arm64"),
)

# A JVM consumer on a host of a konan target of the groups: the platform alone selects no native library.
alias_jvm_on_native_host_test = analysistest.make(_alias_jvm_test_impl, config_settings = for_target("linux_arm64"))
alias_native_only_test = analysistest.make(
    _alias_native_only_test_impl,
    config_settings = for_target("ios_simulator_arm64"),
)
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

fragment_test = analysistest.make(_fragment_test_impl, attrs = _FRAGMENT_ATTRS)
files_test = analysistest.make(_files_test_impl, attrs = {"files": attr.string_list()})
_FRAGMENTS_GRAPH_ATTRS = {
    "expected_content": attr.string(),
    "graph": attr.string(mandatory = True),
    "header": attr.string(mandatory = True),
    "launcher": attr.string(mandatory = True),
}
fragments_graph_unix_test = analysistest.make(
    _fragments_graph_test_impl,
    attrs = _FRAGMENTS_GRAPH_ATTRS,
    config_settings = {
        "//command_line_option:platforms": [str(Label("//%s:jvm_platform" % _PACKAGE))],
    },
)
fragments_graph_windows_test = analysistest.make(
    _fragments_graph_test_impl,
    attrs = _FRAGMENTS_GRAPH_ATTRS,
    config_settings = {
        "//command_line_option:platforms": [str(Label("//%s:windows_platform" % _PACKAGE))],
    },
)
failure_test = analysistest.make(
    _failure_test_impl,
    attrs = {"message": attr.string()},
    expect_failure = True,
)

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

    return unittest.end(env)

def _alias_branches_test(ctx):
    env = unittest.begin(ctx)

    # Bazel convention: a dependency that does not build for a platform is incompatible with it, so
    # its dependents are skipped. The alias is the native library for every Kotlin/Native consumer,
    # also one of a konan target the library does not list, for which the native library is
    # incompatible; it is never a JVM library, which no Kotlin/Native rule can depend on.
    native = str(Label("//kotlin/native/platforms:native"))
    android = str(Label("@platforms//os:android"))
    asserts.equals(
        env,
        {android: ":lib_android", native: ":lib_native", "//conditions:default": ":lib_jvm"},
        alias_branches("lib", {"android": ["android"], "common": [], "ios": [], "jvm": ["jvm"], "native": ["ios_arm64"]}),
    )
    asserts.equals(
        env,
        {native: ":lib_native", "//conditions:default": ":lib_jvm"},
        alias_branches("lib", {"jvm": ["jvm"], "native": ["linux_x64"]}),
    )

    # A library of one kind of platform is that library by default: `bazel build` of the alias builds it.
    asserts.equals(
        env,
        {native: ":lib_native", "//conditions:default": ":lib_native"},
        alias_branches("lib", {"native": ["linux_x64"]}),
    )
    asserts.equals(
        env,
        {android: ":lib_android", "//conditions:default": ":lib_android"},
        alias_branches("lib", {"android": ["android"]}),
    )
    asserts.equals(env, {"//conditions:default": ":lib_jvm"}, alias_branches("lib", {"jvm": ["jvm"]}))

    return unittest.end(env)

def _display_label_test(ctx):
    env = unittest.begin(ctx)

    pkg = Label("//shared:__pkg__")
    asserts.equals(env, "common/A.kt", display_label(Label("//shared:common/A.kt"), pkg))
    asserts.equals(env, "shared_ksp_jvm", display_label(Label("//shared:shared_ksp_jvm"), pkg))
    asserts.equals(env, "//other/sub:A.kt", display_label(Label("//other/sub:A.kt"), pkg))
    asserts.equals(env, "//:A.kt", display_label(Label("//:A.kt"), pkg))
    asserts.equals(env, str(Label("@platforms//os:linux")), display_label(Label("@platforms//os:linux"), pkg))

    root_pkg = Label("//:__pkg__")
    asserts.equals(env, "common/A.kt", display_label(Label("//:common/A.kt"), root_pkg))
    asserts.equals(env, "//sub:A.kt", display_label(Label("//sub:A.kt"), root_pkg))

    return unittest.end(env)

konan_targets_compatibility_test = unittest.make(_konan_targets_compatibility_test)
alias_branches_test = unittest.make(_alias_branches_test)
display_label_test = unittest.make(_display_label_test)

def multiplatform_test_suite(name):
    """Declares multiplatform libraries and the tests of what kt_multiplatform_library declares.

    Args:
      name: the name of the generated test_suite target.
    """

    # Every platform compiles the common sources, the konan targets the non-JVM ones of native, and
    # each konan target those of apple or linux too. The opt-in of native is for the Linux target alone.
    kt_multiplatform_library(
        name = "mpp",
        platforms = [
            "jvm",
            "linux_arm64",
            "macos_arm64",
            "ios_simulator_arm64",
        ],
        srcs = _COMMON,
        native = dict(opts = select({
            "//kotlin/native/platforms:is_linux_arm64": ["-opt-in=kotlin.ExperimentalStdlibApi"],
            "//conditions:default": [],
        })),
        srcs_apple = ["testdata/Platform.apple.kt"],
        srcs_jvm = ["testdata/Platform.jvm.kt"],
        srcs_linux = ["testdata/Platform.linux.kt"],
        srcs_native = _NON_JVM,
        tags = ["manual"],
    )

    # The JVM and the Linux target compile the sources of an alias, no group of the hierarchy, as
    # its fragment, which refines common and which their empty leaves refine; the macOS target
    # compiles the common sources alone.
    kt_multiplatform_library(
        name = "mpp_alias",
        aliases = {"jvm_linux": [
            "jvm",
            "linux_arm64",
        ]},
        platforms = [
            "jvm",
            "linux_arm64",
            "macos_arm64",
        ],
        srcs = ["testdata/Greeting.kt"],
        srcs_jvm_linux = [
            "testdata/Platform.kt",
            "testdata/Platform.linux.kt",
        ],
        tags = ["manual"],
    )

    # Two aliases neither of whose platforms include those of the other: the JVM leaf refines both.
    kt_multiplatform_library(
        name = "mpp_incomparable",
        aliases = {
            "jvm_linux": [
                "jvm",
                "linux_arm64",
            ],
            "jvm_macos": [
                "jvm",
                "macos_arm64",
            ],
        },
        platforms = [
            "jvm",
            "linux_arm64",
            "macos_arm64",
        ],
        srcs = ["testdata/Platform.kt"],
        srcs_jvm = ["testdata/Platform.jvm.kt"],
        srcs_jvm_linux = ["testdata/Description.native.kt"],
        srcs_jvm_macos = ["testdata/Platform.apple.kt"],
        tags = ["manual"],
    )

    # Every level of the lineage of the iOS simulator has sources: the native library compiles their
    # chain of fragments, native and apple of as many platforms in the order they refine.
    kt_multiplatform_library(
        name = "mpp_ios_chain",
        platforms = [
            "jvm",
            "macos_arm64",
            "ios_simulator_arm64",
        ],
        srcs = _COMMON,
        srcs_apple = ["testdata/Platform.apple.kt"],
        srcs_ios = ["testdata/Ios.kt"],
        srcs_jvm = ["testdata/Platform.jvm.kt"],
        srcs_native = _NON_JVM,
        tags = ["manual"],
    )

    # A library of iOS targets only: common and ios cover the same platforms and stay two fragments,
    # so the actual declarations of ios implement the expect ones of common.
    kt_multiplatform_library(
        name = "mpp_ios_only",
        platforms = [
            "ios_arm64",
            "ios_simulator_arm64",
        ],
        srcs = ["testdata/Platform.kt"],
        srcs_ios = ["testdata/Platform.apple.kt"],
        tags = ["manual"],
    )

    # A single platform compiles the common sources as the fragment common, which its leaf refines.
    kt_multiplatform_library(
        name = "mpp_single",
        testonly = True,
        platforms = ["jvm"],
        srcs = _COMMON,
        srcs_jvm = ["testdata/Platform.jvm.kt"],
        tags = ["manual"],
    )

    # A file of every platform that the JVM lists again through a filegroup: the label of every
    # platform is in a fragment, the filegroup in the JVM leaf.
    native.filegroup(
        name = "mpp_platform_file",
        srcs = ["testdata/Platform.kt"],
        tags = ["manual"],
    )
    kt_multiplatform_library(
        name = "mpp_two_labels",
        platforms = [
            "jvm",
            "linux_arm64",
        ],
        srcs = ["testdata/Platform.kt"],
        srcs_jvm = [":mpp_platform_file"],
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
    native.platform(
        name = "windows_platform",
        constraint_values = [
            "@platforms//cpu:x86_64",
            "@platforms//os:windows",
        ],
    )
    kt_kmp_fragments_graph(
        name = "mpp_special_chars.fragments",
        graph = "-e 'single' \"double\" $VAR `cmd` \\back %1% ^caret & < > | (paren) !bang\n",
        tags = ["manual"],
    )

    native_linux_arm64_test(
        name = "multiplatform_native_linux_test",
        target_under_test = ":mpp_native",
        fragments = [
            "common",
            "native",
            "linux",
            "linux_arm64",
        ],
        opt_in = True,
        refines = [
            "native:common",
            "linux:native",
            "linux_arm64:linux",
        ],
        sources = [
            "common:Platform.kt",
            "common:Greeting.kt",
            "native:Description.native.kt",
            "linux:Platform.linux.kt",
        ],
        srcs = [
            "Platform.kt",
            "Greeting.kt",
            "Description.native.kt",
            "Platform.linux.kt",
        ],
        target_compatible_with = not_on_windows(),
    )

    # The Apple targets compile the fragment of apple instead, and their leaves are empty.
    native_macos_arm64_test(
        name = "multiplatform_native_apple_test",
        target_under_test = ":mpp_native",
        fragments = [
            "common",
            "native",
            "apple",
            "macos_arm64",
        ],
        opt_in = False,
        refines = [
            "native:common",
            "apple:native",
            "macos_arm64:apple",
        ],
        sources = [
            "common:Platform.kt",
            "common:Greeting.kt",
            "native:Description.native.kt",
            "apple:Platform.apple.kt",
        ],
        srcs = [
            "Platform.kt",
            "Greeting.kt",
            "Description.native.kt",
            "Platform.apple.kt",
        ],
        target_compatible_with = not_on_windows(),
    )

    # The chain of the iOS simulator: one fragment per group, native and apple of the same platforms.
    native_ios_simulator_arm64_test(
        name = "multiplatform_native_ios_chain_test",
        target_under_test = ":mpp_ios_chain_native",
        fragments = [
            "common",
            "native",
            "apple",
            "ios",
            "ios_simulator_arm64",
        ],
        refines = [
            "native:common",
            "apple:native",
            "ios:apple",
            "ios_simulator_arm64:ios",
        ],
        sources = [
            "common:Platform.kt",
            "common:Greeting.kt",
            "native:Description.native.kt",
            "apple:Platform.apple.kt",
            "ios:Ios.kt",
        ],
        srcs = [
            "Platform.kt",
            "Greeting.kt",
            "Description.native.kt",
            "Platform.apple.kt",
            "Ios.kt",
        ],
        target_compatible_with = not_on_windows(),
    )
    native_ios_simulator_arm64_test(
        name = "multiplatform_native_ios_only_test",
        target_under_test = ":mpp_ios_only_native",
        fragments = [
            "common",
            "ios",
            "ios_simulator_arm64",
        ],
        refines = [
            "ios:common",
            "ios_simulator_arm64:ios",
        ],
        sources = [
            "common:Platform.kt",
            "ios:Platform.apple.kt",
        ],
        srcs = [
            "Platform.kt",
            "Platform.apple.kt",
        ],
        target_compatible_with = not_on_windows(),
    )
    jvm_test(
        name = "multiplatform_jvm_test",
        target_under_test = ":mpp_jvm",
        fragments = [
            "common",
            "jvm",
        ],
        refines = ["jvm:common"],
        sources = [
            "common:Platform.kt",
            "common:Greeting.kt",
            "jvm:Platform.jvm.kt",
        ],
    )
    jvm_test(
        name = "multiplatform_aliases_jvm_test",
        target_under_test = ":mpp_alias_jvm",
        fragments = [
            "common",
            "jvm_linux",
            "jvm",
        ],
        refines = [
            "jvm_linux:common",
            "jvm:jvm_linux",
        ],
        sources = [
            "common:Greeting.kt",
            "jvm_linux:Platform.kt",
            "jvm_linux:Platform.linux.kt",
        ],
    )
    native_linux_arm64_test(
        name = "multiplatform_aliases_native_linux_test",
        target_under_test = ":mpp_alias_native",
        fragments = [
            "common",
            "jvm_linux",
            "linux_arm64",
        ],
        refines = [
            "jvm_linux:common",
            "linux_arm64:jvm_linux",
        ],
        sources = [
            "common:Greeting.kt",
            "jvm_linux:Platform.kt",
            "jvm_linux:Platform.linux.kt",
        ],
        srcs = [
            "Greeting.kt",
            "Platform.kt",
            "Platform.linux.kt",
        ],
        target_compatible_with = not_on_windows(),
    )

    # A platform that the alias does not group compiles nothing of it.
    native_macos_arm64_test(
        name = "multiplatform_aliases_native_apple_test",
        target_under_test = ":mpp_alias_native",
        fragments = [
            "common",
            "macos_arm64",
        ],
        refines = ["macos_arm64:common"],
        sources = ["common:Greeting.kt"],
        srcs = ["Greeting.kt"],
        target_compatible_with = not_on_windows(),
    )
    jvm_test(
        name = "multiplatform_incomparable_test",
        target_under_test = ":mpp_incomparable_jvm",
        fragments = [
            "common",
            "jvm_linux",
            "jvm_macos",
            "jvm",
        ],
        refines = [
            "jvm_linux:common",
            "jvm_macos:common",
            "jvm:jvm_linux",
            "jvm:jvm_macos",
        ],
        sources = [
            "common:Platform.kt",
            "jvm_linux:Description.native.kt",
            "jvm_macos:Platform.apple.kt",
            "jvm:Platform.jvm.kt",
        ],
    )
    jvm_test(
        name = "multiplatform_single_platform_test",
        target_under_test = ":mpp_single_jvm",
        fragments = [
            "common",
            "jvm",
        ],
        refines = ["jvm:common"],
        sources = [
            "common:Platform.kt",
            "common:Greeting.kt",
            "jvm:Platform.jvm.kt",
        ],
    )
    failure_test(
        name = "multiplatform_file_in_two_fragments_fails_test",
        target_under_test = ":mpp_two_labels_jvm",
        message = "testdata/Platform.kt is in both fragment 'common' and 'jvm'",
    )
    fragment_test(
        name = "multiplatform_apple_fragment_test",
        target_under_test = ":mpp_fragment_apple",
        fragment = "apple",
        refines = ["native"],
        srcs = ["Platform.apple.kt"],
        transitive = [
            "common",
            "native",
            "apple",
        ],
    )
    fragment_test(
        name = "multiplatform_common_fragment_test",
        target_under_test = ":mpp_fragment_common",
        fragment = "common",
        srcs = [
            "Platform.kt",
            "Greeting.kt",
        ],
        transitive = ["common"],
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
    alias_native_only_test(
        name = "multiplatform_alias_native_only_test",
        target_under_test = ":mpp_ios_only",
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
        name = "multiplatform_aliases_srcs_test",
        target_under_test = ":mpp_alias_srcs",
        files = [
            "Greeting.kt",
            "Platform.kt",
            "Platform.linux.kt",
        ],
    )
    fragments_graph_unix_test(
        name = "multiplatform_fragments_graph_test",
        target_under_test = ":mpp.fragments",
        graph = """\
fragment common
  platforms: jvm, linux_arm64, macos_arm64, ios_simulator_arm64
  srcs:
    testdata/Platform.kt
    testdata/Greeting.kt
fragment native
  refines: common
  platforms: linux_arm64, macos_arm64, ios_simulator_arm64
  srcs:
    testdata/Description.native.kt
fragment apple
  refines: native
  platforms: macos_arm64, ios_simulator_arm64
  srcs:
    testdata/Platform.apple.kt
fragment linux
  refines: native
  platforms: linux_arm64
  srcs:
    testdata/Platform.linux.kt
leaf ios_simulator_arm64
  refines: apple
leaf jvm
  refines: common
  srcs:
    testdata/Platform.jvm.kt
leaf linux_arm64
  refines: linux
leaf macos_arm64
  refines: apple
""",
        header = "#!/usr/bin/env sh\n",
        launcher = "mpp.fragments.sh",
    )
    fragments_graph_unix_test(
        name = "multiplatform_aliases_fragments_graph_test",
        target_under_test = ":mpp_alias.fragments",
        graph = """\
fragment common
  platforms: jvm, linux_arm64, macos_arm64
  srcs:
    testdata/Greeting.kt
fragment jvm_linux
  refines: common
  platforms: jvm, linux_arm64
  srcs:
    testdata/Platform.kt
    testdata/Platform.linux.kt
leaf jvm
  refines: jvm_linux
leaf linux_arm64
  refines: jvm_linux
leaf macos_arm64
  refines: common
""",
        header = "#!/usr/bin/env sh\n",
        launcher = "mpp_alias.fragments.sh",
    )
    fragments_graph_unix_test(
        name = "multiplatform_incomparable_fragments_graph_test",
        target_under_test = ":mpp_incomparable.fragments",
        graph = """\
fragment common
  platforms: jvm, linux_arm64, macos_arm64
  srcs:
    testdata/Platform.kt
fragment jvm_linux
  refines: common
  platforms: jvm, linux_arm64
  srcs:
    testdata/Description.native.kt
fragment jvm_macos
  refines: common
  platforms: jvm, macos_arm64
  srcs:
    testdata/Platform.apple.kt
leaf jvm
  refines: jvm_linux, jvm_macos
  srcs:
    testdata/Platform.jvm.kt
leaf linux_arm64
  refines: jvm_linux
leaf macos_arm64
  refines: jvm_macos
""",
        header = "#!/usr/bin/env sh\n",
        launcher = "mpp_incomparable.fragments.sh",
    )
    fragments_graph_unix_test(
        name = "multiplatform_single_fragments_graph_test",
        target_under_test = ":mpp_single.fragments",
        graph = """\
fragment common
  platforms: jvm
  srcs:
    testdata/Platform.kt
    testdata/Greeting.kt
leaf jvm
  refines: common
  srcs:
    testdata/Platform.jvm.kt
""",
        header = "#!/usr/bin/env sh\n",
        launcher = "mpp_single.fragments.sh",
    )
    fragments_graph_unix_test(
        name = "multiplatform_ios_only_fragments_graph_test",
        target_under_test = ":mpp_ios_only.fragments",
        graph = """\
fragment common
  platforms: ios_arm64, ios_simulator_arm64
  srcs:
    testdata/Platform.kt
fragment ios
  refines: common
  platforms: ios_arm64, ios_simulator_arm64
  srcs:
    testdata/Platform.apple.kt
leaf ios_arm64
  refines: ios
leaf ios_simulator_arm64
  refines: ios
""",
        header = "#!/usr/bin/env sh\n",
        launcher = "mpp_ios_only.fragments.sh",
    )
    fragments_graph_windows_test(
        name = "multiplatform_windows_fragments_graph_test",
        target_under_test = ":mpp_special_chars.fragments",
        expected_content = (
            "@echo off\r\n" +
            "setlocal DisableDelayedExpansion\r\n" +
            "echo(-e 'single' ^\"double^\" $VAR `cmd` \\back %%1%% ^^caret ^& ^< ^> ^| ^(paren^) !bang\r\n"
        ),
        graph = "-e 'single' \"double\" $VAR `cmd` \\back %1% ^caret & < > | (paren) !bang\n",
        header = "@echo off\r\n",
        launcher = "mpp_special_chars.fragments.bat",
    )
    unittest.suite(
        "multiplatform_helpers",
        konan_targets_compatibility_test,
        alias_branches_test,
        display_label_test,
    )

    native.test_suite(
        name = name,
        tests = [
            ":multiplatform_alias_jvm_on_native_host_test",
            ":multiplatform_alias_jvm_test",
            ":multiplatform_alias_native_only_test",
            ":multiplatform_alias_native_test",
            ":multiplatform_aliases_fragments_graph_test",
            ":multiplatform_aliases_jvm_test",
            ":multiplatform_aliases_native_apple_test",
            ":multiplatform_aliases_native_linux_test",
            ":multiplatform_aliases_srcs_test",
            ":multiplatform_apple_fragment_test",
            ":multiplatform_common_fragment_test",
            ":multiplatform_file_in_two_fragments_fails_test",
            ":multiplatform_fragments_graph_test",
            ":multiplatform_helpers",
            ":multiplatform_incomparable_fragments_graph_test",
            ":multiplatform_incomparable_test",
            ":multiplatform_ios_only_fragments_graph_test",
            ":multiplatform_jvm_test",
            ":multiplatform_native_apple_test",
            ":multiplatform_native_ios_chain_test",
            ":multiplatform_native_ios_only_test",
            ":multiplatform_native_linux_test",
            ":multiplatform_single_fragments_graph_test",
            ":multiplatform_single_platform_test",
            ":multiplatform_srcs_test",
            ":multiplatform_windows_fragments_graph_test",
        ],
    )
