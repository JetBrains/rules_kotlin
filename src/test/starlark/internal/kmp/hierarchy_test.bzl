"""Unit tests for the hierarchy of kt_multiplatform_library: its default table, its checks and the resolution of platforms."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load(
    "//kotlin/internal/kmp:hierarchy.bzl",
    "DEFAULT_HIERARCHY",
    "HIERARCHY",
    "hierarchy_error",
    "make_hierarchy",
    "resolve_platforms",
)

# buildifier: disable=bzl-visibility
load("//kotlin/internal/native:targets.bzl", "KONAN_TARGETS")

_UNSUPPORTED = {"ios_x64": "rules_kotlin has no Kotlin/Native toolchain for it"}

_SUPPORTED = "android, ios_arm64, ios_simulator_arm64, jvm, linux_arm64, linux_x64, macos_arm64"

_SELECTED_PLATFORMS = select({"//conditions:default": ["jvm"]})

# The default hierarchy with a tvOS group below apple, as a new Apple family would add it.
_WITH_TVOS = [
    ("common", ["jvm", "android", "native"]),
    ("native", ["linux", "apple"]),
    ("linux", ["linux_x64", "linux_arm64"]),
    ("apple", ["macos", "ios", "tvos"]),
    ("macos", ["macos_arm64"]),
    ("ios", ["ios_arm64", "ios_simulator_arm64", "ios_x64"]),
    ("tvos", ["tvos_arm64", "tvos_simulator_arm64"]),
]

def _default_hierarchy_test(ctx):
    """The default table describes the default hierarchy of Kotlin Multiplatform, in tree order."""
    env = unittest.begin(ctx)

    asserts.equals(env, None, hierarchy_error(DEFAULT_HIERARCHY))
    asserts.equals(env, "common", HIERARCHY.root)
    asserts.equals(
        env,
        [
            "common",
            "jvm",
            "android",
            "native",
            "linux",
            "linux_x64",
            "linux_arm64",
            "apple",
            "macos",
            "macos_arm64",
            "ios",
            "ios_arm64",
            "ios_simulator_arm64",
            "ios_x64",
        ],
        HIERARCHY.nodes,
    )
    asserts.equals(env, ["common", "native", "linux", "apple", "macos", "ios"], HIERARCHY.groups)
    asserts.equals(
        env,
        ["jvm", "android", "linux_x64", "linux_arm64", "macos_arm64", "ios_arm64", "ios_simulator_arm64", "ios_x64"],
        HIERARCHY.platforms,
    )

    return unittest.end(env)

def _lineage_and_members_test(ctx):
    """A node has the nodes from the root down to it as lineage, and the platforms at or below it as members."""
    env = unittest.begin(ctx)

    asserts.equals(env, ["common"], HIERARCHY.lineage["common"])
    asserts.equals(env, ["common", "jvm"], HIERARCHY.lineage["jvm"])
    asserts.equals(env, ["common", "native", "apple"], HIERARCHY.lineage["apple"])
    asserts.equals(env, ["common", "native", "apple", "ios", "ios_arm64"], HIERARCHY.lineage["ios_arm64"])
    asserts.equals(env, ["common", "native", "linux", "linux_x64"], HIERARCHY.lineage["linux_x64"])

    asserts.equals(env, HIERARCHY.platforms, HIERARCHY.members["common"])
    asserts.equals(env, ["macos_arm64", "ios_arm64", "ios_simulator_arm64", "ios_x64"], HIERARCHY.members["apple"])
    asserts.equals(env, ["linux_x64", "linux_arm64"], HIERARCHY.members["linux"])
    asserts.equals(env, ["ios_arm64", "ios_simulator_arm64", "ios_x64"], HIERARCHY.members["ios"])
    asserts.equals(env, ["jvm"], HIERARCHY.members["jvm"])
    asserts.equals(env, sorted(HIERARCHY.nodes), sorted(HIERARCHY.lineage))
    asserts.equals(env, sorted(HIERARCHY.nodes), sorted(HIERARCHY.members))

    return unittest.end(env)

def _hierarchy_errors_test(ctx):
    """A table that is no tree rooted at common is reported with its first error."""
    env = unittest.begin(ctx)

    for message, groups in [
        ("the hierarchy must be a non-empty list of (group, members) pairs", []),
        ("the hierarchy must be a non-empty list of (group, members) pairs", {"common": ["jvm"]}),
        ("the entry \"common\" of the hierarchy is not a (group, members) pair", ["common"]),
        ("the entry (\"common\", \"jvm\") of the hierarchy is not a (group, members) pair", [("common", "jvm")]),
        ("'Common' is not a name of lowercase letters, digits and _", [("Common", ["jvm"])]),
        ("'ios-arm64' is not a name of lowercase letters, digits and _", [("common", ["ios-arm64"])]),
        ("'' is not a name of lowercase letters, digits and _", [("common", [""])]),
        ("1 is not a name of lowercase letters, digits and _", [("common", [1])]),
        ("the hierarchy lists the group 'common' twice", [("common", ["jvm"]), ("common", ["android"])]),
        (
            "the group 'native' has no members, so it would be both a group and a platform",
            [("common", ["jvm", "native"]), ("native", [])],
        ),
        ("the group 'common' lists 'jvm' twice", [("common", ["jvm", "android", "jvm"])]),
        (
            "'linux_x64' is a member of both 'native' and 'linux'",
            [("common", ["native", "linux"]), ("native", ["linux_x64"]), ("linux", ["linux_x64"])],
        ),
        ("the hierarchy has no group common, its root", [("all", ["jvm"])]),
        ("the group 'native' lists common, the root of the hierarchy", [("common", ["native"]), ("native", ["common"])]),
        (
            "the group 'native' is a member of no group: every group but common is a member of one",
            [("common", ["jvm"]), ("native", ["linux_x64"])],
        ),
        ("'apple' is not below common: its groups form a cycle", [("common", ["jvm"]), ("apple", ["ios"]), ("ios", ["apple"])]),
    ]:
        asserts.equals(env, message, hierarchy_error(groups))

    return unittest.end(env)

def _resolve_platforms_test(ctx):
    """The listed platforms are put in tree order, and target the nodes above them only."""
    env = unittest.begin(ctx)

    resolved = resolve_platforms(HIERARCHY, ["ios_simulator_arm64", "jvm", "ios_arm64", "android"], _UNSUPPORTED)
    asserts.equals(env, None, resolved.error)
    asserts.equals(env, ["jvm", "android", "ios_arm64", "ios_simulator_arm64"], resolved.platforms)
    asserts.equals(
        env,
        {
            "android": ["android"],
            "apple": ["ios_arm64", "ios_simulator_arm64"],
            "common": ["jvm", "android", "ios_arm64", "ios_simulator_arm64"],
            "ios": ["ios_arm64", "ios_simulator_arm64"],
            "ios_arm64": ["ios_arm64"],
            "ios_simulator_arm64": ["ios_simulator_arm64"],
            "jvm": ["jvm"],
            "native": ["ios_arm64", "ios_simulator_arm64"],
        },
        resolved.targeted,
    )
    asserts.false(env, "linux" in resolved.targeted)
    asserts.false(env, "macos" in resolved.targeted)

    single = resolve_platforms(HIERARCHY, ["linux_x64"], _UNSUPPORTED)
    asserts.equals(env, None, single.error)
    asserts.equals(env, ["linux_x64"], single.platforms)
    asserts.equals(env, ["common", "native", "linux", "linux_x64"], list(single.targeted))

    # Without unsupported platforms, any platform of the hierarchy is targeted.
    asserts.equals(env, ["ios_x64"], resolve_platforms(HIERARCHY, ["ios_x64"]).platforms)

    return unittest.end(env)

def _resolve_platforms_errors_test(ctx):
    """A missing or empty list, a group, an unknown or unsupported platform and a repeated one are reported."""
    env = unittest.begin(ctx)

    for message, platforms in [
        ("it declares no platforms: list them in platforms, e.g. [\"jvm\", \"android\", \"ios_arm64\"]", None),
        ("it declares no platforms: list them in platforms, e.g. [\"jvm\", \"android\", \"ios_arm64\"]", []),
        ("platforms must be a list of the names of platforms, not a string", "jvm"),
        ("platforms must be a list of the names of platforms, not a select", _SELECTED_PLATFORMS),
        ("platforms must list the names of platforms, not a Label", [Label("//kotlin/native/platforms:ios_arm64")]),
        (
            "platforms lists the group 'ios': list the platforms to build for instead, among ios_arm64, ios_simulator_arm64",
            ["jvm", "ios"],
        ),
        (
            "platforms lists the group 'native': list the platforms to build for instead, among ios_arm64, " +
            "ios_simulator_arm64, linux_arm64, linux_x64, macos_arm64",
            ["native"],
        ),
        ("platforms lists the group 'common': list the platforms to build for instead, among " + _SUPPORTED, ["common"]),
        ("platforms lists the unknown platform 'ios_arm'; the supported ones are " + _SUPPORTED, ["ios_arm"]),
        ("platforms lists the unknown platform 'iosArm64'; the supported ones are " + _SUPPORTED, ["jvm", "iosArm64"]),
        (
            "platforms lists the unknown platform '//kotlin/native/platforms:ios_arm64'; it takes the names of " +
            "platforms, not labels: write 'ios_arm64'",
            ["//kotlin/native/platforms:ios_arm64"],
        ),
        (
            "platforms lists the unknown platform '@platforms//os:ios'; it takes the names of platforms, not " +
            "labels, and the supported ones are " + _SUPPORTED,
            ["@platforms//os:ios"],
        ),
        ("platform 'ios_x64' is not supported yet: rules_kotlin has no Kotlin/Native toolchain for it", ["ios_x64"]),
        ("platforms lists 'jvm' twice", ["jvm", "android", "jvm"]),
    ]:
        asserts.equals(env, message, resolve_platforms(HIERARCHY, platforms, _UNSUPPORTED).error)

    # A group none of whose platforms is supported names none.
    asserts.equals(
        env,
        "platforms lists the group 'ios': list the platforms to build for instead, though none of its platforms is supported yet",
        resolve_platforms(
            HIERARCHY,
            ["ios"],
            {"ios_arm64": "no toolchain", "ios_simulator_arm64": "no toolchain", "ios_x64": "no toolchain"},
        ).error,
    )

    return unittest.end(env)

def _custom_hierarchy_test(ctx):
    """A group added to the table has its lineage, its members and its messages, whatever the order of the table."""
    env = unittest.begin(ctx)

    hierarchy = make_hierarchy(_WITH_TVOS)
    asserts.equals(env, ["common", "native", "apple", "tvos", "tvos_arm64"], hierarchy.lineage["tvos_arm64"])
    asserts.equals(
        env,
        ["macos_arm64", "ios_arm64", "ios_simulator_arm64", "ios_x64", "tvos_arm64", "tvos_simulator_arm64"],
        hierarchy.members["apple"],
    )
    asserts.equals(
        env,
        "platforms lists the group 'tvos': list the platforms to build for instead, among tvos_arm64, tvos_simulator_arm64",
        resolve_platforms(hierarchy, ["tvos"]).error,
    )
    asserts.equals(
        env,
        "platform 'tvos_arm64' is not supported yet: no toolchain",
        resolve_platforms(hierarchy, ["tvos_arm64"], {"tvos_arm64": "no toolchain"}).error,
    )
    asserts.equals(
        env,
        ["common", "native", "apple", "tvos", "tvos_simulator_arm64"],
        list(resolve_platforms(hierarchy, ["tvos_simulator_arm64"]).targeted),
    )

    # Tree order follows the tree, not the order of the table.
    reversed_table = make_hierarchy(reversed(_WITH_TVOS))
    asserts.equals(env, hierarchy.nodes, reversed_table.nodes)
    asserts.equals(env, hierarchy.lineage, reversed_table.lineage)

    return unittest.end(env)

def _konan_targets_test(ctx):
    """Every konan target rules_kotlin builds is a platform below native, so that a library can target it."""
    env = unittest.begin(ctx)

    for target in sorted(KONAN_TARGETS):
        asserts.true(env, target in HIERARCHY.platforms, "the konan target %s is no platform of the hierarchy" % target)
        asserts.true(
            env,
            "native" in HIERARCHY.lineage.get(target, []),
            "the konan target %s is not below native in the hierarchy" % target,
        )

    return unittest.end(env)

default_hierarchy_test = unittest.make(_default_hierarchy_test)
lineage_and_members_test = unittest.make(_lineage_and_members_test)
hierarchy_errors_test = unittest.make(_hierarchy_errors_test)
resolve_platforms_test = unittest.make(_resolve_platforms_test)
resolve_platforms_errors_test = unittest.make(_resolve_platforms_errors_test)
custom_hierarchy_test = unittest.make(_custom_hierarchy_test)
konan_targets_test = unittest.make(_konan_targets_test)

def hierarchy_test_suite(name):
    unittest.suite(
        name,
        default_hierarchy_test,
        lineage_and_members_test,
        hierarchy_errors_test,
        resolve_platforms_test,
        resolve_platforms_errors_test,
        custom_hierarchy_test,
        konan_targets_test,
    )
