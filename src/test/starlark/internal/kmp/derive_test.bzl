"""Unit tests for derive_fragments: the fragments, names, ranks, refines and leaves of the sources of the groups, aliases and platforms of a library."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:derive.bzl", "derive_fragments", "format_fragments")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:hierarchy.bzl", "HIERARCHY", "resolve_platforms")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:qualifiers.bzl", "resolve_qualifiers")

COMMON = ["common/Platform.kt", "common/Greeting.kt"]
NON_ANDROID = ["non_android/Greeting.nonAndroid.kt"]
NATIVE = ["native/Description.native.kt"]
APPLE = ["apple/Platform.apple.kt"]
IOS = ["ios/Platform.ios.kt"]
LINUX = ["linux/Platform.linux.kt"]
JVM = ["jvm/Platform.jvm.kt"]
ANDROID = ["android/Platform.android.kt"]

# The platforms of examples/kmp but linux_arm64 and ios_simulator_arm64, with Gradle's nonAndroidMain
# as the alias of the JVM and the konan targets.
_NON_ANDROID_PLATFORMS = ["jvm", "android", "ios_arm64", "macos_arm64", "linux_x64"]
_NON_ANDROID_ALIASES = {"non_android": ["jvm", "ios_arm64", "macos_arm64", "linux_x64"]}
_NON_ANDROID_SRCS = {
    "android": ANDROID,
    "apple": APPLE,
    "common": COMMON,
    "jvm": JVM,
    "linux": LINUX,
    "non_android": NON_ANDROID,
}

# Two aliases that share the JVM, neither of which covers the other.
_INCOMPARABLE_PLATFORMS = ["jvm", "android", "linux_x64"]
_INCOMPARABLE_ALIASES = {"android_jvm": ["android", "jvm"], "jvm_linux": ["jvm", "linux_x64"]}
_INCOMPARABLE_SRCS = {
    "android_jvm": ["shared/AndroidJvm.kt"],
    "common": COMMON,
    "jvm": JVM,
    "jvm_linux": ["shared/JvmLinux.kt"],
}

def _qualifiers(platforms, aliases = None):
    return resolve_qualifiers(HIERARCHY, resolve_platforms(HIERARCHY, platforms).targeted, aliases)

def _derive(platforms, qualifier_srcs, aliases = None):
    """The fragments of the sources of some qualifiers of a library of `platforms` of the default hierarchy."""
    return derive_fragments(qualifier_srcs, _qualifiers(platforms, aliases))

def _fragments(derived):
    """The fragments as tuples, which asserts.equals compares field by field."""
    return [
        (fragment.name, fragment.platforms, fragment.rank, fragment.srcs, fragment.refines)
        for fragment in derived.fragments
    ]

def _chain_test(ctx):
    """The sources of each group of a lineage are a fragment refining the one of the group above it."""
    env = unittest.begin(ctx)

    derived = _derive(
        ["jvm", "macos_arm64", "ios_simulator_arm64"],
        {"apple": APPLE, "common": COMMON, "ios": IOS, "jvm": JVM, "native": NATIVE},
    )

    asserts.equals(
        env,
        [
            ("common", ["jvm", "macos_arm64", "ios_simulator_arm64"], 0, COMMON, []),
            ("native", ["macos_arm64", "ios_simulator_arm64"], 1, NATIVE, ["common"]),
            ("apple", ["macos_arm64", "ios_simulator_arm64"], 2, APPLE, ["native"]),
            ("ios", ["ios_simulator_arm64"], 3, IOS, ["apple"]),
        ],
        _fragments(derived),
    )
    asserts.equals(env, {"ios_simulator_arm64": [], "jvm": JVM, "macos_arm64": []}, derived.leaf_srcs)
    asserts.equals(
        env,
        {"ios_simulator_arm64": ["ios"], "jvm": ["common"], "macos_arm64": ["apple"]},
        derived.leaf_refines,
    )

    return unittest.end(env)

def _same_platforms_test(ctx):
    """Groups of the same platforms stay apart, ordered by rank, whatever their names."""
    env = unittest.begin(ctx)

    ios_only = _derive(["ios_arm64", "ios_simulator_arm64"], {"common": COMMON, "ios": IOS})
    asserts.equals(
        env,
        [
            ("common", ["ios_arm64", "ios_simulator_arm64"], 0, COMMON, []),
            ("ios", ["ios_arm64", "ios_simulator_arm64"], 1, IOS, ["common"]),
        ],
        _fragments(ios_only),
    )
    asserts.equals(env, {"ios_arm64": ["ios"], "ios_simulator_arm64": ["ios"]}, ios_only.leaf_refines)

    # apple refines native, so it comes after it although its name comes first.
    native_apple = _derive(["ios_arm64"], {"apple": APPLE, "native": NATIVE})
    asserts.equals(env, ["native", "apple"], [fragment.name for fragment in native_apple.fragments])
    asserts.equals(env, [0, 1], [fragment.rank for fragment in native_apple.fragments])
    asserts.equals(env, {"ios_arm64": ["apple"]}, native_apple.leaf_refines)

    return unittest.end(env)

def _single_platform_test(ctx):
    """A single platform has fragments when two of its lists have sources, and otherwise compiles the only one as its leaf."""
    env = unittest.begin(ctx)

    derived = _derive(["jvm"], {"common": COMMON, "jvm": JVM})
    asserts.equals(env, [("common", ["jvm"], 0, COMMON, [])], _fragments(derived))
    asserts.equals(env, {"jvm": JVM}, derived.leaf_srcs)
    asserts.equals(env, {"jvm": ["common"]}, derived.leaf_refines)

    # The sources of the platform alone are its leaf, which refines nothing.
    own = _derive(["jvm"], {"jvm": JVM})
    asserts.equals(env, [], own.fragments)
    asserts.equals(env, {"jvm": JVM}, own.leaf_srcs)
    asserts.equals(env, {"jvm": []}, own.leaf_refines)

    # The sources of one group alone are the leaf of the platform: there is no fragment.
    pruned = _derive(["jvm"], {"common": COMMON})
    asserts.equals(env, [], pruned.fragments)
    asserts.equals(env, {"jvm": COMMON}, pruned.leaf_srcs)
    asserts.equals(env, {"jvm": []}, pruned.leaf_refines)
    asserts.equals(
        env,
        """\
