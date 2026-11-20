"""kt_multiplatform_library: a Kotlin Multiplatform library whose K2 fragments follow from the sources each platform compiles.

    COMMON = glob(["common/*.kt"])
    NON_ANDROID = glob(["non_android/*.kt"])

    kt_multiplatform_library(
        name = "shared",
        srcs = COMMON,
        deps = ["@kmp_maven//:org_jetbrains_kotlinx_kotlinx_coroutines_core"],
        jvm = dict(srcs = NON_ANDROID + glob(["jvm/*.kt"])),
        android = dict(srcs = glob(["android/*.kt"]), manifest = "android/AndroidManifest.xml"),
        native = {
            "apple": dict(srcs = NON_ANDROID + glob(["apple/*.kt"]), targets = ["ios_arm64", "macos_arm64"]),
            "linux": dict(srcs = NON_ANDROID + glob(["linux/*.kt"]), targets = ["linux_x64"]),
        },
    )

The macro prepends its own srcs, deps, exports and plugins to the same attribute of every
platform: above, each platform compiles COMMON and its own sources against kotlinx.coroutines, as
if it listed both itself. A platform is `jvm`, `android` or a konan target,
and a native group stands for each of its targets. The sources that exactly the same platforms
compile form one K2 fragment, named after them (see derive.bzl): COMMON is the fragment
`android-ios_arm64-jvm-linux_x64-macos_arm64`, NON_ANDROID `ios_arm64-jvm-linux_x64-macos_arm64`,
which refines it, and the Apple sources `ios_arm64-macos_arm64`, which refines that one. The
sources of a single platform are its leaf fragment, named after it, e.g. `jvm` and `linux_x64`;
`ios_arm64` and `macos_arm64` are empty here.

The macro declares:
- shared_fragment_<fragment>: a private kt_kmp_fragment per shared fragment (see fragment.bzl);
- shared_jvm: a kt_jvm_library of the attributes of `jvm`, whose srcs are the sources only the JVM
  compiles, and whose kmp_fragments are the fragments those refine;
- shared_android: a kt_android_library of the attributes of `android`, the same way;
- shared_native: a kt_native_library that compiles, for the konan target of the build's platform,
  the sources only that target compiles and the fragments they refine, with the other attributes
  of the group of that target; it is incompatible with other platforms;
- shared_srcs: a filegroup of the sources of every platform;
- shared.fragments: an executable target printing the derived fragment graph;
- shared: an alias of shared_native for a Kotlin/Native consumer building for a konan target of the
  groups, of shared_android for an Android platform, and otherwise of shared_jvm, or of the only
  platform declared.

The alias selects on //kotlin/native/platforms:native_<konan target>, which only matches below the
Kotlin/Native rules: they set //kotlin/settings:kotlin_platform_type to native for themselves and
their deps. So on a macOS or Linux host, whose platform is also the one of a konan target, the alias
is shared_jvm for a JVM consumer and shared_native for a native one. The attributes of shared_native
and its compatibility select on the platform only (`is_<konan target>`): it is the Kotlin/Native
rule, which transitions itself.
"""

load("//kotlin/internal/jvm:kt_android_library.bzl", "kt_android_library")
load("//kotlin/internal/jvm:kt_jvm_library.bzl", "kt_jvm_library")
load("//kotlin/internal/native:library.bzl", "kt_native_library")
load("//kotlin/internal/native:targets.bzl", "KONAN_TARGETS")
load(":derive.bzl", "derive_fragments", "format_fragments")
load(":fragment.bzl", "kt_kmp_fragment", "kt_kmp_fragments_graph")

# The keys of a group that are not attributes of the native library.
_GROUP_KEYS = ["srcs", "targets"]

# The list attributes of the libraries of every platform, which the macro takes too and prepends to
# the same attribute of each platform.
_COMMON_ATTRS = ["srcs", "deps", "exports", "plugins"]

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

def _platforms(jvm, android, native_groups):
    """The platforms of a declaration as (what the errors call it, its attributes)."""
    return ([("jvm", jvm)] if jvm != None else []) + \
           ([("android", android)] if android != None else []) + \
           [("the native group '%s'" % group, attrs) for group, attrs in native_groups.items()]

