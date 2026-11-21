"""kt_multiplatform_library: a Kotlin Multiplatform library declared along the default hierarchy of Kotlin Multiplatform.

    COMMON = glob(["common/*.kt"])
    NON_ANDROID = glob(["non_android/*.kt"])

    kt_multiplatform_library(
        name = "shared",
        platforms = ["jvm", "android", "ios_arm64", "macos_arm64", "linux_x64"],
        srcs = COMMON,
        deps = ["@kmp_maven//:org_jetbrains_kotlinx_kotlinx_coroutines_core"],
        srcs_jvm = NON_ANDROID + glob(["jvm/*.kt"]),
        srcs_android = glob(["android/*.kt"]),
        srcs_native = NON_ANDROID,
        srcs_apple = glob(["apple/*.kt"]),
        srcs_linux = glob(["linux/*.kt"]),
        android = dict(manifest = "android/AndroidManifest.xml"),
    )

`platforms` lists the platforms of the library, leaves of the hierarchy (see hierarchy.bzl), and
`srcs_<qualifier>`, `deps_<qualifier>`, `exports_<qualifier>` and `plugins_<qualifier>` the lists of
a group or a platform of it (see declaration.bzl). Each platform compiles the lists of its lineage,
from those of the macro down to its own: above, `ios_arm64` compiles COMMON, NON_ANDROID and the
Apple sources against kotlinx.coroutines, and the JVM COMMON, NON_ANDROID and its own. The sources
of a group form one K2 fragment named after it, `common` for the srcs of the macro, and those of a
platform are its leaf fragment, named after it (see derive.bzl): COMMON is the fragment `common`,
the Apple sources `apple` and the Linux ones `linux`. NON_ANDROID, which the JVM and native both
list, is the fragment `jvm-native`: it refines `common`, and `apple`, `linux` and the leaf `jvm`
refine it. The leaves of the konan targets are empty here.

The macro declares:
- shared_fragment_<fragment>: a private kt_kmp_fragment per fragment (see fragment.bzl);
- shared_jvm: when `platforms` lists `jvm`, a kt_jvm_library of the attributes of `jvm`, whose srcs
  are the sources only the JVM compiles, whose kmp_fragments are the fragments those refine, and
  whose deps, exports and plugins are the lists of its lineage;
- shared_android: when `platforms` lists `android`, a kt_android_library of the attributes of
  `android`, the same way;
- shared_native: when `platforms` lists konan targets, a kt_native_library of the attributes of
  `native` that compiles, for the konan target of the build's platform, the sources only that
  target compiles and the fragments they refine, against the lists of its lineage; it is
  incompatible with other platforms;
- shared_srcs: a filegroup of the sources of every platform;
- shared.fragments: an executable target printing the derived fragment graph;
- shared: an alias of shared_native for a Kotlin/Native consumer building for one of the konan
  targets, of shared_android for an Android platform, and otherwise of shared_jvm, or of the only
  library declared.

The alias selects on //kotlin/native/platforms:native_<konan target>, which only matches below the
Kotlin/Native rules: they set //kotlin/settings:kotlin_platform_type to native for themselves and
their deps. So on a macOS or Linux host, whose platform is also the one of a konan target, the alias
is shared_jvm for a JVM consumer and shared_native for a native one. The lists of shared_native and
its compatibility select on the platform only (`is_<konan target>`): it is the Kotlin/Native rule,
which transitions itself.
"""

load("//kotlin/internal/jvm:kt_android_library.bzl", "kt_android_library")
load("//kotlin/internal/jvm:kt_jvm_library.bzl", "kt_jvm_library")
load("//kotlin/internal/native:library.bzl", "kt_native_library")
load(":declaration.bzl", "parse_declaration", "platform_list")
load(":derive.bzl", "derive_fragments", "format_fragments")
load(":fragment.bzl", "kt_kmp_fragment", "kt_kmp_fragments_graph")

