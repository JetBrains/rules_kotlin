"""kt_multiplatform_library: a Kotlin Multiplatform library declared along the default hierarchy of Kotlin Multiplatform.

`platforms` lists the platforms of the library, leaves of the hierarchy (see hierarchy.bzl),
`aliases` names sets of them that no group of the hierarchy gathers (see qualifiers.bzl), and
`<attr>_<qualifier>` are the lists of a group, a platform or an alias (see declaration.bzl). Each
platform compiles the lists of the qualifiers covering it, and the sources of each group and alias
as a K2 fragment (see derive.bzl). With the name `shared`, the macro declares:
- shared_fragment_<fragment>: a private kt_kmp_fragment per fragment (see fragment.bzl);
- shared_jvm: when `platforms` lists `jvm`, a kt_jvm_library of the attributes of `jvm`, whose srcs
  are the sources only the JVM compiles, whose kmp_fragments are the fragments those refine, and
  whose deps, exports and plugins are the lists of the qualifiers covering `jvm`;
- shared_android: when `platforms` lists `android`, a kt_android_library of the attributes of
  `android`, the same way;
- shared_native: when `platforms` lists konan targets, a kt_native_library of the attributes of
  `native` that compiles, for the konan target of the build's platform, the sources only that
  target compiles and the fragments they refine, against the lists of the qualifiers covering it;
  it is incompatible with other platforms;
- shared_srcs: a filegroup of the sources of every platform;
- shared.fragments: an executable target printing the derived fragment graph;
- shared: an alias of shared_native for a Kotlin/Native consumer, of shared_android for an Android
  one, and otherwise of shared_jvm, or of the only library declared.

The alias selects on //kotlin/settings:android, which matches the JVM and Android rules on an
Android platform and below an Android local test, which builds for the host platform, and on
//kotlin/native/platforms:native, which only matches below the Kotlin/Native
rules (see //kotlin/internal/native:transition.bzl). A Kotlin/Native consumer building for a konan
target that `platforms` does not list gets shared_native too, which is incompatible with that
target, and so is the consumer: a build of every target skips it. The lists of shared_native and its
compatibility select on the platform only (`is_<konan target>`): it is the Kotlin/Native rule, which
transitions itself.
"""

load("//kotlin/internal/jvm:kt_android_library.bzl", "kt_android_library")
load("//kotlin/internal/jvm:kt_jvm_library.bzl", "kt_jvm_library")
load("//kotlin/internal/native:library.bzl", "kt_native_library")
load(":declaration.bzl", "parse_declaration", "platform_list")
load(":derive.bzl", "derive_fragments", "format_fragments")
load(":fragment.bzl", "kt_kmp_fragment", "kt_kmp_fragments_graph")

# The lists of the library of a platform that the macro concatenates from the qualifiers covering
# the platform; the srcs are the fragments and the leaf instead.
_CONCATENATED_ATTRS = ["deps", "exports", "plugins"]

_DEFAULT = "//conditions:default"

def _is_konan_target(konan_target):
    return str(Label("//kotlin/native/platforms:is_" + konan_target))

# Matches the Kotlin/Native rules and their deps, whatever their konan target.
_NATIVE = str(Label("//kotlin/native/platforms:native"))

# Matches the JVM and Android rules on an Android platform and below an Android local test.
_ANDROID = str(Label("//kotlin/settings:android"))

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

def konan_targets_compatible_with(konan_targets, given):
    """The target_compatible_with of the target of some konan targets, which may have constraints of its own.

    Args:
      konan_targets: the konan targets, e.g. `["ios_arm64", "ios_simulator_arm64"]`.
      given: dicts of attributes of the target, each of which may set `target_compatible_with`.

    Returns:
      The select() of `konan_targets_compatibility`, followed by the `target_compatible_with` of
      each of `given`, in their order.
    """
    target_compatible_with = select(konan_targets_compatibility(konan_targets))
    for attrs in given:
        if "target_compatible_with" in attrs:
            target_compatible_with = target_compatible_with + attrs["target_compatible_with"]
    return target_compatible_with

def konan_target_selects(konan_targets, lists_of):
    """The list attributes of the target of some konan targets, each a select() of the list of the konan target of the build's platform.

    Args:
      konan_targets: the konan targets, e.g. `["ios_arm64", "ios_simulator_arm64"]`.
      lists_of: a function of a konan target returning a dict of each list attribute to the list
        of that target; the dicts of every target have the same attributes.

    Returns:
      A dict of each attribute to a select() on `is_<konan target>` of each target, empty by
      default: the target is incompatible with other platforms.
    """
    branches = {}
    for target in konan_targets:
        condition = _is_konan_target(target)
        for attr, labels in lists_of(target).items():
            branches.setdefault(attr, {})[condition] = labels
    selects = {}
    for attr, attr_branches in branches.items():
        attr_branches[_DEFAULT] = []
        selects[attr] = select(attr_branches)
    return selects

