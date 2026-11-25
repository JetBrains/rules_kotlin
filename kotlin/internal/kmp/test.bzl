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
- shared_test_native: when `platforms` lists konan targets, a kt_native_test of the attributes of
  `native`, whose associate is //shared:shared_native; it is incompatible with other platforms,
  and runs where a kt_native_test does, for the konan target of the exec host;
- shared_test.fragments: an executable target printing the derived test fragment graph;
- shared_test: a test_suite of the tests above.

The tests of the JVM and of Android run MultiplatformTestSuite by default (see
//src/main/kotlin/io/bazel/kotlin/kmp), a JUnit 4 suite of the test classes of their own jar: the
test sources of a platform are those of several fragments, so no class names its tests.
"""

load("//kotlin/internal/jvm:kt_android_local_test.bzl", "kt_android_local_test")
load("//kotlin/internal/jvm:kt_jvm_test.bzl", "kt_jvm_test")
load("//kotlin/internal/native:test.bzl", "kt_native_test")
load(
    ":declaration.bzl",
    "LIBRARY_NODES",
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

def tests_error(declaration, derived):
    """The error of a declaration that the tests cannot be declared from, or None.

    Args:
      declaration: a struct returned by `parse_declaration` for a test, without error.
      derived: the fragments `derive_fragments` returns for its sources.

    Returns:
      The message for the first of `jvm`, `android` and `native` that sets `associates`, which
      the macro sets, and otherwise for the first listed platform that compiles no source, whose
      test would run nothing. None without either.
    """
    for node in LIBRARY_NODES:
        if _ASSOCIATES in declaration.settings[node]:
            return "%s sets %s, which the macro sets to the library of the platform" % (node, _ASSOCIATES)
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

    The tests of the JVM and of Android use JUnit 4, e.g. through `kotlin-test-junit`, and run
    every public class of their own jar that has a method annotated with `@Test` (or is annotated
    with `@RunWith`); a jar without any fails the test. Setting `test_class` in `jvm` or `android`,
    or a `main_class` other than the test runner of Bazel, runs that instead. The native test runs
    like any `kt_native_test`: `bazel test` runs it for the konan target of the exec host, and it
    is incompatible with the platforms of the konan targets that `platforms` does not list.
    `bazel test <name>` runs the tests of every platform that the build's platform is compatible
    with.

    The macro checks the declaration when it is called and fails with what to change, as
    `kt_multiplatform_library` does, and also for a platform that no list gives test sources.

    Args:
      name: the name of the test_suite, and the prefix of the names of the other targets.
      library: the label of the `kt_multiplatform_library` under test, the one of its alias.
      platforms: the platforms to test, in any order, among those of the library, e.g.
        `["jvm", "macos_arm64", "linux_x64"]`. The macro declares `<name>_jvm` for `jvm`,
        `<name>_android` for `android` and `<name>_native` for the konan targets.
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
        {"android": android, "jvm": jvm, "native": native},
        kwargs,
        aliases = aliases,
        normalize = normalize,
        attrs = TEST_QUALIFIED_ATTRS,
        kind = "test",
    )
    if declaration.error:
        fail("kt_multiplatform_test %s: %s" % (name, declaration.error))

    qualifier_srcs = {
        qualifier: [normalize(label) for label in labels]
        for qualifier, labels in declaration.lists["srcs"].items()
    }
    derived = derive_fragments(qualifier_srcs, declaration.qualifiers)
    error = tests_error(declaration, derived)
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

    konan_targets = declaration.targeted.get("native", [])
    if konan_targets:
        def _native_lists(target):
            return dict(
                {attr: platform_list(declaration, attr, target) for attr in _CONCATENATED_ATTRS},
                kmp_fragments = leaf_fragments(name, derived, target),
                srcs = derived.leaf_srcs[target],
            )

        native_attrs = declaration.settings["native"]
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
