"""Unit tests for derive_fragments: the fragments, names, ranks, refines and leaves of the sources of the groups and platforms of the hierarchy."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:derive.bzl", "derive_fragments", "format_fragments", "fragment_name")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:hierarchy.bzl", "HIERARCHY", "resolve_platforms")

COMMON = ["common/Platform.kt", "common/Greeting.kt"]
NON_ANDROID = ["non_android/Greeting.nonAndroid.kt"]
NATIVE = ["native/Description.native.kt"]
APPLE = ["apple/Platform.apple.kt"]
IOS = ["ios/Platform.ios.kt"]
LINUX = ["linux/Platform.linux.kt"]
JVM = ["jvm/Platform.jvm.kt"]
ANDROID = ["android/Platform.android.kt"]

# The platforms of examples/kmp but linux_arm64 and ios_simulator_arm64, with Gradle's nonAndroidMain
# listed by the JVM and native.
_NON_ANDROID_PLATFORMS = ["jvm", "android", "ios_arm64", "macos_arm64", "linux_x64"]
_NON_ANDROID_SRCS = {
    "android": ANDROID,
    "apple": APPLE,
    "common": COMMON,
    "jvm": NON_ANDROID + JVM,
    "linux": LINUX,
    "native": NON_ANDROID,
}

def _derive(platforms, node_srcs):
    """The fragments of the sources of some nodes of the default hierarchy, for a library of `platforms`."""
    return derive_fragments(node_srcs, HIERARCHY.lineage, resolve_platforms(HIERARCHY, platforms).targeted)

def _fragments(derived):
    """The fragments as tuples, which asserts.equals compares field by field."""
    return [
        (fragment.name, fragment.owners, fragment.platforms, fragment.rank, fragment.srcs, fragment.refines)
        for fragment in derived.fragments
    ]

def _fragment_name_test(ctx):
    """A fragment is named after its owners, sorted and joined with `-`: a group alone names it."""
    env = unittest.begin(ctx)

    asserts.equals(env, "ios", fragment_name(["ios"]))
    asserts.equals(env, "jvm-native", fragment_name(["native", "jvm"]))
    asserts.equals(env, "ios_arm64-jvm-linux_x64", fragment_name(["linux_x64", "jvm", "ios_arm64"]))

    return unittest.end(env)

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
            ("common", ["common"], ["jvm", "macos_arm64", "ios_simulator_arm64"], 0, COMMON, []),
            ("native", ["native"], ["macos_arm64", "ios_simulator_arm64"], 1, NATIVE, ["common"]),
            ("apple", ["apple"], ["macos_arm64", "ios_simulator_arm64"], 2, APPLE, ["native"]),
            ("ios", ["ios"], ["ios_simulator_arm64"], 3, IOS, ["apple"]),
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
            ("common", ["common"], ["ios_arm64", "ios_simulator_arm64"], 0, COMMON, []),
            ("ios", ["ios"], ["ios_arm64", "ios_simulator_arm64"], 1, IOS, ["common"]),
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
    """A single platform compiles the srcs of the macro as the fragment common, which its leaf refines."""
    env = unittest.begin(ctx)

    derived = _derive(["jvm"], {"common": COMMON, "jvm": JVM})
    asserts.equals(env, [("common", ["common"], ["jvm"], 0, COMMON, [])], _fragments(derived))
    asserts.equals(env, {"jvm": JVM}, derived.leaf_srcs)
    asserts.equals(env, {"jvm": ["common"]}, derived.leaf_refines)

    # The sources of the platform alone are its leaf, which refines nothing.
    own = _derive(["jvm"], {"jvm": JVM})
    asserts.equals(env, [], own.fragments)
    asserts.equals(env, {"jvm": JVM}, own.leaf_srcs)
    asserts.equals(env, {"jvm": []}, own.leaf_refines)

    return unittest.end(env)

def _shared_by_jvm_and_native_test(ctx):
    """Sources the JVM and native both list are a fragment of theirs, which the native groups and the JVM leaf refine."""
    env = unittest.begin(ctx)

    derived = _derive(_NON_ANDROID_PLATFORMS, _NON_ANDROID_SRCS)

    asserts.equals(
        env,
        [
            ("common", ["common"], ["jvm", "android", "linux_x64", "macos_arm64", "ios_arm64"], 0, COMMON, []),
            ("jvm-native", ["jvm", "native"], ["jvm", "linux_x64", "macos_arm64", "ios_arm64"], 1, NON_ANDROID, ["common"]),
            ("apple", ["apple"], ["macos_arm64", "ios_arm64"], 2, APPLE, ["jvm-native"]),
            ("linux", ["linux"], ["linux_x64"], 2, LINUX, ["jvm-native"]),
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
            "jvm": ["jvm-native"],
            "linux_x64": ["linux"],
            "macos_arm64": ["apple"],
        },
        derived.leaf_refines,
    )

    return unittest.end(env)

def _incomparable_test(ctx):
    """Two shared fragments neither of which is above the other both refine common, and a leaf of both refines both."""
    env = unittest.begin(ctx)

    android_jvm = ["shared/AndroidJvm.kt"]
    jvm_linux = ["shared/JvmLinux.kt"]
    derived = _derive(
        ["jvm", "android", "linux_x64"],
        {
            "android": android_jvm,
            "common": COMMON,
            "jvm": android_jvm + jvm_linux + JVM,
            "linux_x64": jvm_linux,
        },
    )

    asserts.equals(
        env,
        [
            ("common", ["common"], ["jvm", "android", "linux_x64"], 0, COMMON, []),
            ("android-jvm", ["android", "jvm"], ["jvm", "android"], 1, android_jvm, ["common"]),
            ("jvm-linux_x64", ["jvm", "linux_x64"], ["jvm", "linux_x64"], 1, jvm_linux, ["common"]),
        ],
        _fragments(derived),
    )
    asserts.equals(env, {"android": [], "jvm": JVM, "linux_x64": []}, derived.leaf_srcs)
    asserts.equals(
        env,
        {"android": ["android-jvm"], "jvm": ["android-jvm", "jvm-linux_x64"], "linux_x64": ["jvm-linux_x64"]},
        derived.leaf_refines,
    )

    return unittest.end(env)

def _source_order_and_untargeted_test(ctx):
    """The sources of a fragment are in the order of the first node of the tree listing them; untargeted nodes are ignored."""
    env = unittest.begin(ctx)

    derived = _derive(["jvm", "linux_x64"], {"ios": IOS, "jvm": ["b.kt", "a.kt"], "native": ["a.kt", "b.kt"]})
    asserts.equals(env, [("jvm-native", ["jvm", "native"], ["jvm", "linux_x64"], 0, ["b.kt", "a.kt"], [])], _fragments(derived))
    asserts.equals(env, {"jvm": [], "linux_x64": []}, derived.leaf_srcs)
    asserts.equals(env, {"jvm": ["jvm-native"], "linux_x64": ["jvm-native"]}, derived.leaf_refines)

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
fragment jvm-native
  refines: common
  platforms: jvm, linux_x64, macos_arm64, ios_arm64
  srcs:
    non_android/Greeting.nonAndroid.kt
fragment apple
  refines: jvm-native
  platforms: macos_arm64, ios_arm64
  srcs:
    apple/Platform.apple.kt
fragment linux
  refines: jvm-native
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
  refines: jvm-native
  srcs:
    jvm/Platform.jvm.kt
leaf linux_x64
  refines: linux
leaf macos_arm64
  refines: apple
""",
        format_fragments(_derive(_NON_ANDROID_PLATFORMS, _NON_ANDROID_SRCS)),
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

    derived = _derive(
        ["jvm", "android", "linux_x64"],
        {
            "android": ["shared/AndroidJvm.kt"],
            "common": COMMON,
            "jvm": ["shared/AndroidJvm.kt", "shared/JvmLinux.kt"] + JVM,
            "linux_x64": ["shared/JvmLinux.kt"],
        },
    )
    asserts.equals(
        env,
        """\
fragment common
  platforms: jvm, android, linux_x64
  srcs:
    common/Platform.kt
    common/Greeting.kt
fragment android-jvm
  refines: common
  platforms: jvm, android
  srcs:
    shared/AndroidJvm.kt
fragment jvm-linux_x64
  refines: common
  platforms: jvm, linux_x64
  srcs:
    shared/JvmLinux.kt
leaf android
  refines: android-jvm
leaf jvm
  refines: android-jvm, jvm-linux_x64
  srcs:
    jvm/Platform.jvm.kt
leaf linux_x64
  refines: jvm-linux_x64
""",
        format_fragments(derived),
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
    asserts.equals(env, "", format_fragments(derive_fragments({}, HIERARCHY.lineage, {})))

    return unittest.end(env)

fragment_name_test = unittest.make(_fragment_name_test)
chain_test = unittest.make(_chain_test)
same_platforms_test = unittest.make(_same_platforms_test)
single_platform_test = unittest.make(_single_platform_test)
shared_by_jvm_and_native_test = unittest.make(_shared_by_jvm_and_native_test)
incomparable_test = unittest.make(_incomparable_test)
source_order_and_untargeted_test = unittest.make(_source_order_and_untargeted_test)
format_test = unittest.make(_format_test)
format_incomparable_and_empty_test = unittest.make(_format_incomparable_and_empty_test)

def derive_test_suite(name):
    unittest.suite(
        name,
        fragment_name_test,
        chain_test,
        same_platforms_test,
        single_platform_test,
        shared_by_jvm_and_native_test,
        incomparable_test,
        source_order_and_untargeted_test,
        format_test,
        format_incomparable_and_empty_test,
    )
