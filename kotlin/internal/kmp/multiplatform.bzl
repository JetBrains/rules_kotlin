"""kt_multiplatform_library: a Kotlin Multiplatform library from a declaration like the one of the Kotlin Gradle plugin.

    kt_multiplatform_library(
        name = "shared",
        common_srcs = glob(["common/*.kt"]),
        jvm = dict(srcs = glob(["jvm/*.kt"])),
        android = dict(srcs = glob(["android/*.kt"]), manifest = "android/AndroidManifest.xml"),
        native = {
            "apple": dict(srcs = glob(["apple/*.kt"]), targets = ["ios_arm64", "macos_arm64"]),
            "linux": dict(srcs = glob(["linux/*.kt"]), targets = ["linux_x64"]),
        },
    )

declares:
- shared_common: the source set of common_srcs and common_deps, Gradle's commonMain;
- shared_jvm: a kt_jvm_library of the attributes of `jvm`, which compiles the common source set;
- shared_android: a kt_android_library of the attributes of `android`, which compiles the common
  source set; both also list the source sets they compile in runtime_deps (see fragments.bzl);
- shared_apple, shared_linux: a source set per group of konan targets, which refines the common
  one, as Gradle's appleMain and linuxMain, and the source sets of the group's `depends_on`, for an
  intermediate source set of the module (Gradle's `iosMain.dependsOn(nonAndroidMain)`);
- shared_native: a kt_native_library that compiles, for the konan target of the build's platform,
  the source set of the group of that target; it is incompatible with other platforms;
- shared_srcs: a filegroup of the sources of every source set and platform;
- shared: an alias of shared_native for a Kotlin/Native consumer building for a konan target of the
  groups, of shared_android for an Android platform, and otherwise of shared_jvm, or of the only
  platform declared.

The alias and the compatibility of the source set of a group select on
//kotlin/native/platforms:native_<konan target>, which only matches below the Kotlin/Native rules:
they set //kotlin/settings:kotlin_platform_type to native for themselves and their deps. So on a
macOS or Linux host, whose platform is also the one of a konan target, the alias is shared_jvm for a
JVM consumer and shared_native for a native one, and the source set of the host's group is skipped
by a build of the package. The source sets shared_native compiles and its compatibility select on
the platform only (`is_<konan target>`): it is the Kotlin/Native rule, which transitions itself.
"""

load("//kotlin/internal/jvm:kt_android_library.bzl", "kt_android_library")
load("//kotlin/internal/jvm:kt_jvm_library.bzl", "kt_jvm_library")
load("//kotlin/internal/native:library.bzl", "kt_native_library")
load("//kotlin/internal/native:targets.bzl", "KONAN_TARGETS")
load(":source_set.bzl", "kt_source_set")

# The groups that would name a target the macro declares besides the groups.
_RESERVED_GROUPS = ["android", "common", "jvm", "native", "srcs"]

# The keys of a group that are not attributes of the native library.
_GROUP_KEYS = ["depends_on", "deps", "srcs", "targets"]

_DEFAULT = "//conditions:default"

def _is_konan_target(konan_target):
    return str(Label("//kotlin/native/platforms:is_" + konan_target))

def _native_konan_target(konan_target):
    return str(Label("//kotlin/native/platforms:native_" + konan_target))

def konan_targets_compatibility(konan_targets, native_consumer = False):
    """The branches of the target_compatible_with of a target for some konan targets: it is compatible with their platforms alone.

    Args:
      konan_targets: the konan targets, e.g. `["ios_arm64", "ios_simulator_arm64"]`.
      native_consumer: whether the target is only compatible below a Kotlin/Native consumer building
        for one of the targets (`native_<target>`), as the source set of a group: a build of the
        package for the platform of a target would otherwise resolve its deps as a JVM consumer
        does. By default it is compatible with any build for the platform of a target
        (`is_<target>`), as the native library, which transitions itself to Kotlin/Native.

    Returns:
      The dict of a select(): no constraint on the platform of each target, and
      `@platforms//:incompatible` by default.
    """
    condition = _native_konan_target if native_consumer else _is_konan_target
    compatible = {condition(target): [] for target in konan_targets}
    compatible[_DEFAULT] = [str(Label("@platforms//:incompatible"))]
    return compatible

# The parameter `native` of the macro hides the module.
def _filegroup(**kwargs):
    native.filegroup(**kwargs)

def _unique(labels):
    """The labels without their repetitions, in order: a source several platforms compile is one file of the filegroup.

    A select() (a platform whose srcs are a select) is returned as it is: its branches are only known at analysis.
    """
    if type(labels) != "list":
        return labels
    return {label: None for label in labels}.keys()

def _alias(**kwargs):
    native.alias(**kwargs)