def multiplatform_declaration_error(jvm, android, native_groups, normalize = _as_written, common = {}):
    """The error of the declaration of a kt_multiplatform_library, or None when it is valid.

    Args:
      jvm: the `jvm` argument of the macro.
      android: the `android` argument of the macro.
      native_groups: the `native` argument of the macro.
      normalize: the function turning a label into a string equal for equal labels; by default the
        label as written.
      common: the `srcs`, `deps`, `exports` and `plugins` arguments of the macro by attribute, e.g.
        `{"srcs": [...], "deps": [...]}`; a missing one is empty.

    Returns:
      The message of the error, or None.
    """
    if jvm == None and android == None and not native_groups:
        return "it declares no platform: give jvm, android or native"
    for platform, attrs in [("jvm", jvm), ("android", android)]:
        if attrs != None and type(attrs) != "dict":
            return "%s must be a dict of attributes of its library, not a %s" % (platform, type(attrs))
    if type(native_groups) != "dict":
        return "native must be a dict of groups of konan targets, not a %s" % type(native_groups)
    group_of = {}
    for group, attrs in native_groups.items():
        if not group or not group.replace("_", "").isalnum():
            return "the native group '%s' must be a name of letters, digits and '_'" % group
        if type(attrs) != "dict":
            return "the native group '%s' must be a dict of srcs, deps, targets and attributes of kt_native_library" % group
        if not attrs.get("targets"):
            return "the native group '%s' lists no konan targets" % group
        for target in attrs["targets"]:
            if target not in KONAN_TARGETS:
                return "the native group '%s' lists the unknown konan target '%s'; the known ones are %s" % (
                    group,
                    target,
                    ", ".join(sorted(KONAN_TARGETS)),
                )
            if target in group_of:
                return "the konan target '%s' is in both native groups '%s' and '%s'" % (target, group_of[target], group)
            group_of[target] = group

    # The normalized labels of each common list.
    common_labels = {}
    for attr in _COMMON_ATTRS:
        labels = common.get(attr, [])
        if type(labels) != "list":
            return ("the %s of the macro must be a list of labels, not a %s: it prepends them to the %s of " +
                    "every platform when it is called, before any select() is resolved") % (attr, type(labels), attr)
        listed = {}
        for label in labels:
            normalized = normalize(label)
            if normalized in listed:
                return "the %s of the macro list %s twice" % (attr, label)
            listed[normalized] = True
        common_labels[attr] = listed

    for platform, attrs in _platforms(jvm, android, native_groups):
        if "kmp_fragments" in attrs:
            return "%s sets kmp_fragments, which the macro derives from the srcs of the platforms" % platform
        srcs = attrs.get("srcs", [])
        if type(srcs) != "list":
            return ("the srcs of %s must be a list of labels, not a %s: the macro derives the fragments from the " +
                    "srcs of the platforms when it is called, before any select() is resolved") % (platform, type(srcs))
        listed = {}
        for label in srcs:
            normalized = normalize(label)
            if normalized in listed:
                return "the srcs of %s list %s twice" % (platform, normalized)
            listed[normalized] = True
        for attr in _COMMON_ATTRS:
            labels = attrs.get(attr)

            # The macro cannot read the labels of a select(), e.g. of the deps of jvm: it prepends the
            # common list to it as it is.
            if not common_labels[attr] or type(labels) != "list":
                continue
            for label in labels:
                if normalize(label) in common_labels[attr]:
                    return "the %s of %s list %s, which the %s of the macro already list" % (attr, platform, label, attr)
    return None

