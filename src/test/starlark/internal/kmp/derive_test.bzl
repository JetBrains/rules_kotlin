"""Unit tests for derive_fragments: the fragments, names, refines and leaves of the sources each platform lists."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:derive.bzl", "derive_fragments", "fragment_name")

COMMON = ["common/Platform.kt", "common/Greeting.kt"]
NON_ANDROID = ["non_android/Greeting.nonAndroid.kt"]
APPLE = ["apple/Platform.apple.kt"]
JVM = ["jvm/Platform.jvm.kt"]
ANDROID = ["android/Platform.android.kt"]

def _fragments(derived):
    """The fragments as tuples, which asserts.equals compares field by field."""
    return [(fragment.name, fragment.platforms, fragment.srcs, fragment.refines) for fragment in derived.fragments]

def _fragment_name_test(ctx):
    """A fragment is named after its platforms, sorted and joined with `-`."""
    env = unittest.begin(ctx)

    asserts.equals(env, "android-jvm", fragment_name(["jvm", "android"]))
    asserts.equals(env, "ios_arm64-jvm-linux_x64", fragment_name(["linux_x64", "jvm", "ios_arm64"]))

    return unittest.end(env)

def _common_and_leaves_test(ctx):
    """The sources of every platform are one fragment, and those of one platform its leaf, which refines it."""
    env = unittest.begin(ctx)

    derived = derive_fragments({
        "android": COMMON + ANDROID,
        "jvm": COMMON + JVM,
    })

    asserts.equals(env, [("android-jvm", ["android", "jvm"], COMMON, [])], _fragments(derived))
    asserts.equals(env, {"android": ANDROID, "jvm": JVM}, derived.leaf_srcs)
    asserts.equals(env, {"android": ["android-jvm"], "jvm": ["android-jvm"]}, derived.leaf_refines)

    return unittest.end(env)

def _three_level_chain_test(ctx):
    """Nested sets of platforms refine the set directly above them only, and the Apple leaves are empty."""
    env = unittest.begin(ctx)

    derived = derive_fragments({
        "android": COMMON + ANDROID,
        "ios_arm64": COMMON + NON_ANDROID + APPLE,
        "jvm": COMMON + NON_ANDROID + JVM,
        "macos_arm64": COMMON + NON_ANDROID + APPLE,
    })

    common = "android-ios_arm64-jvm-macos_arm64"
    non_android = "ios_arm64-jvm-macos_arm64"
    apple = "ios_arm64-macos_arm64"
    asserts.equals(
        env,
        [
            (common, ["android", "ios_arm64", "jvm", "macos_arm64"], COMMON, []),
            (non_android, ["ios_arm64", "jvm", "macos_arm64"], NON_ANDROID, [common]),
            (apple, ["ios_arm64", "macos_arm64"], APPLE, [non_android]),
        ],
        _fragments(derived),
    )
    asserts.equals(
        env,
        {"android": ANDROID, "ios_arm64": [], "jvm": JVM, "macos_arm64": []},
        derived.leaf_srcs,
    )
    asserts.equals(
        env,
        {"android": [common], "ios_arm64": [apple], "jvm": [non_android], "macos_arm64": [apple]},
        derived.leaf_refines,
    )

    return unittest.end(env)

def _incomparable_sets_test(ctx):
    """Two sets of platforms neither of which contains the other both refine the common one, and a leaf of both refines both."""
    env = unittest.begin(ctx)

    android_jvm = ["shared/AndroidJvm.kt"]
    jvm_linux = ["shared/JvmLinux.kt"]
    derived = derive_fragments({
        "android": COMMON + android_jvm,
        "jvm": COMMON + android_jvm + jvm_linux + JVM,
        "linux_x64": COMMON + jvm_linux,
    })

    common = "android-jvm-linux_x64"
    asserts.equals(
        env,
        [
            (common, ["android", "jvm", "linux_x64"], COMMON, []),
            ("android-jvm", ["android", "jvm"], android_jvm, [common]),
            ("jvm-linux_x64", ["jvm", "linux_x64"], jvm_linux, [common]),
        ],
        _fragments(derived),
    )
    asserts.equals(
        env,
        {"android": ["android-jvm"], "jvm": ["android-jvm", "jvm-linux_x64"], "linux_x64": ["jvm-linux_x64"]},
        derived.leaf_refines,
    )
    asserts.equals(env, {"android": [], "jvm": JVM, "linux_x64": []}, derived.leaf_srcs)

    return unittest.end(env)

def _identical_sets_collapse_test(ctx):
    """Sources that the same platforms list are one fragment, whichever group of sources they came from."""
    env = unittest.begin(ctx)

    derived = derive_fragments({
        "jvm": COMMON + NON_ANDROID,
        "linux_x64": COMMON + NON_ANDROID,
    })

    asserts.equals(env, [("jvm-linux_x64", ["jvm", "linux_x64"], COMMON + NON_ANDROID, [])], _fragments(derived))
    asserts.equals(env, {"jvm": [], "linux_x64": []}, derived.leaf_srcs)
    asserts.equals(env, {"jvm": ["jvm-linux_x64"], "linux_x64": ["jvm-linux_x64"]}, derived.leaf_refines)

    return unittest.end(env)

def _single_platform_test(ctx):
    """A single platform has no fragment: its sources are its leaf, which refines nothing."""
    env = unittest.begin(ctx)

    derived = derive_fragments({"jvm": COMMON + JVM})

    asserts.equals(env, [], derived.fragments)
    asserts.equals(env, {"jvm": COMMON + JVM}, derived.leaf_srcs)
    asserts.equals(env, {"jvm": []}, derived.leaf_refines)

    return unittest.end(env)

def _empty_leaf_test(ctx):
    """A platform without sources of its own has an empty leaf, and one without sources refines nothing."""
    env = unittest.begin(ctx)

    derived = derive_fragments({
        "android": COMMON,
        "jvm": COMMON + JVM,
        "linux_x64": [],
    })

    asserts.equals(env, [("android-jvm", ["android", "jvm"], COMMON, [])], _fragments(derived))
    asserts.equals(env, {"android": [], "jvm": JVM, "linux_x64": []}, derived.leaf_srcs)
    asserts.equals(env, {"android": ["android-jvm"], "jvm": ["android-jvm"], "linux_x64": []}, derived.leaf_refines)

    return unittest.end(env)

def _source_order_test(ctx):
    """The sources of a fragment are in the order of the first of its platforms by name."""
    env = unittest.begin(ctx)

    derived = derive_fragments({
        "android": ["b.kt", "a.kt"],
        "jvm": ["a.kt", "b.kt"],
    })

    asserts.equals(env, ["b.kt", "a.kt"], derived.fragments[0].srcs)

    return unittest.end(env)

fragment_name_test = unittest.make(_fragment_name_test)
common_and_leaves_test = unittest.make(_common_and_leaves_test)
three_level_chain_test = unittest.make(_three_level_chain_test)
incomparable_sets_test = unittest.make(_incomparable_sets_test)
identical_sets_collapse_test = unittest.make(_identical_sets_collapse_test)
single_platform_test = unittest.make(_single_platform_test)
empty_leaf_test = unittest.make(_empty_leaf_test)
source_order_test = unittest.make(_source_order_test)

def derive_test_suite(name):
    unittest.suite(
        name,
        fragment_name_test,
        common_and_leaves_test,
        three_level_chain_test,
        incomparable_sets_test,
        identical_sets_collapse_test,
        single_platform_test,
        empty_leaf_test,
        source_order_test,
    )