# The lists of the library of a platform that the macro concatenates along the lineage of the
# platform; the srcs are the fragments and the leaf instead.
_LINEAGE_ATTRS = ["deps", "exports", "plugins"]

_DEFAULT = "//conditions:default"

def _is_konan_target(konan_target):
    return str(Label("//kotlin/native/platforms:is_" + konan_target))

def _native_konan_target(konan_target):
    return str(Label("//kotlin/native/platforms:native_" + konan_target))

def konan_targets_compatibility(konan_targets):
    """The branches of the target_compatible_with of a target for some konan targets: it is compatible with their platforms alone.

    Any build for the platform of a target (`is_<target>`) is compatible, whatever its Kotlin
    platform type: the native library transitions itself to Kotlin/Native.

    Args:
      konan_targets: the konan targets, e.g. `["ios_arm64", "ios_simulator_arm64"]`.

    Returns:
      The dict of a select(): no constraint on the platform of each target, and
      `@platforms//:incompatible` by default.
    """
    compatible = {_is_konan_target(target): [] for target in konan_targets}
    compatible[_DEFAULT] = [str(Label("@platforms//:incompatible"))]
    return compatible

# The parameter `native` of the macro hides the module.
def _filegroup(**kwargs):
    native.filegroup(**kwargs)

def _alias(**kwargs):
    native.alias(**kwargs)

def _as_written(label):
    return str(label)

def _strip_colon(label):
    text = str(label)
    return text[1:] if text.startswith(":") else text

def display_label(label, pkg):
    """Formats a resolved Label relative to `pkg` (`:__pkg__` of the macro's package).

    Args:
      label: a Label resolved in the package of the macro.
      pkg: the Label of `:__pkg__` in the package of the macro.

    Returns:
      `label.name` in `pkg`, `//<package>:<name>` in another package of the same repository, or
      `str(label)` in another repository.
    """
    if label.repo_name != pkg.repo_name:
        return str(label)
    if label.package == pkg.package:
        return label.name
    return "//%s:%s" % (label.package, label.name)

def _label_formatter():
    """Returns `(normalize, label_of)` for source labels in the package of the macro.

    Bazel versions without native.package_relative_label compare the labels as written and strip a
    leading `:` for display.
    """
    if not hasattr(native, "package_relative_label"):
        return _as_written, _strip_colon
    pkg = native.package_relative_label(":__pkg__")
    displayed = {}

    def _normalize(label):
        resolved = native.package_relative_label(label)
        canonical = str(resolved)
        if canonical not in displayed:
            displayed[canonical] = display_label(resolved, pkg)
        return canonical

    def _label_of(canonical):
        return displayed.get(canonical, canonical)

    return _normalize, _label_of

def _fragment_target(name, fragment):
    return "%s_fragment_%s" % (name, fragment)