def with_common_attrs(attrs, common):
    """The attributes of a platform with the common lists of the macro prepended.

    Args:
      attrs: the attributes of a platform: the `jvm` or `android` argument of the macro, or a group
        of `native`.
      common: the common lists by attribute, as multiplatform_declaration_error takes them.

    Returns:
      A new dict: `attrs` with `common[attr] + attrs[attr]` for each attribute whose common list is
      not empty, or the common list alone where `attrs` has no such attribute. It changes neither
      argument: the macro reuses the same lists for every platform.
    """
    merged = dict(attrs)
    for attr in _COMMON_ATTRS:
        labels = common.get(attr, [])
        if not labels:
            continue
        own = attrs.get(attr)

        # list + select() is a select(), e.g. for the deps of jvm.
        merged[attr] = labels + own if own != None else list(labels)
    return merged

def _platform_srcs(jvm, android, native_groups, normalize):
    """The labels of the sources of each platform of a valid declaration, normalized: a dict of platform to labels."""
    platform_srcs = {}
    if jvm != None:
        platform_srcs["jvm"] = [normalize(label) for label in jvm.get("srcs", [])]
    if android != None:
        platform_srcs["android"] = [normalize(label) for label in android.get("srcs", [])]
    for attrs in native_groups.values():
        srcs = [normalize(label) for label in attrs.get("srcs", [])]
        for target in attrs["targets"]:
            platform_srcs[target] = srcs
    return platform_srcs

def _fragment_target(name, fragment):
    return "%s_fragment_%s" % (name, fragment)

