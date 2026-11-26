"""Unit tests for the declaration of kt_multiplatform_library and kt_multiplatform_test: its qualified lists, its aliases, its settings, their checks and the lists of each platform."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load(
    "//kotlin/internal/kmp:declaration.bzl",
    "TEST_NODES",
    "TEST_QUALIFIED_ATTRS",
    "parse_declaration",
    "platform_list",
    "sourceless_error",
    "unsupported_platforms",
)

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:hierarchy.bzl", "make_hierarchy")

_SELECTED = select({"//conditions:default": [":selected"]})

_JVM_SELECTED = [":jvm"] + _SELECTED

_PARTLY_SELECTED = [":a"] + _SELECTED

_IOS_APP = ["jvm", "android", "ios_arm64", "ios_simulator_arm64"]

_NON_ANDROID = {"non_android": ["jvm", "ios_arm64", "ios_simulator_arm64"]}

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

def _parse(platforms = _IOS_APP, common = {}, settings = {}, aliases = None, **kwargs):
    return parse_declaration(platforms, common, settings, kwargs, aliases = aliases, normalize = _relative)

def _parse_test(platforms = _IOS_APP, common = {}, settings = {}, aliases = None, **kwargs):
    return parse_declaration(
        platforms,
        common,
        settings,
        kwargs,
        aliases = aliases,
        normalize = _relative,
        attrs = TEST_QUALIFIED_ATTRS,
        nodes = TEST_NODES,
        kind = "test",
    )

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

def _aliases_test(ctx):
    """An alias qualifies lists as a group does, and a platform receives them between those above and below the alias."""
    env = unittest.begin(ctx)

    declaration = _parse(
        platforms = ["jvm", "android", "linux_x64", "ios_arm64"],
        aliases = {"non_android": ["ios_arm64", "jvm", "linux_x64"]},
        common = {"deps": [":common"], "srcs": ["Common.kt"]},
        deps_ios = [":ios"],
        deps_jvm = [":jvm"],
        deps_native = [":native"],
        deps_non_android = [":non_android"],
        exports_non_android = [":non_android_api"],
        plugins_non_android = [":non_android_plugin"],
        srcs_non_android = ["NonAndroid.kt"],
    )

    asserts.equals(env, None, declaration.error)
    asserts.equals(env, {"non_android": ["jvm", "linux_x64", "ios_arm64"]}, declaration.qualifiers.aliases)
    asserts.false(env, "non_android" in declaration.targeted)
    asserts.equals(
        env,
        {
            "deps": {
                "common": [":common"],
                "ios": [":ios"],
                "jvm": [":jvm"],
                "native": [":native"],
                "non_android": [":non_android"],
            },
            "exports": {"non_android": [":non_android_api"]},
            "plugins": {"non_android": [":non_android_plugin"]},
            "srcs": {"common": ["Common.kt"], "non_android": ["NonAndroid.kt"]},
        },
        declaration.lists,
    )

    # The nodes keep the order of the tree, and the aliases follow them.
    asserts.equals(env, ["common", "jvm", "native", "ios", "non_android"], list(declaration.lists["deps"]))

    asserts.equals(env, [":common", ":non_android", ":jvm"], platform_list(declaration, "deps", "jvm"))
    asserts.equals(env, [":common"], platform_list(declaration, "deps", "android"))
    asserts.equals(env, [":common", ":non_android", ":native"], platform_list(declaration, "deps", "linux_x64"))
    asserts.equals(env, [":common", ":non_android", ":native", ":ios"], platform_list(declaration, "deps", "ios_arm64"))
    asserts.equals(env, [":non_android_api"], platform_list(declaration, "exports", "jvm"))
    asserts.equals(env, [], platform_list(declaration, "exports", "android"))
    asserts.equals(env, [":non_android_plugin"], platform_list(declaration, "plugins", "ios_arm64"))
    asserts.equals(env, ["Common.kt", "NonAndroid.kt"], platform_list(declaration, "srcs", "linux_x64"))

    # An alias and a group that share a platform refine neither each other: both may list a label,
    # which the platform they share receives once, where it comes first.
    overlapping = _parse(
        platforms = ["jvm", "android", "linux_x64", "ios_arm64"],
        aliases = {"jvm_ios": ["jvm", "ios_arm64"]},
        deps_jvm_ios = [":lib", ":jvm_ios"],
        deps_native = [":native", "lib"],
    )
    asserts.equals(env, None, overlapping.error)
    asserts.equals(env, [":native", "lib", ":jvm_ios"], platform_list(overlapping, "deps", "ios_arm64"))
    asserts.equals(env, [":native", "lib"], platform_list(overlapping, "deps", "linux_x64"))
    asserts.equals(env, [":lib", ":jvm_ios"], platform_list(overlapping, "deps", "jvm"))

    # The select() of jvm stays last, after the list of the alias.
    selected = _parse(
        platforms = ["jvm", "android", "linux_x64"],
        aliases = {"jvm_linux": ["jvm", "linux_x64"]},
        deps_jvm = _JVM_SELECTED,
        deps_jvm_linux = [":jvm_linux"],
    )
    asserts.equals(env, None, selected.error)
    asserts.equals(env, repr([":jvm_linux"] + _JVM_SELECTED), repr(platform_list(selected, "deps", "jvm")))

    # An alias without lists, an empty list of an alias, and an alias named as the end of an
    # attribute common to every rule are accepted.
    unused = _parse(aliases = _NON_ANDROID, srcs_non_android = [])
    asserts.equals(env, None, unused.error)
    asserts.equals(env, {"deps": {}, "exports": {}, "plugins": {}, "srcs": {}}, unused.lists)
    suffix = _parse(aliases = {"with": ["jvm", "ios_arm64"]}, deps_with = [":lib"], target_compatible_with = ["@platforms//os:macos"])
    asserts.equals(env, None, suffix.error)
    asserts.equals(env, {"target_compatible_with": ["@platforms//os:macos"]}, suffix.rule_attrs)
    asserts.equals(env, [":lib"], platform_list(suffix, "deps", "jvm"))

    return unittest.end(env)

def _alias_errors_test(ctx):
    """The errors of the aliases are those of the declaration, and an alias is checked as the qualifier it is."""
    env = unittest.begin(ctx)

    for message, aliases, common, kwargs in [
        ("aliases must be a dict of a name to the platforms it groups, not a list", ["non_android"], {}, {}),
        (
            "aliases: 'non_android' lists linux_x64, which platforms does not list",
            {"non_android": ["jvm", "linux_x64"]},
            {},
            {},
        ),
        (
            "aliases: 'ios_only' groups the platforms of native, apple, ios: use one of those qualifiers instead",
            {"ios_only": ["ios_arm64", "ios_simulator_arm64"]},
            {},
            {},
        ),
        (
            "srcs_non_andriod: 'non_andriod' is neither a group, a platform nor an alias; the groups are apple, ios, " +
            "linux, macos, native, the platforms android, ios_arm64, ios_simulator_arm64, ios_x64, jvm, linux_arm64, " +
            "linux_x64, macos_arm64 and the aliases jvm_device, non_android",
            {"non_android": ["jvm", "ios_arm64", "ios_simulator_arm64"], "jvm_device": ["jvm", "ios_arm64"]},
            {},
            {"srcs_non_andriod": ["a.kt"]},
        ),
        ("opts_non_android: only srcs, deps, exports and plugins take an alias", _NON_ANDROID, {}, {"opts_non_android": ["-opt"]}),
        ("opts_with: only srcs, deps, exports and plugins take an alias", {"with": ["jvm", "ios_arm64"]}, {}, {"opts_with": []}),
        # The longest qualifier a keyword argument ends with is the one it means.
        ("opts_ios: only srcs, deps, exports and plugins take a group or a platform", {"os": ["jvm", "ios_arm64"]}, {}, {"opts_ios": []}),
        (
            "non_android: only jvm, android and native take a dict of attributes of their library",
            _NON_ANDROID,
            {},
            {"non_android": dict(opts = [])},
        ),
        ("srcs_non_android " + _SELECTED_SRCS, _NON_ANDROID, {}, {"srcs_non_android": _SELECTED}),
        (
            "deps_non_android must be a list of labels, not a select: only deps_jvm and deps_android may be a select(), " +
            "as the macro selects the deps of each konan target itself",
            _NON_ANDROID,
            {},
            {"deps_non_android": _SELECTED},
        ),
        ("srcs_non_android must be a list of labels, not a string", _NON_ANDROID, {}, {"srcs_non_android": "a.kt"}),
        ("srcs_non_android lists a.kt twice", _NON_ANDROID, {}, {"srcs_non_android": ["a.kt", ":a.kt"]}),
        (
            "deps_non_android lists :lib, which the deps of the macro already list",
            _NON_ANDROID,
            {"deps": [":lib"]},
            {"deps_non_android": [":lib"]},
        ),
        (
            "deps_jvm lists :lib, which deps_non_android already lists",
            _NON_ANDROID,
            {},
            {"deps_jvm": [":lib"], "deps_non_android": [":lib"]},
        ),
        # A group whose platforms are some of those of the alias is below it.
        (
            "exports_ios lists :lib, which exports_non_android already lists",
            _NON_ANDROID,
            {},
            {"exports_ios": [":lib"], "exports_non_android": [":other", "lib"]},
        ),
        (
            "srcs_ios_arm64 lists a.kt, which srcs_non_android already lists",
            _NON_ANDROID,
            {},
            {"srcs_ios_arm64": ["a.kt"], "srcs_non_android": [":a.kt"]},
        ),
        # A source that the lists of the platforms of an alias name belongs to the alias.
        (
            "srcs_ios and srcs_jvm both list a.kt: a source is in one fragment; list it in srcs_non_android alone",
            _NON_ANDROID,
            {},
            {"srcs_ios": ["a.kt"], "srcs_jvm": ["a.kt"]},
        ),
        # An alias and a group that share a platform are fragments neither of which sees the other.
        (
            "srcs_ios and srcs_jvm_device both list a.kt: a source is in one fragment; declare an alias of their " +
            "platforms, e.g. aliases = {\"ios_jvm_device\": [\"jvm\", \"ios_arm64\", \"ios_simulator_arm64\"]}, and list " +
            "it in srcs_ios_jvm_device alone",
            {"jvm_device": ["jvm", "ios_arm64"]},
            {},
            {"srcs_ios": ["a.kt"], "srcs_jvm_device": ["a.kt"]},
        ),
    ]:
        asserts.equals(
            env,
            message,
            parse_declaration(_IOS_APP, common, {}, kwargs, aliases = aliases, normalize = _relative).error,
        )

    # The platforms are checked before the aliases, and the aliases before the lists.
    asserts.equals(
        env,
        "platforms lists 'jvm' twice",
        _parse(platforms = ["jvm", "jvm"], aliases = {"Bad": []}, srcs_iso = []).error,
    )
    asserts.equals(
        env,
        "aliases: 'Bad' is not a name of lowercase letters, digits and _",
        _parse(aliases = {"Bad": []}, srcs_iso = []).error,
    )

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

    # The deps, exports and plugins of lists neither of which is above the other may repeat a label.
    shared = _parse(
        platforms = ["jvm", "linux_x64"],
        deps_jvm = [":lib"],
        deps_native = [":lib"],
        exports_jvm = [":lib"],
        exports_linux_x64 = [":lib"],
        plugins_jvm = [":plugin"],
        plugins_linux = [":plugin"],
    )
    asserts.equals(env, None, shared.error)
    asserts.equals(env, [":lib"], platform_list(shared, "deps", "jvm"))
    asserts.equals(env, [":lib"], platform_list(shared, "deps", "linux_x64"))

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
            "srcs_iso: 'iso' is neither a group, a platform nor an alias; the groups are apple, ios, linux, macos, native " +
            "and the platforms android, ios_arm64, ios_simulator_arm64, ios_x64, jvm, linux_arm64, linux_x64, macos_arm64",
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
        # A source that two lists name, neither above the other, belongs to the list of the platforms of both.
        (
            "srcs_jvm and srcs_native both list :a.kt: a source is in one fragment; list it in the srcs of the macro alone",
            ["jvm", "linux_x64"],
            {},
            {},
            {"srcs_jvm": ["a.kt"], "srcs_native": [":a.kt"]},
        ),
        (
            "srcs_ios_arm64 and srcs_ios_simulator_arm64 both list a.kt: a source is in one fragment; list it in " +
            "srcs_ios alone",
            _IOS_APP,
            {},
            {},
            {"srcs_ios_arm64": ["b.kt", "a.kt"], "srcs_ios_simulator_arm64": ["a.kt"]},
        ),
        # Of the groups of the platforms of both, the lowest one.
        (
            "srcs_ios_arm64 and srcs_ios_simulator_arm64 both list a.kt: a source is in one fragment; list it in " +
            "srcs_ios alone",
            ["ios_arm64", "ios_simulator_arm64"],
            {},
            {},
            {"srcs_ios_arm64": ["a.kt"], "srcs_ios_simulator_arm64": ["a.kt"]},
        ),
        (
            "srcs_jvm and srcs_native both list a.kt: a source is in one fragment; declare an alias of their " +
            "platforms, e.g. aliases = {\"jvm_native\": [\"jvm\", \"ios_arm64\", \"ios_simulator_arm64\"]}, and list it " +
            "in srcs_jvm_native alone",
            _IOS_APP,
            {},
            {},
            {"srcs_jvm": ["a.kt"], "srcs_native": ["a.kt"]},
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
        "deps_iso: 'iso' is neither a group, a platform nor an alias; the groups are apple, ios, linux, macos, native " +
        "and the platforms android, ios_arm64, ios_simulator_arm64, ios_x64, jvm, linux_arm64, linux_x64, macos_arm64",
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
        "srcs_tv: 'tv' is neither a group, a platform nor an alias; the groups are apple, ios, linux, macos, native, tvos " +
        "and the platforms android, ios_arm64, ios_simulator_arm64, ios_x64, jvm, linux_arm64, linux_x64, macos_arm64, " +
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

def _test_declaration_test(ctx):
    """The declaration of a test has the srcs, deps and plugins of a library, no exports, a dict of attributes of the iOS test, and messages that call its targets tests."""
    env = unittest.begin(ctx)

    declaration = _parse_test(
        aliases = {"count": ["jvm", "ios_arm64"]},
        common = {"deps": [":kotlin_test"], "srcs": ["commonTest/GreetingTest.kt"]},
        settings = {
            # The attributes of the iOS test are those of a rule of another ruleset, which the
            # test macro checks: its deps are no list of a qualifier.
            "ios": dict(
                minimum_os_version = "15.0",
                deps = [":bundled"],
            ),
            "jvm": dict(jvm_flags = ["-Xmx1g"]),
        },
        deps_jvm = [":junit"],
        env_inherit = ["HOME"],
        plugins_native = [":plugin"],
        shard_count = 2,
        size = "small",
        srcs_count = ["countTest/Helper.kt"],
        srcs_ios = ["iosTest/Helper.kt"],
    )

    asserts.equals(env, None, declaration.error)
    asserts.equals(
        env,
        {
            "deps": {"common": [":kotlin_test"], "jvm": [":junit"]},
            "plugins": {"native": [":plugin"]},
            "srcs": {
                "common": ["commonTest/GreetingTest.kt"],
                "count": ["countTest/Helper.kt"],
                "ios": ["iosTest/Helper.kt"],
            },
        },
        declaration.lists,
    )
    asserts.equals(
        env,
        {
            "android": {},
            "ios": {"deps": [":bundled"], "minimum_os_version": "15.0"},
            "jvm": {"jvm_flags": ["-Xmx1g"]},
            "native": {},
        },
        declaration.settings,
    )
    asserts.equals(env, ["ios_arm64", "ios_simulator_arm64"], declaration.targeted["ios"])

    # Without iOS targets, the test macro may still get an empty dict for them.
    for ios in [None, {}]:
        asserts.equals(env, {}, _parse_test(platforms = ["jvm", "linux_x64"], settings = {"ios": ios}).settings["ios"])

    # The attributes of every test that end with the name of an alias are not lists of the alias.
    asserts.equals(env, {"env_inherit": ["HOME"], "shard_count": 2, "size": "small"}, declaration.rule_attrs)
    asserts.equals(env, [":kotlin_test", ":junit"], platform_list(declaration, "deps", "jvm"))
    asserts.equals(env, [":plugin"], platform_list(declaration, "plugins", "ios_arm64"))

    for message, platforms, settings, kwargs in [
        ("exports: a test has no exports; its lists are srcs, deps and plugins", _IOS_APP, {}, {"exports": [":api"]}),
        ("exports_jvm: a test has no exports; its lists are srcs, deps and plugins", _IOS_APP, {}, {"exports_jvm": [":api"]}),
        ("jvm sets exports: a test has no exports", ["jvm"], {"jvm": dict(exports = [":api"])}, {}),
        ("jvm sets deps: pass deps_jvm to the macro", ["jvm"], {"jvm": dict(deps = [])}, {}),
        ("jvm must be a dict of attributes of the JVM test, not a list", ["jvm"], {"jvm": []}, {}),
        (
            "android sets attributes of the Android test, but platforms does not list android",
            ["jvm"],
            {"android": dict(manifest = "AndroidManifest.xml")},
            {},
        ),
        (
            "native sets attributes of the native test, but platforms lists no native platform: add %s, or remove native" % _KONAN_TARGETS,
            ["jvm"],
            {"native": dict(opts = ["-opt"])},
            {},
        ),
        ("native sets kmp_fragments, which the macro derives from the sources", ["linux_x64"], {"native": dict(kmp_fragments = [])}, {}),
        ("apple: only jvm, android, native and ios take a dict of attributes of their test", _IOS_APP, {}, {"apple": dict(opts = [])}),
        ("ios must be a dict of attributes of the iOS test, not a string", _IOS_APP, {"ios": "15.0"}, {}),
    ] + [
        # Whatever the attributes, as the macro checks them once it declares the iOS test.
        (
            "ios sets attributes of the iOS test, but platforms lists no ios platform: add ios_arm64 or ios_simulator_arm64, or remove ios",
            ["jvm", "macos_arm64"],
            {"ios": ios},
            {},
        )
        for ios in [dict(minimum_os_version = "15.0"), dict(deps = [":bundled"])]
    ] + [
        ("opts_ios: only srcs, deps and plugins take a group or a platform", _IOS_APP, {}, {"opts_ios": []}),
        ("srcs_jvm lists sources, but platforms does not list jvm", ["linux_x64"], {}, {"srcs_jvm": ["a.kt"]}),
    ]:
        asserts.equals(
            env,
            message,
            _parse_test(platforms = platforms, settings = settings, **kwargs).error,
        )
    asserts.equals(
        env,
        "opts_non_android: only srcs, deps and plugins take an alias",
        _parse_test(aliases = _NON_ANDROID, opts_non_android = ["-opt"]).error,
    )

    # A library takes exports, and its messages call its targets libraries.
    asserts.equals(env, None, _parse(exports_jvm = [":api"]).error)

    return unittest.end(env)

def _sourceless_error_test(ctx):
    """The error of a platform without sources names the lists of the qualifiers covering it, from common down."""
    env = unittest.begin(ctx)

    declaration = _parse_test(
        platforms = ["jvm", "linux_x64", "ios_arm64"],
        aliases = {"jvm_linux": ["jvm", "linux_x64"]},
        srcs_jvm = ["jvmTest/GreetingTest.kt"],
    )
    asserts.equals(env, None, declaration.error)
    asserts.equals(
        env,
        "linux_x64 has no sources: list some in the srcs of the macro, srcs_native, srcs_jvm_linux, srcs_linux or " +
        "srcs_linux_x64, or remove linux_x64 from platforms",
        sourceless_error(declaration, "linux_x64"),
    )
    asserts.equals(
        env,
        "ios_arm64 has no sources: list some in the srcs of the macro, srcs_native, srcs_apple, srcs_ios or " +
        "srcs_ios_arm64, or remove ios_arm64 from platforms",
        sourceless_error(declaration, "ios_arm64"),
    )

    return unittest.end(env)

declaration_test = unittest.make(_declaration_test)
test_declaration_test = unittest.make(_test_declaration_test)
sourceless_error_test = unittest.make(_sourceless_error_test)
platform_list_test = unittest.make(_platform_list_test)
aliases_test = unittest.make(_aliases_test)
alias_errors_test = unittest.make(_alias_errors_test)
lenient_declarations_test = unittest.make(_lenient_declarations_test)
declaration_errors_test = unittest.make(_declaration_errors_test)
unsupported_platforms_test = unittest.make(_unsupported_platforms_test)
custom_hierarchy_test = unittest.make(_custom_hierarchy_test)

def declaration_test_suite(name):
    unittest.suite(
        name,
        declaration_test,
        test_declaration_test,
        sourceless_error_test,
        platform_list_test,
        aliases_test,
        alias_errors_test,
        lenient_declarations_test,
        declaration_errors_test,
        unsupported_platforms_test,
        custom_hierarchy_test,
    )
