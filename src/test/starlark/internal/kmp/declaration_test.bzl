"""Unit tests for the declaration of kt_multiplatform_library: its qualified lists, its settings, their checks and the lists of each platform."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:declaration.bzl", "parse_declaration", "platform_list", "unsupported_platforms")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:hierarchy.bzl", "make_hierarchy")

_SELECTED = select({"//conditions:default": [":selected"]})

_JVM_SELECTED = [":jvm"] + _SELECTED

_PARTLY_SELECTED = [":a"] + _SELECTED

_IOS_APP = ["jvm", "android", "ios_arm64", "ios_simulator_arm64"]

_SUPPORTED = "android, ios_arm64, ios_simulator_arm64, jvm, linux_arm64, linux_x64, macos_arm64"

_KONAN_TARGETS = "ios_arm64, ios_simulator_arm64, linux_arm64, linux_x64 or macos_arm64"

_SELECTED_SRCS = "must be a list of labels, not a select: the macro derives the fragments from the sources when it is called, before any select() is resolved"

# The default hierarchy with a tvOS group below apple, which has no Kotlin/Native toolchain.
_WITH_TVOS = [
    ("common", ["jvm", "android", "native"]),
    ("native", ["linux", "apple"]),
    ("linux", ["linux_x64", "linux_arm64"]),
    ("apple", ["macos", "ios", "tvos"]),
    ("macos", ["macos_arm64"]),
    ("ios", ["ios_arm64", "ios_simulator_arm64", "ios_x64"]),
    ("tvos", ["tvos_arm64", "tvos_simulator_arm64"]),
]

def _relative(label):
    """Normalizes the labels of the package as package_relative_label does for the unit tests: `:a.kt` is `a.kt`."""
    return label[1:] if label.startswith(":") else label

def _parse(platforms = _IOS_APP, common = {}, settings = {}, **kwargs):
    return parse_declaration(platforms, common, settings, kwargs, normalize = _relative)

def _declaration_test(ctx):
    """A declaration of every kind of list parses into its lists, its settings and the attributes common to every rule."""
    env = unittest.begin(ctx)

    declaration = _parse(
        platforms = ["ios_simulator_arm64", "jvm", "android", "ios_arm64"],
        common = {"deps": [":coroutines"], "srcs": ["common/Greeting.kt"]},
        settings = {
            "android": dict(custom_package = "org.example.kmpapp", manifest = "android/AndroidManifest.xml"),
            "native": dict(opts = ["-opt-in=kotlin.ExperimentalStdlibApi"]),
        },
        deps_ios = [":ios"],
        deps_ios_arm64 = [":device"],
        exports_native = [":native_api"],
        features = ["-layering_check"],
        plugins_apple = [":apple_plugin"],
        srcs_android = ["android/Platform.kt"],
        srcs_ios = ["ios/Platform.kt"],
        srcs_jvm = ["jvm/Platform.kt"],
        target_compatible_with = ["@platforms//os:macos"],
    )

    asserts.equals(env, None, declaration.error)
    asserts.equals(env, _IOS_APP, declaration.platforms)
    asserts.equals(env, ["common", "jvm", "android", "native", "apple", "ios", "ios_arm64", "ios_simulator_arm64"], list(declaration.targeted))
    asserts.equals(
        env,
        {
            "deps": {"common": [":coroutines"], "ios": [":ios"], "ios_arm64": [":device"]},
            "exports": {"native": [":native_api"]},
            "plugins": {"apple": [":apple_plugin"]},
            "srcs": {
                "android": ["android/Platform.kt"],
                "common": ["common/Greeting.kt"],
                "ios": ["ios/Platform.kt"],
                "jvm": ["jvm/Platform.kt"],
            },
        },
        declaration.lists,
    )
    asserts.equals(
        env,
        {
            "android": {"custom_package": "org.example.kmpapp", "manifest": "android/AndroidManifest.xml"},
            "jvm": {},
            "native": {"opts": ["-opt-in=kotlin.ExperimentalStdlibApi"]},
        },
        declaration.settings,
    )
    asserts.equals(
        env,
        {"features": ["-layering_check"], "target_compatible_with": ["@platforms//os:macos"]},
        declaration.rule_attrs,
    )

    return unittest.end(env)

def _platform_list_test(ctx):
    """A platform receives the lists of its lineage, from common down to itself."""
    env = unittest.begin(ctx)

    declaration = _parse(
        platforms = ["jvm", "linux_x64", "ios_arm64"],
        common = {"deps": [":common"], "srcs": ["Common.kt"]},
        deps_apple = [":apple"],
        deps_ios = [":ios"],
        deps_ios_arm64 = [":ios_arm64"],
        deps_jvm = [":jvm"],
        deps_linux = [":linux"],
        deps_linux_x64 = [":linux_x64"],
        deps_native = [":native"],
        srcs_ios = ["Ios.kt"],
    )

    asserts.equals(env, None, declaration.error)
    asserts.equals(env, [":common", ":jvm"], platform_list(declaration, "deps", "jvm"))
    asserts.equals(env, [":common", ":native", ":linux", ":linux_x64"], platform_list(declaration, "deps", "linux_x64"))
    asserts.equals(
        env,
        [":common", ":native", ":apple", ":ios", ":ios_arm64"],
        platform_list(declaration, "deps", "ios_arm64"),
    )
    asserts.equals(env, ["Common.kt", "Ios.kt"], platform_list(declaration, "srcs", "ios_arm64"))
    asserts.equals(env, ["Common.kt"], platform_list(declaration, "srcs", "linux_x64"))
    asserts.equals(env, [], platform_list(declaration, "exports", "jvm"))

    return unittest.end(env)

def _lenient_declarations_test(ctx):
    """A single platform, empty lists of nodes that are not targeted, and a select() of the JVM or Android library are accepted."""
    env = unittest.begin(ctx)

    single = _parse(platforms = ["jvm"], common = {"srcs": ["a.kt"]})
    asserts.equals(env, None, single.error)
    asserts.equals(env, {"common": ["jvm"], "jvm": ["jvm"]}, single.targeted)
    asserts.equals(env, ["a.kt"], platform_list(single, "srcs", "jvm"))

    # An empty list is the same as no argument, as a wrapper macro passing a glob() of each node gives.
    empty = _parse(platforms = ["jvm"], common = {"deps": []}, deps_linux_x64 = [], exports_native = [], srcs_ios = [], srcs_jvm = [])
    asserts.equals(env, None, empty.error)
    asserts.equals(env, {"deps": {}, "exports": {}, "plugins": {}, "srcs": {}}, empty.lists)

    # The lists of jvm and android go to a library of a single platform as they are: a select() stays last.
    selected = _parse(
        platforms = ["jvm", "android", "linux_x64"],
        common = {"deps": [":common"]},
        deps_jvm = _JVM_SELECTED,
        exports_android = _SELECTED,
    )
    asserts.equals(env, None, selected.error)
    asserts.equals(env, repr([":common"] + _JVM_SELECTED), repr(platform_list(selected, "deps", "jvm")))
    asserts.equals(env, repr([] + _SELECTED), repr(platform_list(selected, "exports", "android")))
    asserts.equals(env, [":common"], platform_list(selected, "deps", "linux_x64"))

    # Labels may repeat between nodes of different lineages, e.g. sources shared by jvm and native.
    shared = _parse(platforms = ["jvm", "linux_x64"], deps_jvm = [":lib"], deps_native = [":lib"], srcs_jvm = ["a.kt"], srcs_native = [":a.kt"])
    asserts.equals(env, None, shared.error)

    return unittest.end(env)

def _declaration_errors_test(ctx):
    """Every inconsistent declaration is reported, with the names of the hierarchy."""
    env = unittest.begin(ctx)

    for message, platforms, common, settings, kwargs in [
        ("it declares no platforms: list them in platforms, e.g. [\"jvm\", \"android\", \"ios_arm64\"]", None, {}, {}, {}),
        ("it declares no platforms: list them in platforms, e.g. [\"jvm\", \"android\", \"ios_arm64\"]", [], {}, {}, {}),
        (
            "platforms lists the group 'ios': list the platforms to build for instead, among ios_arm64, ios_simulator_arm64",
            ["jvm", "ios"],
            {},
            {},
            {},
        ),
        ("platforms lists the unknown platform 'ios_arm'; the supported ones are " + _SUPPORTED, ["ios_arm"], {}, {}, {}),
        (
            "platform 'ios_x64' is not supported yet: rules_kotlin has no Kotlin/Native toolchain for it",
            ["jvm", "ios_x64"],
            {},
            {},
            {},
        ),
        ("platforms lists 'jvm' twice", ["jvm", "android", "jvm"], {}, {}, {}),
        (
            "srcs_iso: 'iso' is neither a group nor a platform; the groups are apple, ios, linux, macos, native and the " +
            "platforms android, ios_arm64, ios_simulator_arm64, ios_x64, jvm, linux_arm64, linux_x64, macos_arm64",
            _IOS_APP,
            {},
            {},
            {"srcs_iso": ["a.kt"]},
        ),
        ("srcs_common: the sources of every platform are the srcs of the macro", _IOS_APP, {}, {}, {"srcs_common": ["a.kt"]}),
        ("deps_common: the deps of every platform are the deps of the macro", _IOS_APP, {}, {}, {"deps_common": []}),
        ("opts_ios: only srcs, deps, exports and plugins take a group or a platform", _IOS_APP, {}, {}, {"opts_ios": ["-opt"]}),
        ("resources_jvm: only srcs, deps, exports and plugins take a group or a platform", _IOS_APP, {}, {}, {"resources_jvm": []}),
        ("ios: only jvm, android and native take a dict of attributes of their library", _IOS_APP, {}, {}, {"ios": dict(opts = [])}),
        ("kmp_fragments: the macro derives it from the sources", _IOS_APP, {}, {}, {"kmp_fragments": []}),
        (
            "srcs_ios lists sources, but platforms lists no ios platform: add ios_arm64 or ios_simulator_arm64, or remove srcs_ios",
            ["jvm", "macos_arm64"],
            {},
            {},
            {"srcs_ios": ["a.kt"]},
        ),
        (
            "plugins_native lists plugins, but platforms lists no native platform: add %s, or remove plugins_native" % _KONAN_TARGETS,
            ["jvm", "android"],
            {},
            {},
            {"plugins_native": [":plugin"]},
        ),
        (
            "deps_linux_x64 lists deps, but platforms does not list linux_x64",
            ["jvm", "linux_arm64"],
            {},
            {},
            {"deps_linux_x64": [":lib"]},
        ),
        ("srcs_ios_x64 lists sources, but platforms does not list ios_x64", _IOS_APP, {}, {}, {"srcs_ios_x64": ["a.kt"]}),
        ("deps_jvm lists deps, but platforms does not list jvm", ["android"], {}, {}, {"deps_jvm": _SELECTED}),
        ("srcs_ios " + _SELECTED_SRCS, _IOS_APP, {}, {}, {"srcs_ios": _SELECTED}),
        ("srcs_jvm " + _SELECTED_SRCS, _IOS_APP, {}, {}, {"srcs_jvm": _PARTLY_SELECTED}),
        ("the srcs of the macro " + _SELECTED_SRCS, _IOS_APP, {"srcs": _SELECTED}, {}, {}),
        (
            "deps_ios must be a list of labels, not a select: only deps_jvm and deps_android may be a select(), as the " +
            "macro selects the deps of each konan target itself",
            _IOS_APP,
            {},
            {},
            {"deps_ios": _SELECTED},
        ),
        (
            "exports_ios_arm64 must be a list of labels, not a select: only exports_jvm and exports_android may be a " +
            "select(), as the macro selects the exports of each konan target itself",
            _IOS_APP,
            {},
            {},
            {"exports_ios_arm64": _PARTLY_SELECTED},
        ),
        (
            "the deps of the macro must be a list of labels, not a select: only deps_jvm and deps_android may be a " +
            "select(), as the macro selects the deps of each konan target itself",
            ["jvm", "android"],
            {"deps": _SELECTED},
            {},
            {},
        ),
        ("srcs_ios must be a list of labels, not a string", _IOS_APP, {}, {}, {"srcs_ios": "a.kt"}),
        ("srcs_ios lists a.kt twice", _IOS_APP, {}, {}, {"srcs_ios": ["a.kt", "b.kt", "a.kt"]}),
        # A label written twice in different forms is repeated once normalized, as the macro normalizes it.
        ("srcs_ios lists a.kt twice", _IOS_APP, {}, {}, {"srcs_ios": ["a.kt", ":a.kt"]}),
        ("the srcs of the macro list a.kt twice", _IOS_APP, {"srcs": ["a.kt", "a.kt"]}, {}, {}),
        (
            "deps_ios lists :lib, which deps_apple already lists",
            _IOS_APP,
            {},
            {},
            {"deps_apple": [":lib"], "deps_ios": [":other", ":lib"]},
        ),
        ("deps_jvm lists :lib, which the deps of the macro already list", _IOS_APP, {"deps": [":lib"]}, {}, {"deps_jvm": [":lib"]}),
        (
            "srcs_ios_arm64 lists :a.kt, which srcs_native already lists",
            _IOS_APP,
            {},
            {},
            {"srcs_ios_arm64": [":a.kt"], "srcs_native": ["a.kt"]},
        ),
        ("jvm must be a dict of attributes of the JVM library, not a list", ["jvm"], {}, {"jvm": []}, {}),
        (
            "android sets attributes of the Android library, but platforms does not list android",
            ["jvm"],
            {},
            {"android": dict(manifest = "AndroidManifest.xml")},
            {},
        ),
        (
            "native sets attributes of the native library, but platforms lists no native platform: add %s, or remove native" % _KONAN_TARGETS,
            ["jvm"],
            {},
            {"native": dict(opts = ["-opt"])},
            {},
        ),
        ("jvm sets srcs: pass srcs_jvm to the macro", ["jvm"], {}, {"jvm": dict(srcs = ["a.kt"])}, {}),
        ("android sets deps: pass deps_android to the macro", ["android"], {}, {"android": dict(deps = [])}, {}),
        (
            "native sets kmp_fragments, which the macro derives from the sources",
            ["linux_x64"],
            {},
            {"native": dict(kmp_fragments = [])},
            {},
        ),
    ]:
        asserts.equals(env, message, parse_declaration(platforms, common, settings, kwargs, normalize = _relative).error)

    # The first error is that of the first keyword argument in sorted order.
    asserts.equals(
        env,
        "deps_iso: 'iso' is neither a group nor a platform; the groups are apple, ios, linux, macos, native and the " +
        "platforms android, ios_arm64, ios_simulator_arm64, ios_x64, jvm, linux_arm64, linux_x64, macos_arm64",
        _parse(srcs_iso = [], opts_ios = [], deps_iso = []).error,
    )

    return unittest.end(env)

def _unsupported_platforms_test(ctx):
    """A platform below native without a konan target has no toolchain, and one below no library node has no rules."""
    env = unittest.begin(ctx)

    asserts.equals(env, {"ios_x64": "rules_kotlin has no Kotlin/Native toolchain for it"}, unsupported_platforms())
    asserts.equals(
        env,
        {"js": "rules_kotlin has no rules for it"},
        unsupported_platforms(make_hierarchy([("common", ["jvm", "native", "web"]), ("native", ["linux_x64"]), ("web", ["js"])])),
    )

    return unittest.end(env)

def _custom_hierarchy_test(ctx):
    """A group added to the hierarchy is a qualifier, propagates to its platforms and is named in the messages."""
    env = unittest.begin(ctx)

    tvos = make_hierarchy(_WITH_TVOS)
    declaration = parse_declaration(
        ["ios_arm64", "tvos_arm64"],
        {"srcs": ["Common.kt"]},
        {},
        {"deps_tvos": [":tv"], "srcs_apple": ["Apple.kt"]},
        hierarchy = tvos,
        unsupported = {},
    )
    asserts.equals(env, None, declaration.error)
    asserts.equals(env, ["Common.kt", "Apple.kt"], platform_list(declaration, "srcs", "tvos_arm64"))
    asserts.equals(env, [":tv"], platform_list(declaration, "deps", "tvos_arm64"))
    asserts.equals(env, [], platform_list(declaration, "deps", "ios_arm64"))

    asserts.equals(
        env,
        "srcs_tvos lists sources, but platforms lists no tvos platform: add tvos_arm64 or tvos_simulator_arm64, or remove srcs_tvos",
        parse_declaration(["ios_arm64"], {}, {}, {"srcs_tvos": ["a.kt"]}, hierarchy = tvos, unsupported = {}).error,
    )
    asserts.equals(
        env,
        "srcs_tv: 'tv' is neither a group nor a platform; the groups are apple, ios, linux, macos, native, tvos and the " +
        "platforms android, ios_arm64, ios_simulator_arm64, ios_x64, jvm, linux_arm64, linux_x64, macos_arm64, " +
        "tvos_arm64, tvos_simulator_arm64",
        parse_declaration(["ios_arm64"], {}, {}, {"srcs_tv": []}, hierarchy = tvos, unsupported = {}).error,
    )

    # By default, the platforms of a hierarchy are supported as rules_kotlin supports them.
    asserts.equals(
        env,
        "platform 'tvos_arm64' is not supported yet: rules_kotlin has no Kotlin/Native toolchain for it",
        parse_declaration(["tvos_arm64"], {}, {}, {}, hierarchy = tvos).error,
    )

    return unittest.end(env)

declaration_test = unittest.make(_declaration_test)
platform_list_test = unittest.make(_platform_list_test)
lenient_declarations_test = unittest.make(_lenient_declarations_test)
declaration_errors_test = unittest.make(_declaration_errors_test)
unsupported_platforms_test = unittest.make(_unsupported_platforms_test)
custom_hierarchy_test = unittest.make(_custom_hierarchy_test)

def declaration_test_suite(name):
    unittest.suite(
        name,
        declaration_test,
        platform_list_test,
        lenient_declarations_test,
        declaration_errors_test,
        unsupported_platforms_test,
        custom_hierarchy_test,
    )
