"""kt_multiplatform_test: the tests of a kt_multiplatform_library, declared along the same hierarchy.

`platforms`, `aliases` and the `<attr>_<qualifier>` lists are those of kt_multiplatform_library (see
multiplatform.bzl and declaration.bzl), for the test sources: each platform compiles the test
sources of the qualifiers covering it, those of each group and alias as a K2 fragment (see
derive.bzl). A test fragment is named after its qualifier, as a fragment of the library is: the
test of a platform compiles test fragments only, in a compilation of its own, and sees the library
of its platform, with the `internal` declarations of every fragment of it, as its associate. With
the name `shared_test` and the library `//shared`, the macro declares:
- shared_test_fragment_<fragment>: a private, testonly kt_kmp_fragment per test fragment;
- shared_test_jvm: when `platforms` lists `jvm`, a kt_jvm_test of the attributes of `jvm`, whose
  associate is //shared:shared_jvm;
- shared_test_android: when `platforms` lists `android`, a kt_android_local_test of the attributes
  of `android`, whose associate is //shared:shared_android;
- shared_test_native: when `platforms` lists konan targets other than those of iOS, a
  kt_native_test of the attributes of `native`, whose associate is //shared:shared_native; it is
  incompatible with other platforms, and runs where a kt_native_test does, for the konan target of
  the exec host;
- shared_test_ios_lib and shared_test_ios: when `platforms` lists iOS targets, a
  kt_native_xctest_library whose associate is //shared:shared_native, which is incompatible with
  other platforms, and the test of `ios_test_rule` and of the attributes of `ios` that takes it
  in `deps`, before the `deps` of `ios`, the other libraries of the test bundle;
- shared_test.fragments: an executable target printing the derived test fragment graph;
- shared_test: a test_suite of the tests above.

The tests of the JVM and of Android run MultiplatformTestSuite by default (see
//src/main/kotlin/io/bazel/kotlin/kmp), a JUnit 4 suite of the test classes of their own jar: the
test sources of a platform are those of several fragments, so no class names its tests.

A kt_native_test of an iOS target links but cannot run, on the exec host or in a simulator. The
tests of the iOS targets run in a test bundle instead (see //kotlin/internal/native:xctest.bzl),
which rules_apple builds and runs: rules_kotlin does not depend on rules_apple, so the caller
passes its test rule, `ios_unit_test`, as `ios_test_rule`.

The test of rules_apple has no rule transition: it is a target of the platform of the build, by
default the host, and depends on a test bundle, which has the transition to the iOS platform that
rules_apple picks, and which builds the library for that platform. So the compatibility of the
iOS test has two parts (see ios_test_konan_targets):
- the library is compatible with the listed iOS targets alone, and a test whose bundle builds it
  for another platform, e.g. the x86_64 simulator, which is no konan target, is incompatible
  through its deps, and skipped;
- the test itself is compatible with the hosts that build the listed iOS targets, and with those
  targets: on another host, e.g. Linux, the test of rules_apple finds no execution platform,
  which fails the analysis before Bazel finds an incompatible dep.
"""

load("//kotlin/internal/jvm:kt_android_local_test.bzl", "kt_android_local_test")
load("//kotlin/internal/jvm:kt_jvm_test.bzl", "kt_jvm_test")
load("//kotlin/internal/native:link.bzl", "LINK_ATTRS")
load("//kotlin/internal/native:targets.bzl", "EXEC_HOSTS")
load("//kotlin/internal/native:test.bzl", "kt_native_test")
load("//kotlin/internal/native:xctest.bzl", "kt_native_xctest_library")
load(
    ":declaration.bzl",
    "LIBRARY_NODES",
    "TEST_NODES",
    "TEST_QUALIFIED_ATTRS",
    "parse_declaration",
    "platform_list",
    "sourceless_error",
)
load(":derive.bzl", "derive_fragments", "format_fragments")
load(":fragment.bzl", "kt_kmp_fragments_graph")
load(
    ":multiplatform.bzl",
    "declare_fragments",
    "konan_target_selects",
    "konan_targets_compatible_with",
    "label_formatter",
    "leaf_fragments",
)

# The lists of the test of a platform that the macro concatenates from the qualifiers covering the
# platform; the srcs are the fragments and the leaf instead.
_CONCATENATED_ATTRS = ["deps", "plugins"]