def kt_multiplatform_library(
        name,
        platforms = None,
        srcs = [],
        deps = [],
        exports = [],
        plugins = [],
        jvm = None,
        android = None,
        native = None,
        visibility = None,
        tags = [],
        testonly = False,
        **kwargs):
    """Declares a Kotlin Multiplatform library: a library per platform, the fragments they share, `<name>.fragments` and an alias.

    Experimental. The library builds for the platforms of `platforms`, the leaves of the default
    hierarchy of Kotlin Multiplatform, whose inner nodes are groups:

        common
        +-- jvm
        +-- android
        +-- native
            +-- linux: linux_x64, linux_arm64
            +-- apple
                +-- macos: macos_arm64
                +-- ios: ios_arm64, ios_simulator_arm64, ios_x64

    The `srcs`, `deps`, `exports` and `plugins` of the macro are those of every platform, the ones
    of `common`. A group or a platform has its own lists, those of the platforms at or below it, as
    `<attr>_<qualifier>`, e.g. `srcs_ios`, `deps_apple`, `exports_native` or `plugins_linux_x64`.
    Each platform compiles the lists of its lineage, from `common` down to itself: the deps of
    `ios_arm64` are `deps + deps_native + deps_apple + deps_ios + deps_ios_arm64`. The sources of a
    group are a K2 fragment of the compilations of its platforms, named after the group, e.g.
    `common` for the srcs of the macro or `ios`, and those of a platform are its leaf fragment. A
    fragment refines those of the groups above it, so the `expect` declarations of a group and the
    `actual` ones of a group or a platform below it are in one module, even when both cover the
    same platforms (see derive.bzl). A label that several groups or platforms list, none above
    another, is a fragment of theirs, e.g. `jvm-native`. Running `<name>.fragments` prints the
    derived fragments, their `refines` edges, their platforms and their sources. A fragment has no
    deps: each platform compiles it against the deps of its lineage. Sources are shared by label:
    a file must be listed by the same label everywhere. A library of a single platform compiles
    its `srcs` as the fragment `common` too, with the restrictions of `kmp_fragments`.

    The macro checks the declaration when it is called and fails with what to change, e.g. for
    sources of a group none of whose platforms `platforms` lists, a list given as a select() it
    cannot read, or a label that a list repeats from a list above it in the hierarchy.

    Args:
      name: the name of the alias, and the prefix of the names of the other targets.
      platforms: the platforms to build for, in any order, e.g.
        `["jvm", "android", "ios_arm64", "ios_simulator_arm64"]`: `jvm`, `android`, and the konan
        targets `ios_arm64`, `ios_simulator_arm64`, `macos_arm64`, `linux_x64` and `linux_arm64`.
        A group, e.g. `ios`, is not a platform. The macro declares `<name>_jvm` for `jvm`,
        `<name>_android` for `android` and `<name>_native` for the konan targets.
      srcs: the sources of every platform, a list of labels, e.g. those of Gradle's `commonMain`.
        Those of only some platforms are the srcs of a group or a platform, e.g. `srcs_ios` for
        `iosMain`; a label listed by several groups or platforms, none above another, is shared by
        their platforms, e.g. Gradle's `nonAndroidMain` in `srcs_jvm` and `srcs_native`.
      deps: the deps of every platform, a list of labels. Each resolves for every platform: an alias
        selecting the variant of the platform, such as those of `kmp_maven`, or another
        kt_multiplatform_library. The deps of only some platforms are those of a group or a
        platform, e.g. `deps_jvm`.
      exports: the exports of every platform, a list of labels; like `deps`, each resolves for every
        platform.
      plugins: the Kotlin compiler plugins of every platform, a list of kt_compiler_plugin targets,
        the only kind kt_native_library takes.
      jvm: the other attributes of the kt_jvm_library `<name>_jvm`, e.g. `dict(resources = [...])`;
        its srcs, deps, exports and plugins are `srcs_jvm`, `deps_jvm`, `exports_jvm` and
        `plugins_jvm`.
      android: the other attributes of the kt_android_library `<name>_android`, e.g.
        `dict(manifest = "AndroidManifest.xml", custom_package = "org.example")`.
      native: the other attributes of the kt_native_library `<name>_native`, e.g.
        `dict(opts = ["-opt-in=kotlin.ExperimentalStdlibApi"])`, for each of its konan targets. A
        value of only some targets is a select() on
        `@rules_kotlin//kotlin/native/platforms:is_<konan target>`.
      visibility: the visibility of the targets; the fragments are private.
      tags: the tags of the targets.
      testonly: whether the targets are testonly.
      **kwargs: the lists of the groups and the platforms, `<attr>_<qualifier>`: `<attr>` is `srcs`,
        `deps`, `exports` or `plugins`, and `<qualifier>` a group, `native`, `linux`, `apple`,
        `macos` or `ios`, or a platform. Each is a list of labels; an empty one is the same as
        none. The deps, exports and plugins of `jvm` and `android`, whose libraries build a single
        platform, may also be or end with a select(). The other keyword arguments are attributes
        common to every rule, e.g. `features`, of every target.
    """
    normalize, label_of = _label_formatter()
    declaration = parse_declaration(
        platforms,
        {"deps": deps, "exports": exports, "plugins": plugins, "srcs": srcs},
        {"android": android, "jvm": jvm, "native": native},
        kwargs,
        normalize = normalize,
    )
    if declaration.error:
        fail("kt_multiplatform_library %s: %s" % (name, declaration.error))

    node_srcs = {
        node: [normalize(label) for label in labels]
        for node, labels in declaration.lists["srcs"].items()
    }
    derived = derive_fragments(node_srcs, declaration.hierarchy.lineage, declaration.targeted)
    rule_attrs = dict(declaration.rule_attrs, tags = tags, testonly = testonly, visibility = visibility)

    def _fragments(platform):
        return [":" + _fragment_target(name, fragment) for fragment in derived.leaf_refines[platform]]

    def _lineage_lists(platform):
        return {attr: platform_list(declaration, attr, platform) for attr in _LINEAGE_ATTRS}

    for fragment in derived.fragments:
        kt_kmp_fragment(
            name = _fragment_target(name, fragment.name),
            srcs = fragment.srcs,
            fragment_name = fragment.name,
            platforms = fragment.platforms,
            refines = [":" + _fragment_target(name, refined) for refined in fragment.refines],
            **dict(rule_attrs, visibility = ["//visibility:private"])
        )

    if "jvm" in declaration.targeted:
        kt_jvm_library(
            name = name + "_jvm",
            srcs = derived.leaf_srcs["jvm"],
            kmp_fragments = _fragments("jvm"),
            **dict(rule_attrs, **dict(declaration.settings["jvm"], **_lineage_lists("jvm")))
        )

    if "android" in declaration.targeted:
        kt_android_library(
            name = name + "_android",
            srcs = derived.leaf_srcs["android"],
            kmp_fragments = _fragments("android"),
            **dict(rule_attrs, **dict(declaration.settings["android"], **_lineage_lists("android")))
        )

    konan_targets = declaration.targeted.get("native", [])
    if konan_targets:
        # Per konan target: the sources only it lists, the fragments they refine, and the lists of
        # its lineage.
        branches = {attr: {} for attr in ["srcs", "kmp_fragments"] + _LINEAGE_ATTRS}
        for target in konan_targets:
            condition = _is_konan_target(target)
            branches["srcs"][condition] = derived.leaf_srcs[target]
            branches["kmp_fragments"][condition] = _fragments(target)
            for attr, labels in _lineage_lists(target).items():
                branches[attr][condition] = labels

        native_attrs = declaration.settings["native"]
        attrs = dict(rule_attrs, **native_attrs)

        # The compatibility with the konan targets comes first, then that of the macro and of native.
        target_compatible_with = select(konan_targets_compatibility(konan_targets))
        for given in [rule_attrs, native_attrs]:
            if "target_compatible_with" in given:
                target_compatible_with = target_compatible_with + given["target_compatible_with"]
        attrs["target_compatible_with"] = target_compatible_with
        for attr, attr_branches in branches.items():
            attr_branches[_DEFAULT] = []
            attrs[attr] = select(attr_branches)
        kt_native_library(
            name = name + "_native",
            **attrs
        )

    _filegroup(
        name = name + "_srcs",
        srcs = {label: None for labels in node_srcs.values() for label in labels}.keys(),
        **rule_attrs
    )

    kt_kmp_fragments_graph(
        name = name + ".fragments",
        graph = format_fragments(derived, label_of = label_of),
        **rule_attrs
    )

    actual = {}
    if "android" in declaration.targeted:
        actual[str(Label("@platforms//os:android"))] = ":%s_android" % name
    for target in konan_targets:
        actual[_native_konan_target(target)] = ":%s_native" % name
    if "jvm" in declaration.targeted:
        actual[_DEFAULT] = ":%s_jvm" % name
    elif "android" in declaration.targeted:
        actual[_DEFAULT] = ":%s_android" % name
    else:
        actual[_DEFAULT] = ":%s_native" % name
    _alias(
        name = name,
        actual = select(actual),
        **rule_attrs
    )
