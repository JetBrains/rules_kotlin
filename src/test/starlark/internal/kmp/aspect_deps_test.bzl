"""Analysis tests of the deps of source sets reaching the aspects of the consumers of a JVM or Android library.

The aspects of other rule sets follow Bazel's conventional dependency attributes, deps, exports and
runtime_deps, and not source_sets: the dexing aspect of the android_binary of rules_android dexes
the jars of the targets it reaches and fails on a jar of the runtime classpath it did not reach. A
library lists its source sets in runtime_deps as well, as kt_multiplatform_library does for its JVM
and Android libraries, so that such an aspect reaches the source sets and follows their deps. The
aspect of the mobile-install of rules_android (mobile_install/adapters/default.bzl) is stricter: a
target without JavaInfo forwards nothing, not even what the aspect reached through its deps. A
source set therefore provides a JavaInfo of no classes of its own, which exports its deps. The
tests apply an aspect of that stricter shape to the JVM library (the Android one takes the same
attributes and code path, see kt_android_library_impl.bzl), check which JVM libraries it reaches
and that the JavaInfo of a source set adds no jar such an aspect would dex twice.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_java//java:defs.bzl", "JavaInfo", "java_library")
load("//kotlin:jvm.bzl", "kt_jvm_library")
load("//kotlin:kmp.bzl", "kt_multiplatform_library", "kt_source_set")

_PACKAGE = "src/test/starlark/internal/kmp"

_ReachedInfo = provider(
    doc = "The targets an aspect following the conventional dependency attributes reaches.",
    fields = {
        "labels": "depset of string: the labels of the reached targets that provide JavaInfo, as the dexing aspect dexes their jars.",
    },
)

# The attributes the dexing aspects of rules_android follow (dex_desugar_aspect.bzl and
# mobile_install/adapters/default.bzl: deps, exports, runtime_deps, and their own implicit ones).
_CONVENTIONAL_ATTRS = ["deps", "exports", "runtime_deps"]

def _reached_aspect_impl(target, ctx):
    # As the default adapter of mobile-install: a target without JavaInfo forwards nothing.
    if JavaInfo not in target:
        return [_ReachedInfo(labels = depset())]
    return [_ReachedInfo(labels = depset(
        [str(target.label)],
        transitive = [
            dep[_ReachedInfo].labels
            for attr in _CONVENTIONAL_ATTRS
            for dep in getattr(ctx.rule.attr, attr, [])
            if _ReachedInfo in dep
        ],
    ))]

_reached_aspect = aspect(
    implementation = _reached_aspect_impl,
    attr_aspects = _CONVENTIONAL_ATTRS,
)

def _label(name):
    return str(Label("//%s:%s" % (_PACKAGE, name)))

def _reached(env):
    """The labels of the targets of this test the aspect reached, sorted: the order of a depset is unspecified."""
    labels = analysistest.target_under_test(env)[_ReachedInfo].labels.to_list()
    return sorted([label for label in labels if label.startswith(_label("ad_"))])

def _runtime_jars(env):
    """The basenames of the jars of this test on the runtime classpath, and of the empty jar of the source sets, if there."""
    jars = analysistest.target_under_test(env)[JavaInfo].transitive_runtime_jars.to_list()
    return sorted([jar.basename for jar in jars if jar.basename.startswith("libad_") or jar.basename == "empty.jar"])

def _multiplatform_jvm_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The JVM library of the macro lists the common source set and the intermediate one in
    # runtime_deps: the aspect reaches the deps of both through them, as the source sets provide a
    # JavaInfo.
    asserts.equals(
        env,
        [
            _label("ad_common_lib"),
            _label("ad_intermediate"),
            _label("ad_intermediate_lib"),
            _label("ad_mpp_common"),
            _label("ad_mpp_jvm"),
        ],
        _reached(env),
    )

    # The source sets add nothing to the runtime classpath, not even their empty jar: it is the one
    # of source_sets.
    asserts.equals(env, ["libad_common_lib.jar", "libad_intermediate_lib.jar"], _runtime_jars(env))

    return analysistest.end(env)

def _explicit_jvm_test_impl(ctx):
    env = analysistest.begin(ctx)

    # A library of the explicit form that lists its source sets in source_sets alone compiles
    # against their deps, which the aspect does not reach: source_sets is no conventional attribute.
    asserts.equals(env, [_label("ad_explicit_jvm")], _reached(env))
    asserts.equals(env, ["libad_common_lib.jar", "libad_intermediate_lib.jar"], _runtime_jars(env))

    return analysistest.end(env)

def _explicit_jvm_runtime_deps_test_impl(ctx):
    env = analysistest.begin(ctx)

    # Listed in runtime_deps as well, the source set and the one it refines lead the aspect to their
    # deps; the common source set is one the library compiles, through the intermediate one, although
    # it is not in source_sets.
    asserts.equals(
        env,
        [
            _label("ad_common_lib"),
            _label("ad_explicit_jvm_runtime_deps"),
            _label("ad_intermediate"),
            _label("ad_intermediate_lib"),
            _label("ad_mpp_common"),
        ],
        _reached(env),
    )
    asserts.equals(env, ["libad_common_lib.jar", "libad_intermediate_lib.jar"], _runtime_jars(env))

    return analysistest.end(env)

def _source_set_java_info_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The JavaInfo of the intermediate source set: the empty jar is its only jar of its own, so an
    # aspect dexing the jars of the targets it reaches dexes nothing twice, and it exports its deps,
    # not those of the source set it refines, which runtime_deps lists itself.
    java_info = analysistest.target_under_test(env)[JavaInfo]
    asserts.equals(env, ["empty.jar"], [jar.basename for jar in java_info.runtime_output_jars])
    asserts.equals(env, ["empty.jar"], [output.class_jar.basename for output in java_info.java_outputs])
    asserts.equals(env, ["empty.jar", "libad_intermediate_lib.jar"], _runtime_jars(env))
    asserts.equals(
        env,
        ["ad_intermediate_lib", "empty"],
        sorted([jar.owner.name for jar in java_info.compile_jars.to_list()]),
    )

    # A source set still compiles nothing.
    asserts.equals(env, [], analysistest.target_actions(env))

    return analysistest.end(env)

def _not_compiled_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.expect_failure(env, "the source set %s in runtime_deps is none the target compiles" % _label("ad_intermediate"))

    return analysistest.end(env)

def _in_deps_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The JavaInfo makes a source set acceptable to deps and exports, where it would export its deps
    # and compile none of its sources: the rule rejects it.
    asserts.expect_failure(env, "deps lists the source set %s, which is compiled, not depended on" % _label("ad_mpp_common"))

    return analysistest.end(env)

def _in_exports_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The same for a library without sources, which only forwards its exports.
    asserts.expect_failure(env, "exports lists the source set %s, which is compiled, not depended on" % _label("ad_mpp_common"))

    return analysistest.end(env)

multiplatform_jvm_test = analysistest.make(_multiplatform_jvm_test_impl, extra_target_under_test_aspects = [_reached_aspect])
explicit_jvm_test = analysistest.make(_explicit_jvm_test_impl, extra_target_under_test_aspects = [_reached_aspect])
explicit_jvm_runtime_deps_test = analysistest.make(_explicit_jvm_runtime_deps_test_impl, extra_target_under_test_aspects = [_reached_aspect])
source_set_java_info_test = analysistest.make(_source_set_java_info_test_impl)
not_compiled_test = analysistest.make(_not_compiled_test_impl, expect_failure = True)
in_deps_test = analysistest.make(_in_deps_test_impl, expect_failure = True)
in_exports_test = analysistest.make(_in_exports_test_impl, expect_failure = True)

def aspect_deps_test_suite(name):
    """Declares a multiplatform library with deps of its source sets, explicit libraries of them and the tests of the aspects reaching the deps.

    Args:
      name: the name of the generated test_suite target.
    """
    java_library(
        name = "ad_common_lib",
        srcs = ["testdata/PlatformTypeLib.java"],
        tags = ["manual"],
    )
    java_library(
        name = "ad_intermediate_lib",
        srcs = ["testdata/PlatformTypeLib.java"],
        tags = ["manual"],
    )

    # An intermediate source set with a dep of its own, Gradle's nonAndroidMain, which the JVM
    # library compiles with the common one.
    kt_source_set(
        name = "ad_intermediate",
        srcs = ["testdata/Description.native.kt"],
        depends_on = [":ad_mpp_common"],
        tags = ["manual"],
        deps = [":ad_intermediate_lib"],
    )
    kt_multiplatform_library(
        name = "ad_mpp",
        common_deps = [":ad_common_lib"],
        common_srcs = [
            "testdata/Platform.kt",
            "testdata/Greeting.kt",
        ],
        jvm = dict(
            srcs = ["testdata/Platform.jvm.kt"],
            source_sets = [":ad_intermediate"],
        ),
        tags = ["manual"],
    )

    # The explicit form: the source sets in source_sets alone, and also in runtime_deps.
    kt_jvm_library(
        name = "ad_explicit_jvm",
        srcs = ["testdata/Platform.jvm.kt"],
        source_sets = [":ad_intermediate"],
        tags = ["manual"],
    )
    kt_jvm_library(
        name = "ad_explicit_jvm_runtime_deps",
        srcs = ["testdata/Platform.jvm.kt"],
        source_sets = [":ad_intermediate"],
        tags = ["manual"],
        runtime_deps = [
            ":ad_intermediate",
            ":ad_mpp_common",
        ],
    )

    # A source set in runtime_deps that the library does not compile: the intermediate one refines
    # the common one, not the other way round.
    kt_jvm_library(
        name = "ad_not_compiled",
        srcs = ["testdata/Platform.jvm.kt"],
        source_sets = [":ad_mpp_common"],
        tags = ["manual"],
        runtime_deps = [":ad_intermediate"],
    )

    # A source set in deps, where it belongs in source_sets, and one in the exports of a library
    # without sources.
    kt_jvm_library(
        name = "ad_in_deps",
        srcs = ["testdata/Platform.jvm.kt"],
        tags = ["manual"],
        deps = [":ad_mpp_common"],
    )
    kt_jvm_library(
        name = "ad_in_exports",
        exports = [":ad_mpp_common"],
        tags = ["manual"],
    )

    multiplatform_jvm_test(
        name = "aspect_deps_multiplatform_jvm_test",
        target_under_test = ":ad_mpp_jvm",
    )
    explicit_jvm_test(
        name = "aspect_deps_explicit_jvm_test",
        target_under_test = ":ad_explicit_jvm",
    )
    explicit_jvm_runtime_deps_test(
        name = "aspect_deps_explicit_jvm_runtime_deps_test",
        target_under_test = ":ad_explicit_jvm_runtime_deps",
    )
    source_set_java_info_test(
        name = "aspect_deps_source_set_java_info_test",
        target_under_test = ":ad_intermediate",
    )
    not_compiled_test(
        name = "aspect_deps_not_compiled_fails_test",
        target_under_test = ":ad_not_compiled",
    )
    in_deps_test(
        name = "aspect_deps_in_deps_fails_test",
        target_under_test = ":ad_in_deps",
    )
    in_exports_test(
        name = "aspect_deps_in_exports_fails_test",
        target_under_test = ":ad_in_exports",
    )

    native.test_suite(
        name = name,
        tests = [
            ":aspect_deps_explicit_jvm_runtime_deps_test",
            ":aspect_deps_explicit_jvm_test",
            ":aspect_deps_in_deps_fails_test",
            ":aspect_deps_in_exports_fails_test",
            ":aspect_deps_multiplatform_jvm_test",
            ":aspect_deps_not_compiled_fails_test",
            ":aspect_deps_source_set_java_info_test",
        ],
    )