# What the macro sets on the test of a platform, besides its lists and its kmp_fragments.
_ASSOCIATES = "associates"

# The attributes of `native` that the library of the iOS tests takes too, those of the compilation
# and of the link: the others are of kt_native_test, which runs on the exec host.
_IOS_LIBRARY_ATTRS = [attr for attr in LINK_ATTRS if not attr.startswith("_")]

# Those a declaration can set in `native`: the others are lists of the macro.
_IOS_LIBRARY_SETTINGS = sorted([attr for attr in _IOS_LIBRARY_ATTRS if attr not in TEST_QUALIFIED_ATTRS])

# What the iOS test must set: the macro cannot know the deployment target of the tests.
_MINIMUM_OS_VERSION = "minimum_os_version"

# What the macro sets on the iOS test unless `ios` does. Kotlin/Native does not instrument the
# Kotlin tests, and a test bundle links them alone unless `ios` has `deps`: in a coverage build,
# the runner of rules_apple fails a test that passed when its process wrote no profile.
_IOS_TEST_DEFAULTS = {"collect_code_coverage": False}

# The main class of kt_jvm_test and kt_android_local_test, which runs the class of `test_class`.
_TEST_RUNNER = "com.google.testing.junit.runner.BazelTestRunner"

_SUITE_CLASS = "io.bazel.kotlin.kmp.MultiplatformTestSuite"
_SUITE = Label("//src/main/kotlin:kmp_test_suite")
_TEST_JAR_PROPERTY = "rules_kotlin.kmp.test_jar"

def suite_attrs(package, name, attrs):
    """The attributes of a JVM or Android test, which runs the test classes of its own jar unless it names what to run.

    Args:
      package: the package of the test, its path from the root of its repository.
      name: the name of the test, which compiles into `<name>.jar`.
      attrs: the attributes of the test, e.g. the `jvm` of the macro.

    Returns:
      `attrs` as they are when they set `test_class`, or a `main_class` other than the test runner
      of Bazel, which reads none. Otherwise `attrs` with the suite as `test_class`, its jar after
      the `runtime_deps`, and, before the `jvm_flags`, the system property naming the jar of the
      test, by its path from the root of its repository.
    """
    if attrs.get("test_class") or attrs.get("main_class", _TEST_RUNNER) != _TEST_RUNNER:
        return attrs
    jar = "/".join([segment for segment in [package, name + ".jar"] if segment])
    return dict(
        attrs,
        jvm_flags = ["-D%s=%s" % (_TEST_JAR_PROPERTY, jar)] + attrs.get("jvm_flags", []),
        runtime_deps = attrs.get("runtime_deps", []) + [_SUITE],
        test_class = _SUITE_CLASS,
    )

def platform_library(library, node):
    """The library of a platform that a kt_multiplatform_library declares, next to its alias.

    Args:
      library: the Label of the alias of a kt_multiplatform_library.
      node: `jvm`, `android` or `native`.

    Returns:
      The Label of `<library>_<node>`.
    """
    return library.same_package_label("%s_%s" % (library.name, node))

def ios_test_konan_targets(ios_targets):
    """The konan targets whose platforms the iOS test of some iOS targets is compatible with.

    The test is a target of the platform of the build, and its bundle builds for an iOS platform
    of its own choice: a build for a platform that no listed iOS target builds on, or for, skips
    the test before it resolves anything.

    Args:
      ios_targets: the iOS targets the tests list, e.g. `["ios_simulator_arm64"]`.

    Returns:
      `ios_targets`, for a build for one of them, and then the konan target of each exec host
      whose Kotlin/Native distribution compiles one of them, for a build for the host: with the
      hosts of rules_kotlin, `macos_arm64`.
    """
    hosts = [
        host.konan_host
        for host in EXEC_HOSTS.values()
        if [target for target in ios_targets if target in host.targets]
    ]
    return ios_targets + [host for host in hosts if host not in ios_targets]

def _enumeration(names):
    """`a`, `a and b`, `a, b and c`."""
    return ", ".join(names[:-1]) + " and " + names[-1] if len(names) > 1 else "".join(names)

def _konan_targets(declaration):
    """The iOS targets of a declaration, which the iOS test covers, and its other konan targets, those of the native test."""
    ios_targets = declaration.targeted.get("ios", [])
    return ios_targets, [target for target in declaration.targeted.get("native", []) if target not in ios_targets]