leaf jvm
  srcs:
    common/Platform.kt
    common/Greeting.kt
""",
        format_fragments(pruned),
    )

    # So are those of a group below common.
    pruned_apple = _derive(["ios_arm64"], {"apple": APPLE})
    asserts.equals(env, [], pruned_apple.fragments)
    asserts.equals(env, {"ios_arm64": APPLE}, pruned_apple.leaf_srcs)
    asserts.equals(env, {"ios_arm64": []}, pruned_apple.leaf_refines)

    # Two groups with sources stay two fragments, although the platform has no sources of its own.
    two_groups = _derive(["ios_arm64"], {"apple": APPLE, "common": COMMON})
    asserts.equals(
        env,
        [
            ("common", ["ios_arm64"], 0, COMMON, []),
            ("apple", ["ios_arm64"], 1, APPLE, ["common"]),
        ],
        _fragments(two_groups),
    )
    asserts.equals(env, {"ios_arm64": []}, two_groups.leaf_srcs)
    asserts.equals(env, {"ios_arm64": ["apple"]}, two_groups.leaf_refines)

    # Two platforms keep the fragment of the only group with sources.
    two_platforms = _derive(["jvm", "android"], {"common": COMMON})
    asserts.equals(env, [("common", ["jvm", "android"], 0, COMMON, [])], _fragments(two_platforms))
    asserts.equals(env, {"android": [], "jvm": []}, two_platforms.leaf_srcs)
    asserts.equals(env, {"android": ["common"], "jvm": ["common"]}, two_platforms.leaf_refines)

    return unittest.end(env)

def _alias_test(ctx):
    """The sources of an alias are a fragment named after it, which the groups and the leaves of its platforms refine."""
    env = unittest.begin(ctx)

    derived = _derive(_NON_ANDROID_PLATFORMS, _NON_ANDROID_SRCS, _NON_ANDROID_ALIASES)

    asserts.equals(
        env,
        [
            ("common", ["jvm", "android", "linux_x64", "macos_arm64", "ios_arm64"], 0, COMMON, []),
            ("non_android", ["jvm", "linux_x64", "macos_arm64", "ios_arm64"], 1, NON_ANDROID, ["common"]),
            ("apple", ["macos_arm64", "ios_arm64"], 2, APPLE, ["non_android"]),
            ("linux", ["linux_x64"], 2, LINUX, ["non_android"]),
        ],
        _fragments(derived),
    )
    asserts.equals(
        env,
        {"android": ANDROID, "ios_arm64": [], "jvm": JVM, "linux_x64": [], "macos_arm64": []},
        derived.leaf_srcs,
    )
    asserts.equals(
        env,
        {
            "android": ["common"],
            "ios_arm64": ["apple"],
            "jvm": ["non_android"],
            "linux_x64": ["linux"],
            "macos_arm64": ["apple"],
        },
        derived.leaf_refines,
    )

    # An alias without sources has no fragment: what is below it refines what is above it.
    without = _derive(_NON_ANDROID_PLATFORMS, {"apple": APPLE, "common": COMMON, "jvm": JVM}, _NON_ANDROID_ALIASES)
    asserts.equals(
        env,
        [
            ("common", ["jvm", "android", "linux_x64", "macos_arm64", "ios_arm64"], 0, COMMON, []),
            ("apple", ["macos_arm64", "ios_arm64"], 1, APPLE, ["common"]),
        ],
        _fragments(without),
    )
    asserts.equals(env, ["common"], without.leaf_refines["jvm"])

    return unittest.end(env)

def _alias_above_groups_test(ctx):
    """A group refines an alias whose platforms include its own and more, and groups of the same platforms keep the order of the hierarchy below it."""
    env = unittest.begin(ctx)

    platforms = ["jvm", "android", "ios_arm64"]
    aliases = {"non_android": ["jvm", "ios_arm64"]}

    # apple is not below the alias in the hierarchy: its platform alone orders them.
    derived = _derive(platforms, {"apple": APPLE, "common": COMMON, "non_android": NON_ANDROID}, aliases)
    asserts.equals(
        env,
        [
            ("common", ["jvm", "android", "ios_arm64"], 0, COMMON, []),
            ("non_android", ["jvm", "ios_arm64"], 1, NON_ANDROID, ["common"]),
            ("apple", ["ios_arm64"], 2, APPLE, ["non_android"]),
        ],
        _fragments(derived),
    )
    asserts.equals(
        env,
        {"android": ["common"], "ios_arm64": ["apple"], "jvm": ["non_android"]},
        derived.leaf_refines,
    )

    # native, apple and ios cover ios_arm64 alone: each refines the one above it, and native the alias.
    chain = _derive(
        platforms,
        {"apple": APPLE, "common": COMMON, "ios": IOS, "native": NATIVE, "non_android": NON_ANDROID},
        aliases,
    )
    asserts.equals(
        env,
        [
            ("common", ["jvm", "android", "ios_arm64"], 0, COMMON, []),
            ("non_android", ["jvm", "ios_arm64"], 1, NON_ANDROID, ["common"]),
            ("native", ["ios_arm64"], 2, NATIVE, ["non_android"]),
            ("apple", ["ios_arm64"], 3, APPLE, ["native"]),
            ("ios", ["ios_arm64"], 4, IOS, ["apple"]),
        ],
        _fragments(chain),
    )
    asserts.equals(env, ["ios"], chain.leaf_refines["ios_arm64"])

    return unittest.end(env)

def _incomparable_test(ctx):
    """Two aliases neither of which covers the other both refine common, and a leaf of both refines both."""
    env = unittest.begin(ctx)

    derived = _derive(_INCOMPARABLE_PLATFORMS, _INCOMPARABLE_SRCS, _INCOMPARABLE_ALIASES)

    asserts.equals(
        env,
        [
            ("common", ["jvm", "android", "linux_x64"], 0, COMMON, []),
            ("android_jvm", ["jvm", "android"], 1, ["shared/AndroidJvm.kt"], ["common"]),
            ("jvm_linux", ["jvm", "linux_x64"], 1, ["shared/JvmLinux.kt"], ["common"]),
        ],
        _fragments(derived),
    )
    asserts.equals(env, {"android": [], "jvm": JVM, "linux_x64": []}, derived.leaf_srcs)
    asserts.equals(
        env,
        {"android": ["android_jvm"], "jvm": ["android_jvm", "jvm_linux"], "linux_x64": ["jvm_linux"]},
        derived.leaf_refines,
    )

    # A group below an alias and below a group that the alias overlaps refines both.
    overlapping = _derive(
        ["jvm", "linux_x64", "macos_arm64"],
        {"common": COMMON, "jvm_linux": ["shared/JvmLinux.kt"], "linux": LINUX, "native": NATIVE},
        {"jvm_linux": ["jvm", "linux_x64"]},
    )
    asserts.equals(
        env,
        [
            ("common", ["jvm", "linux_x64", "macos_arm64"], 0, COMMON, []),
            ("jvm_linux", ["jvm", "linux_x64"], 1, ["shared/JvmLinux.kt"], ["common"]),
            ("native", ["linux_x64", "macos_arm64"], 1, NATIVE, ["common"]),
            ("linux", ["linux_x64"], 2, LINUX, ["jvm_linux", "native"]),
        ],
        _fragments(overlapping),
    )
    asserts.equals(
        env,
        {"jvm": ["jvm_linux"], "linux_x64": ["linux"], "macos_arm64": ["native"]},
        overlapping.leaf_refines,
    )

    return unittest.end(env)

def _source_order_and_untargeted_test(ctx):
    """The sources of a fragment and of a leaf keep the order they are listed in; untargeted nodes are ignored."""
    env = unittest.begin(ctx)

    derived = _derive(["jvm", "linux_x64"], {"ios": IOS, "jvm": ["d.kt", "c.kt"], "native": ["b.kt", "a.kt"]})
    asserts.equals(env, [("native", ["linux_x64"], 0, ["b.kt", "a.kt"], [])], _fragments(derived))
    asserts.equals(env, {"jvm": ["d.kt", "c.kt"], "linux_x64": []}, derived.leaf_srcs)
    asserts.equals(env, {"jvm": [], "linux_x64": ["native"]}, derived.leaf_refines)

    return unittest.end(env)

def _strip_pkg(label):
    return label.removeprefix("//pkg:")

def _format_test(ctx):
    """format_fragments renders the fragments in order with their refines, platforms and sources, then the sorted leaves."""
    env = unittest.begin(ctx)

    asserts.equals(
        env,
        """\