def multiplatform_declaration_error(jvm, android, native_groups):
    """The error of the platforms of a kt_multiplatform_library, or None when they are valid.

    Args:
      jvm: the `jvm` argument of the macro.
      android: the `android` argument of the macro.
      native_groups: the `native` argument of the macro.

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
        if group in _RESERVED_GROUPS:
            return "the native group '%s' would name a target the macro declares; rename it" % group
        if type(attrs) != "dict":
            return "the native group '%s' must be a dict of srcs, deps, depends_on, targets and attributes of kt_native_library" % group
        if type(attrs.get("depends_on", [])) != "list":
            return "the native group '%s' must list the source sets it refines in depends_on, not give a %s" % (
                group,
                type(attrs["depends_on"]),
            )
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
    return None

def kt_multiplatform_library(
        name,
        common_srcs,
        common_deps = [],
        jvm = None,
        android = None,
        native = {},
        visibility = None,
        tags = [],
        testonly = False,
        **kwargs):
    """Declares a Kotlin Multiplatform library: its source sets, a library per platform and an alias.

    Experimental. Each platform compiles the common source set with its own sources, as K2
    fragments (see kt_source_set), so the `expect` declarations of the common sources and the
    `actual` ones of a platform are in one module.

    Args:
      name: the name of the alias, and the prefix of the names of the other targets.
      common_srcs: the Kotlin sources of the common source set, `<name>_common`.
      common_deps: the deps of the common source set, which every platform compiles against. A dep
        that differs per platform is an alias that selects its klib on
        `@rules_kotlin//kotlin/native/platforms:native_<konan target>`, its Android library on
        `@platforms//os:android` and its JVM library by default.
      jvm: the attributes of the kt_jvm_library `<name>_jvm`, e.g. `dict(srcs = [...], deps = [...])`,
        or None for no JVM library. Its source_sets are the common source set and those it lists,
        which are in its runtime_deps too (see that attribute of the library).
      android: the attributes of the kt_android_library `<name>_android`, e.g. `srcs` and `manifest`,
        or None for no Android library. Its source_sets are the common source set and those it
        lists, which are in its runtime_deps too (see that attribute of the library).
      native: the groups of konan targets, `{"<group>": dict(srcs = [...], deps = [...], targets = [...])}`.
        Each group is a source set, `<name>_<group>`, of its srcs and deps, which refines the common
        one and which `<name>_native` compiles for each of its targets. A group also refines the
        kt_source_sets of its `depends_on`, the intermediate source sets of the module between the
        common one and the group, as Gradle's `iosMain.dependsOn(nonAndroidMain)`; a JVM or Android
        platform compiles such a source set by listing it in its `source_sets`. The other attributes
        of a group are attributes of `<name>_native` for its targets, e.g. `opts`.
      visibility: the visibility of the targets.
      tags: the tags of the targets.
      testonly: whether the targets are testonly.
      **kwargs: more attributes common to every rule, e.g. `features`, of every target.
    """
    error = multiplatform_declaration_error(jvm, android, native)
    if error:
        fail("kt_multiplatform_library %s: %s" % (name, error))

    common_attrs = dict(kwargs, tags = tags, testonly = testonly, visibility = visibility)
    common = ":%s_common" % name
    kt_source_set(
        name = name + "_common",
        srcs = common_srcs,
        deps = common_deps,
        **common_attrs
    )
    all_srcs = common_srcs

    if jvm != None:
        attrs = dict(common_attrs, **jvm)
        attrs["source_sets"] = [common] + jvm.get("source_sets", [])
        attrs["runtime_deps"] = jvm.get("runtime_deps", []) + attrs["source_sets"]
        all_srcs = all_srcs + jvm.get("srcs", [])
        kt_jvm_library(name = name + "_jvm", **attrs)

    if android != None:
        attrs = dict(common_attrs, **android)
        attrs["source_sets"] = [common] + android.get("source_sets", [])
        attrs["runtime_deps"] = android.get("runtime_deps", []) + attrs["source_sets"]
        all_srcs = all_srcs + android.get("srcs", [])
        kt_android_library(name = name + "_android", **attrs)

    native_targets = []
    if native:
        # Per konan target: the source set of its group, and the other attributes of the group.
        source_sets = {}
        group_attrs = {}
        for group, spec in native.items():
            attrs = dict(common_attrs)
            kt_source_set(
                name = "%s_%s" % (name, group),
                srcs = spec.get("srcs", []),
                deps = spec.get("deps", []),
                depends_on = [common] + [refined for refined in spec.get("depends_on", []) if refined != common],
                target_compatible_with = select(konan_targets_compatibility(spec["targets"], native_consumer = True)) + attrs.pop("target_compatible_with", []),
                **attrs
            )
            all_srcs = all_srcs + spec.get("srcs", [])
            for target in spec["targets"]:
                condition = _is_konan_target(target)
                native_targets.append(target)
                source_sets[condition] = [":%s_%s" % (name, group)]
                for key, value in spec.items():
                    if key not in _GROUP_KEYS:
                        group_attrs.setdefault(key, {})[condition] = value
        source_sets[_DEFAULT] = []

        attrs = dict(common_attrs)
        target_compatible_with = select(konan_targets_compatibility(native_targets)) + attrs.pop("target_compatible_with", [])
        for key, branches in group_attrs.items():
            # None takes the default of the attribute, for the targets of the groups without it.
            branches[_DEFAULT] = None
            attrs[key] = select(branches)
        kt_native_library(
            name = name + "_native",
            source_sets = select(source_sets),
            target_compatible_with = target_compatible_with,
            **attrs
        )

    _filegroup(
        name = name + "_srcs",
        srcs = _unique(all_srcs),
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
