"""Tests of the exports of kt_jvm_import: any JVM library, not only a Kotlin one, as of kt_jvm_library."""

load("@rules_java//java:defs.bzl", "java_import")
load("@rules_java//java/common:java_info.bzl", "JavaInfo")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("//kotlin:jvm.bzl", "kt_jvm_import")
load("//src/test/starlark:case.bzl", "suite")

_IMPORTED_JAR = "imported.jar"
_EXPORTED_JAR = "exported.jar"
_IMPORTING = "importing"

def _basenames(files):
    return [f.basename for f in files.to_list()]

def _exports_assertion(env, target):
    # The consumers of the import compile against the exported jar (its ijar, as java_import
    # provides it) as well as the imported one, and run with both. The fixtures are named after the
    # test case, as the target is.
    prefix = target.label.name[:-len(_IMPORTING)]
    java_info = target[JavaInfo]
    env.expect.that_collection(_basenames(java_info.transitive_compile_time_jars)).contains_exactly([
        prefix + _IMPORTED_JAR,
        prefix + _EXPORTED_JAR.replace(".jar", "-ijar.jar"),
    ])
    env.expect.that_collection(_basenames(java_info.transitive_runtime_jars)).contains_exactly([
        prefix + _IMPORTED_JAR,
        prefix + _EXPORTED_JAR,
    ])

def _exports_a_java_import_case(test):
    # A library without KtJvmInfo, as a java_import of a plain jar or an aar_import of an Android archive.
    exported = test.have(
        java_import,
        name = "exported",
        jars = [test.artifact(name = _EXPORTED_JAR)],
    )
    importing = test.got(
        kt_jvm_import,
        name = "importing",
        jar = test.artifact(name = _IMPORTED_JAR),
        exports = [exported],
    )
    analysis_test(
        name = test.name,
        impl = _exports_assertion,
        target = importing,
    )

def import_exports_tests(name):
    suite(
        name,
        kt_jvm_import_exports_a_java_import = _exports_a_java_import_case,
    )