def _ios_error(declaration, ios_test_rule):
    """The error of the iOS test of a declaration that lists iOS targets, or None."""
    ios_targets, _ = _konan_targets(declaration)
    if not ios_targets:
        return None
    listed = _enumeration(ios_targets)
    if ios_test_rule == None:
        return ("platforms lists %s, whose tests need ios_test_rule: pass the ios_unit_test of rules_apple, " +
                "loaded from @rules_apple//apple:ios.bzl, or remove %s from platforms") % (listed, listed)
    ios = declaration.settings["ios"]
    if not ios.get(_MINIMUM_OS_VERSION):
        return ("platforms lists %s, whose test needs a deployment target, which the macro has no default for: " +
                "pass it as ios = dict(%s = ...), e.g. \"15.0\"") % (listed, _MINIMUM_OS_VERSION)
    if _ASSOCIATES in ios:
        return "ios sets %s, which the macro sets to the library of the platform" % _ASSOCIATES

    # The macro puts the library of the Kotlin tests before them, when it is called.
    if type(ios.get("deps", [])) not in ["list", "select"]:
        return ("the deps of ios must be a list of labels, not a %s: they are the other libraries that the test " +
                "bundle links, e.g. an objc_library; the deps of the Kotlin tests are deps_ios of the macro") % type(ios["deps"])
    return None

def _native_test_attrs_error(declaration):
    """The error of the attributes of `native` that no target of a declaration without a native test takes, or None.

    With iOS targets as its only konan targets, a declaration has no native test, and only the
    library of the iOS tests reads `native`: an attribute of the native test alone, e.g. `data`,
    would go nowhere.
    """
    ios_targets, konan_targets = _konan_targets(declaration)
    if not ios_targets or konan_targets:
        return None
    unused = sorted([attr for attr in declaration.settings["native"] if attr not in _IOS_LIBRARY_SETTINGS])
    if not unused:
        return None
    names = _enumeration(unused)
    return ("native sets %s, %s of the native test, but platforms lists no konan target other than those of iOS, " +
            "whose tests take only the %s of native: remove %s from native, or add a konan target that has a " +
            "native test, e.g. macos_arm64; the attributes of the iOS test are those of ios") % (
        names,
        "attributes" if len(unused) > 1 else "an attribute",
        _enumeration(_IOS_LIBRARY_SETTINGS),
        names,
    )

def tests_error(declaration, derived, ios_test_rule = None):
    """The error of a declaration that the tests cannot be declared from, or None.

    Args:
      declaration: a struct returned by `parse_declaration` for a test, without error.
      derived: the fragments `derive_fragments` returns for its sources.
      ios_test_rule: the `ios_test_rule` of the macro.

    Returns:
      The message for the first of `jvm`, `android` and `native` that sets `associates`, which
      the macro sets. Otherwise, with iOS targets, the first of: no `ios_test_rule`, no
      `minimum_os_version` in `ios`, `associates` in `ios`, which the macro sets, and `deps` in
      `ios` that are neither a list nor a select, as the macro adds the library of the Kotlin
      tests to them. Then, with iOS targets and no other konan target, the message for the
      attributes of `native` that are those of the native test alone, which the macro then does
      not declare. Otherwise the message for the first listed platform that compiles no source,
      whose test would run nothing. None without any.
    """
    for node in LIBRARY_NODES:
        if _ASSOCIATES in declaration.settings[node]:
            return "%s sets %s, which the macro sets to the library of the platform" % (node, _ASSOCIATES)
    error = _ios_error(declaration, ios_test_rule) or _native_test_attrs_error(declaration)
    if error:
        return error
    for platform in declaration.platforms:
        if not derived.leaf_srcs[platform] and not derived.leaf_refines[platform]:
            return sourceless_error(declaration, platform)
    return None

# The parameter `native` of the macro hides the module.
def _test_suite(**kwargs):
    native.test_suite(**kwargs)

def _package_name():
    return native.package_name()

def _package_relative_label(label):
    return native.package_relative_label(label)

