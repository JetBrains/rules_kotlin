"""Tests for the fragments of a multiplatform compilation.

Unit tests for plan_fragments, the pure part of collect_fragments, on structs standing in for
KtFragmentInfo, and analysis tests for kt_kmp_fragment, the target of a fragment.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:fragment.bzl", "KtFragmentInfo", "kt_kmp_fragment")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:fragments.bzl", "plan_fragments")

def _fragment(platforms, srcs = [], refines = [], name = None):
    """A struct with the fields of KtFragmentInfo that plan_fragments reads, refining the structs of `refines`.

    Its name is `name`, by default its platforms sorted and joined with `-`, and its rank is computed
    as kt_kmp_fragment computes it.
    """
    own = struct(
        name = name or "-".join(sorted(platforms)),
        platforms = tuple(sorted(platforms)),
        rank = 1 + max([refined.rank for refined in refines]) if refines else 0,
        refines = tuple([refined.name for refined in refines]),
        srcs = tuple(srcs),
        transitive_fragments = None,
    )
    return struct(
        name = own.name,
        platforms = own.platforms,
        rank = own.rank,
        refines = own.refines,
        srcs = own.srcs,
        transitive_fragments = depset(
            [own],
            transitive = [refined.transitive_fragments for refined in refines],
            order = "postorder",
        ),
    )

def _chain_test(ctx):
    """The fragments come most shared first, each after those it refines, and the leaf, named after its platform, last."""
    env = unittest.begin(ctx)

    common = _fragment(["jvm", "linux_x64", "macos_arm64"], srcs = ["shared/Platform.kt", "shared/Greeting.kt"])
    native = _fragment(["linux_x64", "macos_arm64"], srcs = ["shared/Native.kt"], refines = [common])
    plan = plan_fragments([native], "linux_x64", ["shared/Linux.kt"])

    asserts.equals(env, None, plan.error)
    asserts.equals(env, ["jvm-linux_x64-macos_arm64", "linux_x64-macos_arm64", "linux_x64"], plan.names)
    asserts.equals(
        env,
        [
            ("jvm-linux_x64-macos_arm64", ["shared/Platform.kt", "shared/Greeting.kt"]),
            ("linux_x64-macos_arm64", ["shared/Native.kt"]),
            ("linux_x64", ["shared/Linux.kt"]),
        ],
        [(fragment.name, fragment.srcs) for fragment in plan.fragments],
    )
    asserts.equals(
        env,
        ["shared/Platform.kt", "shared/Greeting.kt", "shared/Native.kt", "shared/Linux.kt"],
        plan.srcs,
    )
    asserts.equals(
        env,
        ["linux_x64-macos_arm64:jvm-linux_x64-macos_arm64", "linux_x64:linux_x64-macos_arm64"],
        plan.refines,
    )

    return unittest.end(env)

def _most_shared_first_test(ctx):
    """The order is by the number of platforms, then by rank, then by name, whatever the order of the walk; the leaf may be empty."""
    env = unittest.begin(ctx)

    common = _fragment(["jvm", "linux_arm64", "linux_x64", "macos_arm64"], srcs = ["Common.kt"])
    linux = _fragment(["jvm", "linux_arm64", "linux_x64"], srcs = ["Linux.kt"], refines = [common])
    arm = _fragment(["jvm", "linux_arm64"], srcs = ["Arm.kt"], refines = [linux])
    mac = _fragment(["jvm", "macos_arm64"], srcs = ["Mac.kt"], refines = [common])

    # The leaf refines two incomparable fragments of as many platforms: jvm-macos_arm64, which
    # refines common, ranks before jvm-linux_arm64, which refines linux.
    plan = plan_fragments([mac, arm], "jvm", [])

    asserts.equals(env, None, plan.error)
    asserts.equals(env, [1, 2], [mac.rank, arm.rank])
    asserts.equals(
        env,
        [common.name, linux.name, "jvm-macos_arm64", "jvm-linux_arm64", "jvm"],
        plan.names,
    )
    asserts.equals(env, ["Common.kt", "Linux.kt", "Mac.kt", "Arm.kt"], plan.srcs)
    asserts.equals(env, [], plan.fragments[-1].srcs)
    asserts.equals(
        env,
        [
            linux.name + ":" + common.name,
            "jvm-macos_arm64:" + common.name,
            "jvm-linux_arm64:" + linux.name,
            "jvm:jvm-macos_arm64",
            "jvm:jvm-linux_arm64",
        ],
        plan.refines,
    )

    return unittest.end(env)

def _rank_order_test(ctx):
    """Fragments of the same platforms, e.g. of the groups of a library of iOS targets only, come in the order they refine, whatever their names."""
    env = unittest.begin(ctx)

    ios = ["ios_arm64", "ios_simulator_arm64"]
    common = _fragment(ios, srcs = ["Common.kt"], name = "common")
    native = _fragment(ios, srcs = ["Native.kt"], refines = [common], name = "native")
    apple = _fragment(ios, srcs = ["Apple.kt"], refines = [native], name = "apple")
    plan = plan_fragments([apple], "ios_arm64", ["IosArm64.kt"])

    asserts.equals(env, None, plan.error)
    asserts.equals(env, [0, 1, 2], [common.rank, native.rank, apple.rank])
    asserts.equals(env, ["common", "native", "apple", "ios_arm64"], plan.names)
    asserts.equals(env, ["Common.kt", "Native.kt", "Apple.kt", "IosArm64.kt"], plan.srcs)
    asserts.equals(env, ["native:common", "apple:native", "ios_arm64:apple"], plan.refines)

    return unittest.end(env)

def _fragment_reached_twice_test(ctx):
    """A fragment that two fragments of the compilation refine is one fragment."""
    env = unittest.begin(ctx)

    common = _fragment(["android", "jvm", "linux_x64"], srcs = ["Common.kt"])
    android_jvm = _fragment(["android", "jvm"], srcs = ["AndroidJvm.kt"], refines = [common])
    jvm_linux = _fragment(["jvm", "linux_x64"], srcs = ["JvmLinux.kt"], refines = [common])
    plan = plan_fragments([android_jvm, jvm_linux], "jvm", ["Jvm.kt"])

    asserts.equals(env, None, plan.error)
    asserts.equals(env, [common.name, "android-jvm", "jvm-linux_x64", "jvm"], plan.names)
    asserts.equals(
        env,
        [
            "android-jvm:" + common.name,
            "jvm-linux_x64:" + common.name,
            "jvm:android-jvm",
            "jvm:jvm-linux_x64",
        ],
        plan.refines,
    )

    return unittest.end(env)

def _repeated_source_test(ctx):
    """A source listed twice in a fragment, e.g. directly and through a filegroup, is compiled once."""
    env = unittest.begin(ctx)

    common = _fragment(["jvm", "linux_x64"], srcs = ["shared/A.kt", "shared/A.kt"])
    plan = plan_fragments([common], "jvm", ["shared/B.kt", "shared/B.kt"])

    asserts.equals(env, None, plan.error)
    asserts.equals(env, ["shared/A.kt", "shared/B.kt"], plan.srcs)
    asserts.equals(env, [["shared/A.kt"], ["shared/B.kt"]], [fragment.srcs for fragment in plan.fragments])

    return unittest.end(env)

def _duplicate_name_test(ctx):
    """Two fragments of one name fail the compilation, which the compiler would crash on."""
    env = unittest.begin(ctx)

    a = _fragment(["jvm", "linux_x64"], srcs = ["A.kt"])
    b = _fragment(["jvm", "linux_x64"], srcs = ["B.kt"])
    plan = plan_fragments([a, b], "jvm", [])

    asserts.equals(env, "fragment names must be unique in a compilation, but two fragments are named 'jvm-linux_x64'", plan.error)

    return unittest.end(env)

def _leaf_name_of_a_fragment_test(ctx):
    """The leaf cannot take the name of a shared fragment."""
    env = unittest.begin(ctx)

    common = _fragment(["jvm", "linux_x64"])
    plan = plan_fragments([common], "jvm-linux_x64", [])

    asserts.equals(
        env,
        "fragment names must be unique in a compilation, but 'jvm-linux_x64' names both a shared fragment and the leaf",
        plan.error,
    )

    return unittest.end(env)

def _source_in_two_fragments_test(ctx):
    """A source belongs to one fragment: one file that two lists name through two labels fails."""
    env = unittest.begin(ctx)

    common = _fragment(["jvm", "linux_x64"], srcs = ["shared/Platform.kt"])
    plan = plan_fragments([common], "jvm", ["shared/Platform.kt"])

    asserts.equals(
        env,
        "the source shared/Platform.kt is in both fragment 'jvm-linux_x64' and 'jvm': a source is in one fragment, " +
        "and two lists of kt_multiplatform_library name it through different labels; list it once",
        plan.error,
    )

    return unittest.end(env)

chain_test = unittest.make(_chain_test)
most_shared_first_test = unittest.make(_most_shared_first_test)
rank_order_test = unittest.make(_rank_order_test)
fragment_reached_twice_test = unittest.make(_fragment_reached_twice_test)
repeated_source_test = unittest.make(_repeated_source_test)
duplicate_name_test = unittest.make(_duplicate_name_test)
leaf_name_of_a_fragment_test = unittest.make(_leaf_name_of_a_fragment_test)
source_in_two_fragments_test = unittest.make(_source_in_two_fragments_test)

def _fragment_info_test_impl(ctx):
    env = analysistest.begin(ctx)

    # Without fragment_name, the fragment is named after its platforms, sorted, and refines the
    # fragments of its refines, which come first in its transitive fragments.
    target = analysistest.target_under_test(env)
    info = target[KtFragmentInfo]
    asserts.equals(env, "linux_x64-macos_arm64", info.name)
    asserts.equals(env, ("linux_x64", "macos_arm64"), info.platforms)
    asserts.equals(env, 1, info.rank)
    asserts.equals(env, ("jvm-linux_x64-macos_arm64",), info.refines)
    asserts.equals(env, ["Description.native.kt"], [src.basename for src in info.srcs])
    asserts.equals(
        env,
        ["jvm-linux_x64-macos_arm64", "linux_x64-macos_arm64"],
        [fragment.name for fragment in info.transitive_fragments.to_list()],
    )
    asserts.equals(env, ["Description.native.kt"], [f.basename for f in target[DefaultInfo].files.to_list()])

    # A fragment compiles nothing by itself.
    asserts.equals(env, [], analysistest.target_actions(env))

    return analysistest.end(env)

def _named_fragment_test_impl(ctx):
    env = analysistest.begin(ctx)

    # A fragment named after a group refines one of the same platforms, and ranks after it.
    info = analysistest.target_under_test(env)[KtFragmentInfo]
    asserts.equals(env, "apple", info.name)
    asserts.equals(env, ("linux_x64", "macos_arm64"), info.platforms)
    asserts.equals(env, 2, info.rank)
    asserts.equals(env, ("linux_x64-macos_arm64",), info.refines)
    asserts.equals(
        env,
        ["jvm-linux_x64-macos_arm64", "linux_x64-macos_arm64", "apple"],
        [fragment.name for fragment in info.transitive_fragments.to_list()],
    )

    return analysistest.end(env)

def _one_platform_fragment_test_impl(ctx):
    env = analysistest.begin(ctx)

    # A fragment of a single platform, e.g. the common sources of a library of one platform.
    info = analysistest.target_under_test(env)[KtFragmentInfo]
    asserts.equals(env, "common", info.name)
    asserts.equals(env, ("jvm",), info.platforms)
    asserts.equals(env, 0, info.rank)
    asserts.equals(env, (), info.refines)

    return analysistest.end(env)

def _fragment_failure_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(env, ctx.attr.message)

    return analysistest.end(env)

fragment_info_test = analysistest.make(_fragment_info_test_impl)
named_fragment_test = analysistest.make(_named_fragment_test_impl)
one_platform_fragment_test = analysistest.make(_one_platform_fragment_test_impl)
fragment_failure_test = analysistest.make(
    _fragment_failure_test_impl,
    attrs = {"message": attr.string()},
    expect_failure = True,
)

def fragments_test_suite(name):
    """Declares fragments, and the tests of their plans and of what they provide.

    Args:
      name: the name of the generated test_suite target.
    """
    unittest.suite(
        "fragments_plan_tests",
        chain_test,
        most_shared_first_test,
        rank_order_test,
        fragment_reached_twice_test,
        repeated_source_test,
        duplicate_name_test,
        leaf_name_of_a_fragment_test,
        source_in_two_fragments_test,
    )

    kt_kmp_fragment(
        name = "frag_common",
        srcs = [
            "testdata/Greeting.kt",
            "testdata/Platform.kt",
        ],
        platforms = [
            "jvm",
            "linux_x64",
            "macos_arm64",
        ],
        tags = ["manual"],
    )
    kt_kmp_fragment(
        name = "frag_native",
        srcs = ["testdata/Description.native.kt"],
        platforms = [
            "macos_arm64",
            "linux_x64",
        ],
        refines = [":frag_common"],
        tags = ["manual"],
    )
    kt_kmp_fragment(
        name = "frag_jvm_linux",
        srcs = ["testdata/Platform.jvm.kt"],
        platforms = [
            "jvm",
            "linux_x64",
        ],
        refines = [":frag_native"],
        tags = ["manual"],
    )
    kt_kmp_fragment(
        name = "frag_apple",
        srcs = ["testdata/Platform.apple.kt"],
        fragment_name = "apple",
        platforms = [
            "linux_x64",
            "macos_arm64",
        ],
        refines = [":frag_native"],
        tags = ["manual"],
    )
    kt_kmp_fragment(
        name = "frag_one_platform",
        srcs = ["testdata/Platform.jvm.kt"],
        fragment_name = "common",
        platforms = ["jvm"],
        tags = ["manual"],
    )
    kt_kmp_fragment(
        name = "frag_repeated_platform",
        srcs = ["testdata/Platform.jvm.kt"],
        platforms = [
            "jvm",
            "jvm",
        ],
        tags = ["manual"],
    )

    fragment_info_test(
        name = "fragments_info_test",
        target_under_test = ":frag_native",
    )
    named_fragment_test(
        name = "fragments_named_test",
        target_under_test = ":frag_apple",
    )
    one_platform_fragment_test(
        name = "fragments_one_platform_test",
        target_under_test = ":frag_one_platform",
    )
    fragment_failure_test(
        name = "fragments_refine_not_superset_fails_test",
        target_under_test = ":frag_jvm_linux",
        message = "the fragment 'jvm-linux_x64' cannot refine 'linux_x64-macos_arm64', which jvm does not compile",
    )
    fragment_failure_test(
        name = "fragments_repeated_platform_fails_test",
        target_under_test = ":frag_repeated_platform",
        message = "a fragment is compiled by one or more distinct platforms, not [\"jvm\", \"jvm\"]",
    )

    native.test_suite(
        name = name,
        tests = [
            ":fragments_info_test",
            ":fragments_named_test",
            ":fragments_one_platform_test",
            ":fragments_plan_tests",
            ":fragments_refine_not_superset_fails_test",
            ":fragments_repeated_platform_fails_test",
        ],
    )