fragment common
  platforms: jvm, android, linux_x64, macos_arm64, ios_arm64
  srcs:
    common/Platform.kt
    common/Greeting.kt
fragment non_android
  refines: common
  platforms: jvm, linux_x64, macos_arm64, ios_arm64
  srcs:
    non_android/Greeting.nonAndroid.kt
fragment apple
  refines: non_android
  platforms: macos_arm64, ios_arm64
  srcs:
    apple/Platform.apple.kt
fragment linux
  refines: non_android
  platforms: linux_x64
  srcs:
    linux/Platform.linux.kt
leaf android
  refines: common
  srcs:
    android/Platform.android.kt
leaf ios_arm64
  refines: apple
leaf jvm
  refines: non_android
  srcs:
    jvm/Platform.jvm.kt
leaf linux_x64
  refines: linux
leaf macos_arm64
  refines: apple
""",
        format_fragments(_derive(_NON_ANDROID_PLATFORMS, _NON_ANDROID_SRCS, _NON_ANDROID_ALIASES)),
    )

    relabeled = _derive(["jvm", "android"], {"common": ["//pkg:common/A.kt"], "jvm": ["//other:B.kt"]})
    asserts.equals(
        env,
        """\
fragment common
  platforms: jvm, android
  srcs:
    common/A.kt
