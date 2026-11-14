"""Analysis tests of the deps of a multiplatform library reaching the aspects of the consumers of its JVM library.

The aspects of other rule sets follow Bazel's conventional dependency attributes, deps, exports and
runtime_deps: the dexing aspect of the android_binary of rules_android dexes the jars of the targets
it reaches and fails on a jar of the runtime classpath it did not reach, and the aspect of its
mobile-install forwards nothing from a target without JavaInfo. The fragments of a
kt_multiplatform_library have no deps: each platform lists the deps it compiles them against in its
own deps, so such an aspect reaches every jar of the runtime classpath of the library, and nothing
of the fragments is on it. The tests apply an aspect of that stricter shape to the JVM library (the
Android one takes the same attributes and code path, see kt_android_library_impl.bzl).
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_java//java:defs.bzl", "JavaInfo", "java_library")
load("//kotlin:kmp.bzl", "kt_multiplatform_library")

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

def _multiplatform_jvm_test_impl(ctx):
    env = analysistest.begin(ctx)

    # The aspect reaches the deps of the JVM library, which it compiles its fragments against too.
    target = analysistest.target_under_test(env)
    labels = target[_ReachedInfo].labels.to_list()
    asserts.equals(
        env,
        [_label("ad_common_lib"), _label("ad_jvm_lib"), _label("ad_mpp_jvm")],
        sorted([label for label in labels if label.startswith(_label("ad_"))]),
    )

    # The runtime classpath holds the jar of the library and those of its deps, and nothing of the
    # fragments.
    jars = target[JavaInfo].transitive_runtime_jars.to_list()
    asserts.equals(
        env,
        ["ad_mpp_jvm.jar", "libad_common_lib.jar", "libad_jvm_lib.jar"],
        sorted([jar.basename for jar in jars if jar.basename.startswith(("ad_", "libad_")) or jar.basename == "empty.jar"]),
    )

    return analysistest.end(env)

multiplatform_jvm_test = analysistest.make(_multiplatform_jvm_test_impl, extra_target_under_test_aspects = [_reached_aspect])

def aspect_deps_test_suite(name):
    """Declares a multiplatform library with deps of its platforms, and the test of the aspects reaching them.

    Args:
      name: the name of the generated test_suite target.
    """
    java_library(
        name = "ad_common_lib",
        srcs = ["testdata/PlatformTypeLib.java"],
        tags = ["manual"],
    )
    java_library(
        name = "ad_jvm_lib",
        srcs = ["testdata/PlatformTypeLib.java"],
        tags = ["manual"],
    )

    # The common sources use the common lib, which every platform lists, and the JVM sources the JVM
    # one.
    kt_multiplatform_library(
        name = "ad_mpp",
        jvm = dict(
            srcs = [
                "testdata/Platform.kt",
                "testdata/Greeting.kt",
                "testdata/Platform.jvm.kt",
            ],
            deps = [
                ":ad_common_lib",
                ":ad_jvm_lib",
            ],
        ),
        native = {
            "linux": dict(
                srcs = [
                    "testdata/Platform.kt",
                    "testdata/Greeting.kt",
                    "testdata/Platform.linux.kt",
                ],
                targets = ["linux_arm64"],
            ),
        },
        tags = ["manual"],
    )

    multiplatform_jvm_test(
        name = "aspect_deps_multiplatform_jvm_test",
        target_under_test = ":ad_mpp_jvm",
    )

    native.test_suite(
        name = name,
        tests = [":aspect_deps_multiplatform_jvm_test"],
    )