def alias_branches(name, targeted):
    """The branches of the alias of a library: the library of each kind of consumer.

    A Kotlin/Native consumer gets the native library whatever its konan target: for a target the
    library does not list, the native library is incompatible, and so is the consumer.

    Args:
      name: the name of the macro.
      targeted: the nodes at or above the platforms of the library, as `parse_declaration` returns
        them, e.g. `jvm` and `native`.

    Returns:
      The dict of a select(): `<name>_native` below the Kotlin/Native rules, `<name>_android` on
      an Android platform and below an Android local test (`//kotlin/settings:android`), and by
      default `<name>_jvm`, or the library of the only node there is.
    """
    actual = {}
    if "android" in targeted:
        actual[_ANDROID] = ":%s_android" % name
    if "native" in targeted:
        actual[_NATIVE] = ":%s_native" % name
    if "jvm" in targeted:
        actual[_DEFAULT] = ":%s_jvm" % name
    elif "android" in targeted:
        actual[_DEFAULT] = ":%s_android" % name
    else:
        actual[_DEFAULT] = ":%s_native" % name
    return actual

# The parameter `native` of the macro hides the module.
def _filegroup(**kwargs):
    native.filegroup(**kwargs)

def _alias(**kwargs):
    native.alias(**kwargs)

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

# buildifier: disable=unnamed-macro
def label_formatter():
    """The functions resolving and displaying the source labels of a macro, in its package.

    Returns:
      `(normalize, label_of)`: `normalize` turns a label, as written in the package of the macro,
      into a string equal for equal labels, and `label_of` turns that string into the label to
      display (see `display_label`).
    """
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

def declare_fragments(name, derived, **kwargs):
    """Declares the kt_kmp_fragment target of each derived fragment, `<name>_fragment_<fragment>`.

    Args:
      name: the name of the macro.
      derived: a struct returned by `derive_fragments`.
      **kwargs: the other attributes of the targets, e.g. `tags`.
    """
    for fragment in derived.fragments:
        kt_kmp_fragment(
            name = _fragment_target(name, fragment.name),
            srcs = fragment.srcs,
            fragment_name = fragment.name,
            platforms = fragment.platforms,
            refines = [":" + _fragment_target(name, refined) for refined in fragment.refines],
            **kwargs
        )

def leaf_fragments(name, derived, platform):
    """The kmp_fragments of the target of a platform: the fragment targets its leaf refines.

    Args:
      name: the name of the macro.
      derived: a struct returned by `derive_fragments`.
      platform: a listed platform.

    Returns:
      The labels of the targets `declare_fragments` declares for the fragments directly above the
      platform.
    """
    return [":" + _fragment_target(name, fragment) for fragment in derived.leaf_refines[platform]]