leaf android
  refines: common
leaf jvm
  refines: common
  srcs:
    //other:B.kt
""",
        format_fragments(relabeled, label_of = _strip_pkg),
    )

    return unittest.end(env)

def _format_incomparable_and_empty_test(ctx):
    """Several refined fragments are comma-separated, empty sections are omitted, and no platform prints nothing."""
    env = unittest.begin(ctx)

    asserts.equals(
        env,
        """\
fragment common
  platforms: jvm, android, linux_x64
  srcs:
    common/Platform.kt
    common/Greeting.kt
fragment android_jvm
  refines: common
  platforms: jvm, android
  srcs:
    shared/AndroidJvm.kt
fragment jvm_linux
  refines: common
  platforms: jvm, linux_x64
  srcs:
    shared/JvmLinux.kt
leaf android
  refines: android_jvm
leaf jvm
  refines: android_jvm, jvm_linux
  srcs:
    jvm/Platform.jvm.kt
leaf linux_x64
  refines: jvm_linux
""",
        format_fragments(_derive(_INCOMPARABLE_PLATFORMS, _INCOMPARABLE_SRCS, _INCOMPARABLE_ALIASES)),
    )

    asserts.equals(
        env,
        """\
leaf jvm
  srcs:
    jvm/Platform.jvm.kt
leaf linux_x64
""",
        format_fragments(_derive(["jvm", "linux_x64"], {"jvm": JVM})),
    )
    asserts.equals(env, "", format_fragments(derive_fragments({}, resolve_qualifiers(HIERARCHY, {}, None))))

    return unittest.end(env)

chain_test = unittest.make(_chain_test)
same_platforms_test = unittest.make(_same_platforms_test)
single_platform_test = unittest.make(_single_platform_test)
alias_test = unittest.make(_alias_test)
alias_above_groups_test = unittest.make(_alias_above_groups_test)
incomparable_test = unittest.make(_incomparable_test)
source_order_and_untargeted_test = unittest.make(_source_order_and_untargeted_test)
format_test = unittest.make(_format_test)
format_incomparable_and_empty_test = unittest.make(_format_incomparable_and_empty_test)

def derive_test_suite(name):
    unittest.suite(
        name,
        chain_test,
        same_platforms_test,
        single_platform_test,
        alias_test,
        alias_above_groups_test,
        incomparable_test,
        source_order_and_untargeted_test,
        format_test,
        format_incomparable_and_empty_test,
    )
