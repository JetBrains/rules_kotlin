"""Unit tests for the qualifiers of kt_multiplatform_library: its aliases, their checks and the order of refinement."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:hierarchy.bzl", "HIERARCHY", "make_hierarchy", "resolve_platforms")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:qualifiers.bzl", "direct", "resolve_qualifiers")

_PLATFORMS = ["jvm", "android", "linux_x64", "macos_arm64", "ios_arm64", "ios_simulator_arm64"]

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

def _resolve(platforms, aliases, hierarchy = HIERARCHY):
    return resolve_qualifiers(hierarchy, resolve_platforms(hierarchy, platforms).targeted, aliases)

def _no_aliases_test(ctx):
    """Without aliases, the qualifiers are the targeted nodes, ordered as the hierarchy orders them."""
    env = unittest.begin(ctx)

    platforms = ["ios_simulator_arm64", "jvm", "ios_arm64", "android"]
    qualifiers = _resolve(platforms, None)
    asserts.equals(env, None, qualifiers.error)
    asserts.equals(
        env,
        ["common", "native", "apple", "ios", "jvm", "android", "ios_arm64", "ios_simulator_arm64"],
        qualifiers.names,
    )
    asserts.equals(env, ["jvm", "android", "ios_arm64", "ios_simulator_arm64"], qualifiers.leaves)
    asserts.equals(env, resolve_platforms(HIERARCHY, platforms).targeted, qualifiers.platforms)
    asserts.equals(env, {}, qualifiers.aliases)
    for qualifier in qualifiers.names:
        asserts.equals(env, HIERARCHY.lineage[qualifier][:-1], qualifiers.above[qualifier])
    for platform in qualifiers.leaves:
        asserts.equals(env, HIERARCHY.lineage[platform], qualifiers.of_platform[platform])

    empty = _resolve(platforms, {})
    asserts.equals(env, qualifiers.names, empty.names)
    asserts.equals(env, qualifiers.above, empty.above)

    # Groups of the same platforms keep the order of the hierarchy.
    single = _resolve(["linux_x64"], None)
    asserts.equals(env, ["common", "native", "linux", "linux_x64"], single.names)
    asserts.equals(env, ["common", "native"], single.above["linux"])
    asserts.equals(env, {"linux_x64": ["common", "native", "linux", "linux_x64"]}, single.of_platform)

    return unittest.end(env)

def _alias_test(ctx):
    """An alias is below common, and above the platforms and the groups whose platforms are some of its own."""
    env = unittest.begin(ctx)

    qualifiers = _resolve(["jvm", "android", "ios_arm64"], {"non_android": ["ios_arm64", "jvm"]})
    asserts.equals(env, None, qualifiers.error)
    asserts.equals(env, {"non_android": ["jvm", "ios_arm64"]}, qualifiers.aliases)
    asserts.equals(env, ["jvm", "ios_arm64"], qualifiers.platforms["non_android"])
    asserts.equals(
        env,
        ["common", "non_android", "jvm", "android", "native", "apple", "ios", "ios_arm64"],
        qualifiers.names,
    )
    asserts.equals(
        env,
        {
            "android": ["common"],
            # The groups of ios_arm64 alone are ordered by the hierarchy, and each is below the alias.
            "apple": ["common", "non_android", "native"],
            "common": [],
            "ios": ["common", "non_android", "native", "apple"],
            "ios_arm64": ["common", "non_android", "native", "apple", "ios"],
            "jvm": ["common", "non_android"],
            "native": ["common", "non_android"],
            "non_android": ["common"],
        },
        qualifiers.above,
    )
    asserts.equals(
        env,
        {
            "android": ["common", "android"],
            "ios_arm64": ["common", "non_android", "native", "apple", "ios", "ios_arm64"],
            "jvm": ["common", "non_android", "jvm"],
        },
        qualifiers.of_platform,
    )

    asserts.equals(env, ["non_android"], direct(qualifiers, qualifiers.above["jvm"]))
    asserts.equals(env, ["non_android"], direct(qualifiers, qualifiers.above["native"]))
    asserts.equals(env, ["ios"], direct(qualifiers, qualifiers.above["ios_arm64"]))
    asserts.equals(env, ["common"], direct(qualifiers, qualifiers.above["android"]))
    asserts.equals(env, [], direct(qualifiers, qualifiers.above["common"]))

    # Without the qualifiers in between, the ones left are directly above.
    asserts.equals(env, ["non_android"], direct(qualifiers, ["common", "non_android"]))
    asserts.equals(env, ["apple"], direct(qualifiers, ["common", "apple"]))

    return unittest.end(env)

def _overlapping_aliases_test(ctx):
    """Aliases that share a platform refine neither each other, nor a group that shares a platform with them."""
    env = unittest.begin(ctx)

    qualifiers = _resolve(
        ["jvm", "linux_x64", "macos_arm64"],
        {"jvm_macos": ["jvm", "macos_arm64"], "jvm_linux": ["jvm", "linux_x64"]},
    )
    asserts.equals(env, None, qualifiers.error)
    asserts.equals(
        env,
        ["common", "native", "jvm_linux", "jvm_macos", "jvm", "linux", "linux_x64", "apple", "macos", "macos_arm64"],
        qualifiers.names,
    )
    asserts.equals(env, ["common"], qualifiers.above["jvm_linux"])
    asserts.equals(env, ["common"], qualifiers.above["jvm_macos"])
    asserts.equals(env, ["common"], qualifiers.above["native"])
    asserts.equals(env, ["common", "jvm_linux", "jvm_macos"], qualifiers.above["jvm"])
    asserts.equals(env, ["common", "native", "jvm_linux"], qualifiers.above["linux"])
    asserts.equals(env, ["common", "native", "jvm_macos", "apple", "macos"], qualifiers.above["macos_arm64"])
    asserts.equals(env, ["common", "native", "jvm_linux", "linux", "linux_x64"], qualifiers.of_platform["linux_x64"])

    asserts.equals(env, ["jvm_linux", "jvm_macos"], direct(qualifiers, qualifiers.above["jvm"]))
    asserts.equals(env, ["native", "jvm_linux"], direct(qualifiers, qualifiers.above["linux"]))
    asserts.equals(env, ["linux"], direct(qualifiers, qualifiers.above["linux_x64"]))
    asserts.equals(env, ["macos"], direct(qualifiers, qualifiers.above["macos_arm64"]))

    # An alias whose platforms are some of those of another one refines it.
    nested = _resolve(
        ["jvm", "android", "linux_x64", "macos_arm64"],
        {"jvm_linux": ["jvm", "linux_x64"], "non_android": ["jvm", "linux_x64", "macos_arm64"]},
    )
    asserts.equals(env, None, nested.error)
    asserts.equals(env, ["common", "non_android"], nested.above["jvm_linux"])
    asserts.equals(env, ["common", "non_android"], nested.above["native"])
    asserts.equals(env, ["common", "non_android", "native", "jvm_linux"], nested.above["linux"])
    asserts.equals(env, ["native", "jvm_linux"], direct(nested, nested.above["linux"]))
    asserts.equals(env, ["jvm_linux"], direct(nested, nested.above["jvm"]))
    asserts.equals(env, ["common", "non_android", "jvm_linux", "jvm"], nested.of_platform["jvm"])

    return unittest.end(env)

def _alias_errors_test(ctx):
    """An alias that names no new set of listed platforms is reported with what to change."""
    env = unittest.begin(ctx)

    for message, aliases in [
        ("aliases must be a dict of a name to the platforms it groups, not a list", ["non_android"]),
        ("aliases must be a dict of a name to the platforms it groups, not a string", "non_android"),
        ("aliases: 'nonAndroid' is not a name of lowercase letters, digits and _", {"nonAndroid": ["jvm", "ios_arm64"]}),
        ("aliases: 'non-android' is not a name of lowercase letters, digits and _", {"non-android": ["jvm", "ios_arm64"]}),
        ("aliases: '' is not a name of lowercase letters, digits and _", {"": ["jvm", "ios_arm64"]}),
        ("aliases: 1 is not a name of lowercase letters, digits and _", {1: ["jvm", "ios_arm64"]}),
        ("aliases: 'apple' is a group of the hierarchy: give the alias another name", {"apple": ["jvm", "ios_arm64"]}),
        ("aliases: 'common' is a group of the hierarchy: give the alias another name", {"common": ["jvm", "ios_arm64"]}),
        ("aliases: 'jvm' is a platform of the hierarchy: give the alias another name", {"jvm": ["jvm", "ios_arm64"]}),
        # Also a platform that the library does not list.
        ("aliases: 'ios_x64' is a platform of the hierarchy: give the alias another name", {"ios_x64": ["jvm", "ios_arm64"]}),
        ("aliases: 'non_android' must be a list of the platforms it groups, not a string", {"non_android": "jvm"}),
        ("aliases: 'non_android' must be a list of the platforms it groups, not a NoneType", {"non_android": None}),
        ("aliases: 'non_android' must list the platforms it groups", {"non_android": []}),
        ("aliases: 'non_android' must list the names of platforms, not a int", {"non_android": ["jvm", 1]}),
        (
            "aliases: 'non_android' lists the group 'native': list its platforms instead, among ios_arm64, " +
            "ios_simulator_arm64, linux_x64, macos_arm64",
            {"non_android": ["jvm", "native"]},
        ),
        (
            "aliases: 'non_android' lists the unknown platform 'ios_arm'; the listed ones are android, ios_arm64, " +
            "ios_simulator_arm64, jvm, linux_x64, macos_arm64",
            {"non_android": ["jvm", "ios_arm"]},
        ),
        ("aliases: 'non_android' lists linux_arm64, which platforms does not list", {"non_android": ["jvm", "linux_arm64"]}),
        ("aliases: 'non_android' lists 'jvm' twice", {"non_android": ["jvm", "ios_arm64", "jvm"]}),
        (
            "aliases: 'apple_only' groups the platforms of apple: use that qualifier instead",
            {"apple_only": ["ios_arm64", "ios_simulator_arm64", "macos_arm64"]},
        ),
        (
            "aliases: 'mac' groups the platforms of macos, macos_arm64: use one of those qualifiers instead",
            {"mac": ["macos_arm64"]},
        ),
        ("aliases: 'desktop' groups jvm alone: use that qualifier instead", {"desktop": ["jvm"]}),
        (
            "aliases: 'all' groups every platform: the lists of the macro without a qualifier, e.g. srcs, are those of " +
            "every platform",
            {"all": list(_PLATFORMS)},
        ),
        (
            "aliases: 'jvm_ios' and 'ios_jvm' group the same platforms: declare one of them",
            {"jvm_ios": ["jvm", "ios_arm64"], "ios_jvm": ["ios_arm64", "jvm"]},
        ),
        # The first error is reported, the aliases taken in the order of the dict.
        (
            "aliases: 'second' must list the platforms it groups",
            {"first": ["jvm", "ios_arm64"], "second": [], "Third": ["jvm"]},
        ),
    ]:
        asserts.equals(env, message, _resolve(_PLATFORMS, aliases).error)

    # A group none of whose platforms is listed names none.
    asserts.equals(
        env,
        "aliases: 'jvm_linux' lists the group 'linux': list its platforms instead, though platforms lists none of them",
        _resolve(["jvm", "android", "ios_arm64"], {"jvm_linux": ["jvm", "linux"]}).error,
    )

    # The only alias of a library of one platform would group every platform.
    asserts.equals(
        env,
        "aliases: 'desktop' groups every platform: the lists of the macro without a qualifier, e.g. srcs, are those of " +
        "every platform",
        _resolve(["jvm"], {"desktop": ["jvm"]}).error,
    )

    return unittest.end(env)

def _custom_hierarchy_test(ctx):
    """The qualifiers follow the hierarchy they are given: a group added to it is a name no alias takes."""
    env = unittest.begin(ctx)

    hierarchy = make_hierarchy(_WITH_TVOS)
    qualifiers = _resolve(["jvm", "tvos_arm64", "ios_arm64"], {"jvm_tv": ["tvos_arm64", "jvm"]}, hierarchy)
    asserts.equals(env, None, qualifiers.error)
    asserts.equals(
        env,
        ["common", "native", "apple", "jvm_tv", "jvm", "ios", "ios_arm64", "tvos", "tvos_arm64"],
        qualifiers.names,
    )
    asserts.equals(env, ["common", "native", "apple", "jvm_tv"], qualifiers.above["tvos"])
    asserts.equals(env, ["apple", "jvm_tv"], direct(qualifiers, qualifiers.above["tvos"]))
    asserts.equals(env, ["common", "native", "apple"], qualifiers.above["ios"])

    asserts.equals(
        env,
        "aliases: 'tvos' is a group of the hierarchy: give the alias another name",
        _resolve(["jvm", "tvos_arm64", "ios_arm64"], {"tvos": ["tvos_arm64", "jvm"]}, hierarchy).error,
    )
    asserts.equals(
        env,
        "aliases: 'jvm_tv' lists the group 'tvos': list its platforms instead, among tvos_arm64, tvos_simulator_arm64",
        _resolve(["jvm", "tvos_arm64", "tvos_simulator_arm64"], {"jvm_tv": ["jvm", "tvos"]}, hierarchy).error,
    )

    # A name that the default hierarchy lacks is free there.
    asserts.equals(env, None, _resolve(["jvm", "android", "ios_arm64"], {"tvos": ["jvm", "ios_arm64"]}).error)

    return unittest.end(env)

no_aliases_test = unittest.make(_no_aliases_test)
alias_test = unittest.make(_alias_test)
overlapping_aliases_test = unittest.make(_overlapping_aliases_test)
alias_errors_test = unittest.make(_alias_errors_test)
custom_hierarchy_test = unittest.make(_custom_hierarchy_test)

def qualifiers_test_suite(name):
    unittest.suite(
        name,
        no_aliases_test,
        alias_test,
        overlapping_aliases_test,
        alias_errors_test,
        custom_hierarchy_test,
    )
