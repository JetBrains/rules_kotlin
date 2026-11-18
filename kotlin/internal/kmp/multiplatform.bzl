"""kt_multiplatform_library: a Kotlin Multiplatform library whose platforms each list every source they compile.

    COMMON = glob(["common/*.kt"])
    NON_ANDROID = glob(["non_android/*.kt"])

    kt_multiplatform_library(
        name = "shared",
        jvm = dict(srcs = COMMON + NON_ANDROID + glob(["jvm/*.kt"])),
        android = dict(srcs = COMMON + glob(["android/*.kt"]), manifest = "android/AndroidManifest.xml"),
        native = {
            "apple": dict(srcs = COMMON + NON_ANDROID + glob(["apple/*.kt"]), targets = ["ios_arm64", "macos_arm64"]),
            "linux": dict(srcs = COMMON + NON_ANDROID + glob(["linux/*.kt"]), targets = ["linux_x64"]),
        },
    )

A platform is `jvm`, `android` or a konan target, and a native group stands for each of its
targets. The sources that exactly the same platforms list form one K2 fragment, named after them
(see derive.bzl): COMMON is the fragment `android-ios_arm64-jvm-linux_x64-macos_arm64`, NON_ANDROID
`ios_arm64-jvm-linux_x64-macos_arm64`, which refines it, and the Apple sources
`ios_arm64-macos_arm64`, which refines that one. The sources of a single platform are its leaf
fragment, named after it, e.g. `jvm` and `linux_x64`; `ios_arm64` and `macos_arm64` are empty here.

The macro declares:
- shared_fragment_<fragment>: a private kt_kmp_fragment per shared fragment (see fragment.bzl);
- shared_jvm: a kt_jvm_library of the attributes of `jvm`, whose srcs are the sources only the JVM
  lists, and whose kmp_fragments are the fragments those refine;
- shared_android: a kt_android_library of the attributes of `android`, the same way;
- shared_native: a kt_native_library that compiles, for the konan target of the build's platform,
  the sources only that target lists and the fragments they refine, with the other attributes of
  the group of that target; it is incompatible with other platforms;
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

def multiplatform_declaration_error(jvm, android, native_groups, normalize = _as_written):
    """The error of the declaration of a kt_multiplatform_library, or None when it is valid.

    Args:
      jvm: the `jvm` argument of the macro.
      android: the `android` argument of the macro.
      native_groups: the `native` argument of the macro.
      normalize: the function turning a label of srcs into a string equal for equal labels; by
        default the label as written.

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
    return None

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
        visibility = None,
        tags = [],
        testonly = False,
        **kwargs):
    """Declares a Kotlin Multiplatform library: a library per platform, the fragments they share, `<name>.fragments` and an alias.

    Experimental. Each platform lists every source it compiles. The sources that exactly the same
    platforms list are a K2 fragment of the compilations of those platforms, named after them, and
    the sources of a single platform are its leaf fragment, so the `expect` declarations of shared
    sources and the `actual` ones of a platform are in one module (see derive.bzl). Running
    `<name>.fragments` prints the derived fragments, their `refines` edges and their sources. A
    fragment has no deps: each platform compiles it against its own deps. Sources are shared by
    label: a platform lists a label once, and a file must be listed by the same label everywhere.

    Args:
      name: the name of the alias, and the prefix of the names of the other targets.
      jvm: the attributes of the kt_jvm_library `<name>_jvm`, e.g. `dict(srcs = COMMON + JVM, deps = [...])`,
        or None for no JVM library. Its `srcs`, a list of labels, are every source the JVM compiles.
      android: the attributes of the kt_android_library `<name>_android`, e.g. `srcs`, `deps` and
        `manifest`, or None for no Android library. Its `srcs`, a list of labels, are every source
        Android compiles.
      native: the groups of konan targets, `{"<group>": dict(srcs = [...], deps = [...], targets = [...])}`.
        A group stands for each of its targets: its `srcs`, a list of labels, are every source they
        compile, and its other attributes, e.g. `deps` and `opts`, are attributes of `<name>_native`
        for them.
      visibility: the visibility of the targets; the fragments are private.
      tags: the tags of the targets.
      testonly: whether the targets are testonly.
      **kwargs: more attributes common to every rule, e.g. `features`, of every target.
    """
    normalize, label_of = _label_formatter()
    error = multiplatform_declaration_error(jvm, android, native, normalize)
    if error:
        fail("kt_multiplatform_library %s: %s" % (name, error))

    platform_srcs = _platform_srcs(jvm, android, native, normalize)
    derived = derive_fragments(platform_srcs)
    common_attrs = dict(kwargs, tags = tags, testonly = testonly, visibility = visibility)

    def _fragments(platform):
        return [":" + _fragment_target(name, fragment) for fragment in derived.leaf_refines[platform]]

    for fragment in derived.fragments:
        kt_kmp_fragment(
            name = _fragment_target(name, fragment.name),
            srcs = fragment.srcs,
            platforms = fragment.platforms,
            refines = [":" + _fragment_target(name, refined) for refined in fragment.refines],
            **dict(common_attrs, visibility = ["//visibility:private"])
        )

    if jvm != None:
        kt_jvm_library(
            name = name + "_jvm",
            **dict(common_attrs, **dict(jvm, srcs = derived.leaf_srcs["jvm"], kmp_fragments = _fragments("jvm")))
        )

    if android != None:
        kt_android_library(
            name = name + "_android",
            **dict(common_attrs, **dict(android, srcs = derived.leaf_srcs["android"], kmp_fragments = _fragments("android")))
        )

    native_targets = []
    if native:
        # Per konan target: the sources only it lists, the fragments they refine, and the other
        # attributes of its group.
        srcs = {}
        fragments = {}
        group_attrs = {}
        for spec in native.values():
            for target in spec["targets"]:
                condition = _is_konan_target(target)
                native_targets.append(target)
                srcs[condition] = derived.leaf_srcs[target]
                fragments[condition] = _fragments(target)
                for key, value in spec.items():
                    if key not in _GROUP_KEYS:
                        group_attrs.setdefault(key, {})[condition] = value
        srcs[_DEFAULT] = []
        fragments[_DEFAULT] = []

        attrs = dict(common_attrs)
        target_compatible_with = select(konan_targets_compatibility(native_targets)) + attrs.pop("target_compatible_with", [])
        for key, branches in group_attrs.items():
            # None takes the default of the attribute, for the targets of the groups without it.
            branches[_DEFAULT] = None
            attrs[key] = select(branches)
        kt_native_library(
            name = name + "_native",
            srcs = select(srcs),
            kmp_fragments = select(fragments),
            target_compatible_with = target_compatible_with,
            **attrs
        )

    _filegroup(
        name = name + "_srcs",
        srcs = {label: None for labels in platform_srcs.values() for label in labels}.keys(),
        **common_attrs
    )

    kt_kmp_fragments_graph(
        name = name + ".fragments",
        graph = format_fragments(derived, label_of = label_of),
        **common_attrs
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
        **common_attrs
    )