def kt_multiplatform_test(
        name,
        library,
        platforms = None,
        aliases = {},
        srcs = [],
        deps = [],
        plugins = [],
        jvm = None,
        android = None,
        native = None,
        ios = None,
        ios_test_rule = None,
        visibility = None,
        tags = [],
        **kwargs):
    """Declares the tests of a Kotlin Multiplatform library: a test per platform, the test fragments they share, `<name>.fragments` and a test_suite.

    Experimental. The test sources are declared as the sources of `kt_multiplatform_library` are:
    `platforms` lists the platforms to test, `srcs`, `deps` and `plugins` are those of every
    platform, a group, a platform or an alias of `aliases` has its own as `<attr>_<qualifier>`, e.g.
    `srcs_jvm`, `srcs_native` or `deps_non_android`, and each platform compiles the lists of the
    groups and aliases above it and its own. The test sources of a group or an alias are a K2
    fragment of the tests of its platforms, named after it, so a common test can use an `expect`
    helper that each platform implements with `actual`. Running `<name>.fragments` prints the
    derived test fragments. The platforms and the aliases are those of the test, not of the
    library: they may be fewer, and the test may declare aliases of its own.

    The test of a platform is a `kt_jvm_test`, a `kt_android_local_test` or a `kt_native_test`
    whose `associates` are the library of that platform, `<library>_jvm`, `<library>_android` or
    `<library>_native`: every test fragment sees the `internal` declarations of the whole library
    of the platform, and the library is a dep of the test. The other deps of the tests are their
    own lists: a test does not inherit the deps of the library that the library does not export.
    A platform of the test that the library does not list is a missing `<library>_<platform>`
    target, or, for a konan target, a native test that is skipped as incompatible.

    The iOS targets have a test of their own, as a `kt_native_test` runs on the exec host: the
    macro links their tests into `<name>_ios_lib`, a `kt_native_xctest_library` whose `associates`
    are `<library>_native`, and declares `<name>_ios` with `ios_test_rule`, which takes the library
    in `deps`, bundles it and runs it, e.g. in the iOS simulator. The `deps` of `ios` follow the
    library in the `deps` of the test: they are the other libraries the test bundle links, e.g.
    the `objc_library` or the Swift package of an SDK that a klib of the tests refers to, as
    `ios = dict(minimum_os_version = "15.0", deps = [...], linkopts = ["-ObjC"])`. rules_kotlin
    does not depend on rules_apple, so the caller loads its `ios_unit_test` and passes it:

    ```bzl
    load("@rules_apple//apple:ios.bzl", "ios_unit_test")
    load("@rules_kotlin//kotlin:kmp.bzl", "kt_multiplatform_test")

    kt_multiplatform_test(
        name = "shared_test",
        srcs = ["commonTest/GreetingTest.kt"],
        ios = dict(minimum_os_version = "15.0"),
        ios_test_rule = ios_unit_test,
        library = ":shared",
        platforms = ["jvm", "ios_simulator_arm64"],
        deps_jvm = [...],
    )
    ```

    The tests of the JVM and of Android use JUnit 4, e.g. through `kotlin-test-junit`, and run
    every public class of their own jar that has a method annotated with `@Test` (or is annotated
    with `@RunWith`); a jar without any fails the test. Setting `test_class` in `jvm` or `android`,
    or a `main_class` other than the test runner of Bazel, runs that instead. The native test runs
    like any `kt_native_test`: `bazel test` runs it for the konan target of the exec host, and it
    is incompatible with the platforms of the konan targets that `platforms` does not list. The
    test bundle of the iOS test builds for the iOS platform its rule picks, whatever the platform
    of the build: with rules_apple, the first of `--ios_multi_cpus`, by default the arm64
    simulator on an arm64 Mac and the x86_64 simulator elsewhere. `<name>_ios_lib` is incompatible
    with the platforms of the iOS targets that `platforms` does not list, and the test with it:
    the test is skipped where the rule picks the x86_64 simulator, which is no konan target, and
    with `ios_arm64` alone, which is the device, in a default build. The test itself is a target
    of the platform of the build, and is skipped on a host that does not build its iOS targets,
    e.g. Linux. `bazel test <name>` runs, with no platform flag, the tests of every platform that
    the host can run.

    The macro checks the declaration when it is called and fails with what to change, as
    `kt_multiplatform_library` does, and also for a platform that no list gives test sources. For
    the iOS targets it fails, in this order: when `platforms` lists none and `ios` sets attributes;
    when it lists some and `ios_test_rule` is not set, as the macro then has no rule to run their
    tests with; when `ios` does not set `minimum_os_version`, which the macro has no default for;
    when `ios` sets `associates`, which the macro sets; and when the `deps` of `ios` are neither
    a list of labels nor a select(). An `ios_test_rule` without iOS targets is allowed, so a
    wrapper of the macro can always pass it. With iOS targets as the only konan targets, the macro
    declares no native test, and fails when `native` sets an attribute other than `opts`,
    `link_opts` and `module_name`, e.g. `data` or `args`, which nothing would take.

    Args:
      name: the name of the test_suite, and the prefix of the names of the other targets.
      library: the label of the `kt_multiplatform_library` under test, the one of its alias.
      platforms: the platforms to test, in any order, among those of the library, e.g.
        `["jvm", "macos_arm64", "linux_x64"]`. The macro declares `<name>_jvm` for `jvm`,
        `<name>_android` for `android`, `<name>_ios` and `<name>_ios_lib` for the iOS targets and
        `<name>_native` for the other konan targets.
      aliases: the sets of platforms that the hierarchy has no group for, a dict of the name of
        each to its platforms, as in `kt_multiplatform_library`.
      srcs: the test sources of every platform, a list of labels, e.g. those of Gradle's
        `commonTest`. Those of only some platforms are the srcs of a group, a platform or an
        alias, e.g. `srcs_jvm` for `jvmTest`.
      deps: the deps of the test of every platform, a list of labels, each of which resolves for
        every platform. Those of only some platforms are the deps of a group, a platform or an
        alias, e.g. `deps_jvm` for `kotlin-test-junit`.
      plugins: the Kotlin compiler plugins of every platform, a list of kt_compiler_plugin targets.
      jvm: the other attributes of the kt_jvm_test `<name>_jvm`, e.g. `dict(jvm_flags = [...])`;
        its srcs, deps and plugins are `srcs_jvm`, `deps_jvm` and `plugins_jvm`.
      android: the other attributes of the kt_android_local_test `<name>_android`, e.g.
        `dict(manifest = "AndroidManifest.xml")`.
      native: the other attributes of the kt_native_test `<name>_native`, e.g.
        `dict(opts = ["-opt-in=kotlin.ExperimentalStdlibApi"])`, for each of its konan targets.
        Those of the compilation and of the link, `opts`, `link_opts` and `module_name`, are also
        attributes of `<name>_ios_lib`; the others, e.g. `data` or `args`, are of the native test
        alone, and an error when `platforms` lists no konan target other than those of iOS.
      ios: the other attributes of the test `<name>_ios`, those of `ios_test_rule`, e.g.
        `dict(minimum_os_version = "15.0", runner = ...)`. `minimum_os_version` is required with
        iOS targets. Its `deps` are the other libraries that the test bundle links, after
        `<name>_ios_lib`: targets with a `CcInfo`, e.g. an `objc_library` or a `swift_library`, a
        list of labels that may be or end with a select(); the deps of the Kotlin tests are
        `deps_ios`. The macro sets `collect_code_coverage` to False unless `ios` sets it:
        Kotlin/Native code is not instrumented, and the runner of rules_apple fails a test of
        `bazel coverage` whose process wrote no profile. A test with `deps` to cover sets it to
        True, in a build with `--experimental_use_llvm_covmap`: without that flag, a coverage
        build compiles the Objective-C sources of any target for the gcov format, whose runtime
        a test bundle does not link.
      ios_test_rule: the rule that bundles and runs the tests of the iOS targets: the
        `ios_unit_test` of rules_apple, loaded from `@rules_apple//apple:ios.bzl`, or a macro that
        takes its `name`, `deps`, `minimum_os_version`, `collect_code_coverage` and the attributes
        of a test. Its `deps` are `<name>_ios_lib` and then the `deps` of `ios`. It is required
        with iOS targets, and unused without.
      visibility: the visibility of the tests, of `<name>.fragments` and of the test_suite; the
        fragments are private.
      tags: the tags of the targets.
      **kwargs: the lists of the groups, the platforms and the aliases, `<attr>_<qualifier>`:
        `<attr>` is `srcs`, `deps` or `plugins`. Each is a list of labels; the deps and plugins of
        `jvm` and `android` may also be or end with a select(). The other keyword arguments are
        attributes of every test, e.g. `size`, `timeout` or `target_compatible_with`.
    """
    normalize, label_of = label_formatter()
    declaration = parse_declaration(
        platforms,
        {"deps": deps, "plugins": plugins, "srcs": srcs},
        {"android": android, "ios": ios, "jvm": jvm, "native": native},
        kwargs,
        aliases = aliases,
        normalize = normalize,
        attrs = TEST_QUALIFIED_ATTRS,
        nodes = TEST_NODES,
        kind = "test",
    )
    if declaration.error:
        fail("kt_multiplatform_test %s: %s" % (name, declaration.error))

    qualifier_srcs = {
        qualifier: [normalize(label) for label in labels]
        for qualifier, labels in declaration.lists["srcs"].items()
    }
    derived = derive_fragments(qualifier_srcs, declaration.qualifiers)
    error = tests_error(declaration, derived, ios_test_rule)
    if error:
        fail("kt_multiplatform_test %s: %s" % (name, error))

    test_attrs = dict(declaration.rule_attrs, tags = tags, visibility = visibility)
    resolved_library = _package_relative_label(library)
    package = _package_name()
    tests = []

    def _platform_attrs(node, platform):
        lists = {attr: platform_list(declaration, attr, platform) for attr in _CONCATENATED_ATTRS}
        return dict(declaration.settings[node], **lists)

    declare_fragments(name, derived, tags = tags, testonly = True, visibility = ["//visibility:private"])

    if "jvm" in declaration.targeted:
        tests.append(name + "_jvm")
        kt_jvm_test(
            name = name + "_jvm",
            srcs = derived.leaf_srcs["jvm"],
            associates = [platform_library(resolved_library, "jvm")],
            kmp_fragments = leaf_fragments(name, derived, "jvm"),
            **dict(test_attrs, **suite_attrs(package, name + "_jvm", _platform_attrs("jvm", "jvm")))
        )

    if "android" in declaration.targeted:
        tests.append(name + "_android")
        kt_android_local_test(
            name = name + "_android",
            srcs = derived.leaf_srcs["android"],
            associates = [platform_library(resolved_library, "android")],
            kmp_fragments = leaf_fragments(name, derived, "android"),
            **dict(test_attrs, **suite_attrs(package, name + "_android", _platform_attrs("android", "android")))
        )

    def _native_lists(target):
        return dict(
            {attr: platform_list(declaration, attr, target) for attr in _CONCATENATED_ATTRS},
            kmp_fragments = leaf_fragments(name, derived, target),
            srcs = derived.leaf_srcs[target],
        )

    native_attrs = declaration.settings["native"]
    ios_targets, konan_targets = _konan_targets(declaration)
    if konan_targets:
        attrs = dict(test_attrs, **native_attrs)

        # The compatibility with the konan targets comes first, then that of the macro and of native.
        attrs["target_compatible_with"] = konan_targets_compatible_with(konan_targets, [test_attrs, native_attrs])
        attrs.update(konan_target_selects(konan_targets, _native_lists))
        tests.append(name + "_native")
        kt_native_test(
            name = name + "_native",
            associates = [platform_library(resolved_library, "native")],
            **attrs
        )

    if ios_targets:
        ios_attrs = declaration.settings["ios"]
        library_attrs = {attr: native_attrs[attr] for attr in _IOS_LIBRARY_ATTRS if attr in native_attrs}
        library_attrs.update(konan_target_selects(ios_targets, _native_lists))

        # The library is in the configuration of the test bundle, for an iOS platform: the
        # constraints of the macro and of `native` are for the platform of the build.
        kt_native_xctest_library(
            name = name + "_ios_lib",
            associates = [platform_library(resolved_library, "native")],
            tags = tags,
            target_compatible_with = konan_targets_compatible_with(ios_targets, []),
            testonly = True,
            visibility = visibility,
            **library_attrs
        )
        attrs = dict(test_attrs, **dict(_IOS_TEST_DEFAULTS, **ios_attrs))
        attrs["target_compatible_with"] = konan_targets_compatible_with(
            ios_test_konan_targets(ios_targets),
            [test_attrs, ios_attrs],
        )
        attrs["deps"] = [":%s_ios_lib" % name] + ios_attrs.get("deps", [])
        tests.append(name + "_ios")
        ios_test_rule(name = name + "_ios", **attrs)

    kt_kmp_fragments_graph(
        name = name + ".fragments",
        graph = format_fragments(derived, label_of = label_of),
        tags = tags,
        testonly = True,
        visibility = visibility,
    )

    _test_suite(
        name = name,
        tags = tags,
        tests = [":" + test for test in tests],
        visibility = visibility,
    )