def kt_multiplatform_library(
        name,
        platforms = None,
        aliases = {},
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
    `aliases` names the sets of platforms that no group gathers, e.g. `non_android` for `jvm` and
    the konan targets, and an alias has its lists as a group has: `srcs_non_android` or
    `deps_non_android`. A group, a platform or an alias is above another when the hierarchy puts it
    above, and otherwise when its platforms include those of the other and more.

    Each platform compiles the lists of the groups and aliases above it and its own, from `common`
    down to itself: the deps of `ios_arm64` are `deps + deps_non_android + deps_native +
    deps_apple + deps_ios + deps_ios_arm64`. The sources of a group or an alias are a K2 fragment
    of the compilations of its platforms, named after it, e.g. `common` for the srcs of the macro,
    `ios` or `non_android`, and those of a platform are its leaf fragment. A fragment refines those
    of the groups and aliases above it, so the `expect` declarations of one and the `actual` ones
    of a group, an alias or a platform below it are in one module, even when both cover the same
    platforms (see derive.bzl). Running `<name>.fragments` prints the derived fragments, their
    `refines` edges, their platforms and their sources. A fragment has no deps: each platform
    compiles it against its own deps. A source is in one fragment, so one list names it, by one
    label. A library of a single platform compiles its `srcs` as the fragment `common` too, with
    the restrictions of `kmp_fragments`.

    The macro checks the declaration when it is called and fails with what to change, e.g. for
    sources of a group none of whose platforms `platforms` lists, a list given as a select() it
    cannot read, a label that a list repeats from a list above it, or a source that two lists
    name, neither above the other.

    Args:
      name: the name of the alias, and the prefix of the names of the other targets. The alias is
        `<name>_native` for a Kotlin/Native consumer, `<name>_android` for a JVM or Android rule on
        an Android platform or below an Android local test
        (`@rules_kotlin//kotlin/settings:android`), and `<name>_jvm` otherwise; or the only library
        declared.
      platforms: the platforms to build for, in any order, e.g.
        `["jvm", "android", "ios_arm64", "ios_simulator_arm64"]`: `jvm`, `android`, and the konan
        targets `ios_arm64`, `ios_simulator_arm64`, `macos_arm64`, `linux_x64` and `linux_arm64`.
        A group, e.g. `ios`, is not a platform. The macro declares `<name>_jvm` for `jvm`,
        `<name>_android` for `android` and `<name>_native` for the konan targets.
      aliases: the sets of platforms that the hierarchy has no group for, a dict of the name of
        each to its platforms, e.g. `{"non_android": ["jvm", "ios_arm64", "ios_simulator_arm64"]}`.
        A name is made of lowercase letters, digits and `_`, and is not the name of a group or a
        platform. The platforms are two or more of `platforms`, and not those of a group or of
        another alias.
      srcs: the sources of every platform, a list of labels, e.g. those of Gradle's `commonMain`.
        Those of only some platforms are the srcs of a group, a platform or an alias, e.g.
        `srcs_ios` for `iosMain`, or `srcs_non_android` for a `nonAndroidMain`.
      deps: the deps of every platform, a list of labels. Each resolves for every platform: an alias
        selecting the variant of the platform, such as those of `kmp_maven`, or another
        kt_multiplatform_library. The deps of only some platforms are those of a group, a platform
        or an alias, e.g. `deps_jvm`.
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
      **kwargs: the lists of the groups, the platforms and the aliases, `<attr>_<qualifier>`:
        `<attr>` is `srcs`, `deps`, `exports` or `plugins`, and `<qualifier>` a group, `native`,
        `linux`, `apple`, `macos` or `ios`, a platform, or an alias. Each is a list of labels; an
        empty one is the same as none. The deps, exports and plugins of `jvm` and `android`, whose
        libraries build a single platform, may also be or end with a select(). The other keyword
        arguments are attributes common to every rule, e.g. `features`, of every target.
    """
    normalize, label_of = label_formatter()
    declaration = parse_declaration(
        platforms,
        {"deps": deps, "exports": exports, "plugins": plugins, "srcs": srcs},
        {"android": android, "jvm": jvm, "native": native},
        kwargs,
        aliases = aliases,
        normalize = normalize,
    )
    if declaration.error:
        fail("kt_multiplatform_library %s: %s" % (name, declaration.error))

    qualifier_srcs = {
        qualifier: [normalize(label) for label in labels]
        for qualifier, labels in declaration.lists["srcs"].items()
    }
    derived = derive_fragments(qualifier_srcs, declaration.qualifiers)
    rule_attrs = dict(declaration.rule_attrs, tags = tags, testonly = testonly, visibility = visibility)

    def _fragments(platform):
        return leaf_fragments(name, derived, platform)

    def _platform_lists(platform):
        return {attr: platform_list(declaration, attr, platform) for attr in _CONCATENATED_ATTRS}

    declare_fragments(name, derived, **dict(rule_attrs, visibility = ["//visibility:private"]))

    if "jvm" in declaration.targeted:
        jvm_attrs = dict(declaration.settings["jvm"], **_platform_lists("jvm"))

        # kt_jvm_library takes no deps without sources, which only a compilation reads: the library of
        # a JVM that compiles no source keeps them for the runtime classpath of its dependents.
        if not derived.leaf_srcs["jvm"] and not derived.leaf_refines["jvm"]:
            jvm_attrs["runtime_deps"] = jvm_attrs.get("runtime_deps", []) + jvm_attrs.pop("deps")
        kt_jvm_library(
            name = name + "_jvm",
            srcs = derived.leaf_srcs["jvm"],
            kmp_fragments = _fragments("jvm"),
            **dict(rule_attrs, **jvm_attrs)
        )

    if "android" in declaration.targeted:
        kt_android_library(
            name = name + "_android",
            srcs = derived.leaf_srcs["android"],
            kmp_fragments = _fragments("android"),
            **dict(rule_attrs, **dict(declaration.settings["android"], **_platform_lists("android")))
        )

    konan_targets = declaration.targeted.get("native", [])
    if konan_targets:
        def _native_lists(target):
            return dict(
                _platform_lists(target),
                kmp_fragments = _fragments(target),
                srcs = derived.leaf_srcs[target],
            )

        native_attrs = declaration.settings["native"]
        attrs = dict(rule_attrs, **native_attrs)

        # The compatibility with the konan targets comes first, then that of the macro and of native.
        attrs["target_compatible_with"] = konan_targets_compatible_with(konan_targets, [rule_attrs, native_attrs])
        attrs.update(konan_target_selects(konan_targets, _native_lists))
        kt_native_library(
            name = name + "_native",
            **attrs
        )

    _filegroup(
        name = name + "_srcs",
        srcs = [label for labels in qualifier_srcs.values() for label in labels],
        **rule_attrs
    )

    kt_kmp_fragments_graph(
        name = name + ".fragments",
        graph = format_fragments(derived, label_of = label_of),
        **rule_attrs
    )

    _alias(
        name = name,
        actual = select(alias_branches(name, declaration.targeted)),
        **rule_attrs
    )