def kt_multiplatform_library(
        name,
        jvm = None,
        android = None,
        native = {},
        srcs = [],
        deps = [],
        exports = [],
        plugins = [],
        visibility = None,
        tags = [],
        testonly = False,
        **kwargs):
    """Declares a Kotlin Multiplatform library: a library per platform, the fragments they share, `<name>.fragments` and an alias.

    Experimental. Each platform compiles the sources of every platform, the `srcs` of the macro,
    and its own `srcs`: the macro prepends its own `srcs`, `deps`, `exports` and `plugins` to the
    same attribute of every platform, so the library is the same as one listing them in every
    platform. The sources that exactly the same platforms compile are a K2 fragment of the
    compilations of those platforms, named after them, and the sources of a single platform are
    its leaf fragment, so the `expect` declarations of shared sources and the `actual` ones of a
    platform are in one module (see derive.bzl). Running `<name>.fragments` prints the derived
    fragments, their `refines` edges and their sources. A fragment has no deps: each platform
    compiles it against its own deps, the common ones first. Sources are shared by label: a
    platform gets a label once, from the `srcs` of the macro or from its own, and a file must be
    listed by the same label everywhere. The macro fails on a label that a platform lists twice
    or repeats from a common list.

    Args:
      name: the name of the alias, and the prefix of the names of the other targets.
      jvm: the attributes of the kt_jvm_library `<name>_jvm`, e.g. `dict(srcs = JVM, deps = [...])`,
        or None for no JVM library; `{}` is a JVM library of the common entries alone. Its `srcs`, a
        list of labels, are the sources the JVM compiles besides the `srcs` of the macro.
      android: the attributes of the kt_android_library `<name>_android`, e.g. `srcs`, `deps` and
        `manifest`, or None for no Android library. Its `srcs`, a list of labels, are the sources
        Android compiles besides the `srcs` of the macro.
      native: the groups of konan targets, `{"<group>": dict(srcs = [...], deps = [...], targets = [...])}`.
        A group stands for each of its targets: its `srcs`, a list of labels, are the sources they
        compile besides the `srcs` of the macro, and its other attributes, e.g. `deps` and `opts`,
        are attributes of `<name>_native` for them.
      srcs: the sources of every platform, a list of labels, e.g. those of Gradle's `commonMain`,
        prepended to the `srcs` of each platform. The sources of only some platforms, e.g. of an
        intermediate source set, are a list in the `srcs` of those platforms.
      deps: the deps of every platform, a list of labels prepended to the `deps` of each. Each
        resolves for every platform: an alias selecting the variant of the platform, such as those
        of `kmp_maven`, or another kt_multiplatform_library.
      exports: the exports of every platform, a list of labels prepended to the `exports` of each;
        like `deps`, each resolves for every platform.
      plugins: the Kotlin compiler plugins of every platform, a list of kt_compiler_plugin targets,
        the only kind kt_native_library takes, prepended to the `plugins` of each.
      visibility: the visibility of the targets; the fragments are private.
      tags: the tags of the targets.
      testonly: whether the targets are testonly.
      **kwargs: more attributes common to every rule, e.g. `features`, of every target.
    """
    normalize, label_of = _label_formatter()
    common = {
        "deps": deps,
        "exports": exports,
        "plugins": plugins,
        "srcs": srcs,
    }
    error = multiplatform_declaration_error(jvm, android, native, normalize, common = common)
    if error:
        fail("kt_multiplatform_library %s: %s" % (name, error))

    # From here on, each platform is the one that lists the common entries first itself.
    if jvm != None:
        jvm = with_common_attrs(jvm, common)
    if android != None:
        android = with_common_attrs(android, common)
    native = {group: with_common_attrs(attrs, common) for group, attrs in native.items()}

    platform_srcs = _platform_srcs(jvm, android, native, normalize)
    derived = derive_fragments(platform_srcs)
    rule_attrs = dict(kwargs, tags = tags, testonly = testonly, visibility = visibility)

    def _fragments(platform):
        return [":" + _fragment_target(name, fragment) for fragment in derived.leaf_refines[platform]]

    for fragment in derived.fragments:
        kt_kmp_fragment(
            name = _fragment_target(name, fragment.name),
            srcs = fragment.srcs,
            platforms = fragment.platforms,
            refines = [":" + _fragment_target(name, refined) for refined in fragment.refines],
            **dict(rule_attrs, visibility = ["//visibility:private"])
        )

    if jvm != None:
        kt_jvm_library(
            name = name + "_jvm",
            **dict(rule_attrs, **dict(jvm, srcs = derived.leaf_srcs["jvm"], kmp_fragments = _fragments("jvm")))
        )

    if android != None:
        kt_android_library(
            name = name + "_android",
            **dict(rule_attrs, **dict(android, srcs = derived.leaf_srcs["android"], kmp_fragments = _fragments("android")))
        )

    native_targets = []
    if native:
        # Per konan target: the sources only it lists, the fragments they refine, and the other
        # attributes of its group.
        leaf_srcs = {}
        fragments = {}
        group_attrs = {}
        for spec in native.values():
            for target in spec["targets"]:
                condition = _is_konan_target(target)
                native_targets.append(target)
                leaf_srcs[condition] = derived.leaf_srcs[target]
                fragments[condition] = _fragments(target)
                for key, value in spec.items():
                    if key not in _GROUP_KEYS:
                        group_attrs.setdefault(key, {})[condition] = value
        leaf_srcs[_DEFAULT] = []
        fragments[_DEFAULT] = []

        attrs = dict(rule_attrs)
        target_compatible_with = select(konan_targets_compatibility(native_targets)) + attrs.pop("target_compatible_with", [])
        for key, branches in group_attrs.items():
            # None takes the default of the attribute, for the targets of the groups without it.
            branches[_DEFAULT] = None
            attrs[key] = select(branches)
        kt_native_library(
            name = name + "_native",
            srcs = select(leaf_srcs),
            kmp_fragments = select(fragments),
            target_compatible_with = target_compatible_with,
            **attrs
        )

    _filegroup(
        name = name + "_srcs",
        srcs = {label: None for labels in platform_srcs.values() for label in labels}.keys(),
        **rule_attrs
    )

    kt_kmp_fragments_graph(
        name = name + ".fragments",
        graph = format_fragments(derived, label_of = label_of),
        **rule_attrs
    )

    actual = {}
    if android != None:
        actual[str(Label("@platforms//os:android"))] = ":%s_android" % name
    for target in native_targets:
        actual[_native_konan_target(target)] = ":%s_native" % name
    if jvm != None:
        actual[_DEFAULT] = ":%s_jvm" % name
    elif android != None:
        actual[_DEFAULT] = ":%s_android" % name
    else:
        actual[_DEFAULT] = ":%s_native" % name
    _alias(
        name = name,
        actual = select(actual),
        **rule_attrs
    )
