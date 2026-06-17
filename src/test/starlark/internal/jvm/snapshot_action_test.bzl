load("@rules_testing//lib:analysis_test.bzl", "analysis_test")
load("@rules_testing//lib:test_suite.bzl", "test_suite")
load("@rules_testing//lib:util.bzl", "util")
load("@rules_java//java:defs.bzl", "java_import")
load("//kotlin:jvm.bzl", "kt_jvm_library")
load("//kotlin/internal:defs.bzl", _KtJvmInfo = "KtJvmInfo")
load("//src/test/starlark:truth.bzl", "flags_and_values_of")

def _snapshot_action_test_impl(env, target):
    target_subject = env.expect.that_target(target)
    target_subject.action_named("KotlinClasspathSnapshot")

def _snapshot_flag_wiring_test_impl(env, target):
    compile_action = env.expect.that_target(target).action_named("KotlinCompile")
    parsed_flags = flags_and_values_of(compile_action)
    parsed_flags.transform(
        desc = "classpath snapshot flag wiring",
        map_each = lambda item: (
            item[0] == "--classpath_snapshots" and
            len(item[1]) == 1 and
            item[1][0].endswith(env.ctx.attr.want_snapshot_suffix)
        ),
    ).contains(True)

def _snapshot_action_test(name):
    dep_name = name + "_dep"
    subject_name = name + "_subject"
    kt_jvm_library(
        name = dep_name,
        srcs = [util.empty_file(dep_name + ".kt")],
        tags = ["manual"],
    )
    kt_jvm_library(
        name = subject_name,
        srcs = [util.empty_file(subject_name + ".kt")],
        deps = [dep_name],
        tags = ["manual"],
    )

    analysis_test(
        name = name,
        impl = _snapshot_action_test_impl,
        target = subject_name,
    )

def _snapshot_flag_wiring_test(name):
    dep_name = name + "_dep"
    subject_name = name + "_subject"
    kt_jvm_library(
        name = dep_name,
        srcs = [util.empty_file(dep_name + ".kt")],
        tags = ["manual"],
    )
    kt_jvm_library(
        name = subject_name,
        srcs = [util.empty_file(subject_name + ".kt")],
        deps = [dep_name],
        tags = ["manual"],
    )

    analysis_test(
        name = name,
        impl = _snapshot_flag_wiring_test_impl,
        target = subject_name,
        attr_values = {
            "want_snapshot_suffix": dep_name + ".classpath-snapshot",
        },
        attrs = {
            "want_snapshot_suffix": attr.string(),
        },
    )

def _snapshot_flag_wiring_transitive_test_impl(env, target):
    def _has_snapshot_suffix(values, suffix):
        for value in values:
            if value.endswith(suffix):
                return True
        return False

    compile_action = env.expect.that_target(target).action_named("KotlinCompile")
    parsed_flags = flags_and_values_of(compile_action)
    parsed_flags.transform(
        desc = "transitive classpath snapshot flag wiring",
        map_each = lambda item: (
            item[0] == "--classpath_snapshots" and
            _has_snapshot_suffix(item[1], env.ctx.attr.want_direct_snapshot_suffix) and
            _has_snapshot_suffix(item[1], env.ctx.attr.want_transitive_snapshot_suffix)
        ),
    ).contains(True)

def _snapshot_flag_wiring_transitive_test(name):
    transitive_dep_name = name + "_transitive_dep"
    direct_dep_name = name + "_direct_dep"
    subject_name = name + "_subject"

    kt_jvm_library(
        name = transitive_dep_name,
        srcs = [util.empty_file(transitive_dep_name + ".kt")],
        tags = ["manual"],
    )
    kt_jvm_library(
        name = direct_dep_name,
        srcs = [util.empty_file(direct_dep_name + ".kt")],
        deps = [transitive_dep_name],
        tags = ["manual"],
    )
    kt_jvm_library(
        name = subject_name,
        srcs = [util.empty_file(subject_name + ".kt")],
        deps = [direct_dep_name],
        tags = ["manual"],
    )

    analysis_test(
        name = name,
        impl = _snapshot_flag_wiring_transitive_test_impl,
        target = subject_name,
        attr_values = {
            "want_direct_snapshot_suffix": direct_dep_name + ".classpath-snapshot",
            "want_transitive_snapshot_suffix": transitive_dep_name + ".classpath-snapshot",
        },
        attrs = {
            "want_direct_snapshot_suffix": attr.string(),
            "want_transitive_snapshot_suffix": attr.string(),
        },
    )

def _snapshot_flag_wiring_java_only_dep_test_impl(env, target):
    compile_action = env.expect.that_target(target).action_named("KotlinCompile")
    parsed_flags = flags_and_values_of(compile_action)
    parsed_flags.transform(
        desc = "java-only dependency snapshot wiring",
        map_each = lambda item: (
            item[0] == "--classpath_snapshots" and
            len(item[1]) > 0
        ),
    ).contains(True)

def _snapshot_flag_wiring_java_only_dep_test(name):
    java_dep_name = name + "_java_dep"
    subject_name = name + "_subject"

    java_import(
        name = java_dep_name,
        jars = [util.empty_file(java_dep_name + ".jar")],
        tags = ["manual"],
    )

    kt_jvm_library(
        name = subject_name,
        srcs = [util.empty_file(subject_name + ".kt")],
        deps = [java_dep_name],
        tags = ["manual"],
    )

    analysis_test(
        name = name,
        impl = _snapshot_flag_wiring_java_only_dep_test_impl,
        target = subject_name,
    )

def _snapshot_flag_wiring_exports_transitive_test_impl(env, target):
    def _has_snapshot_suffix(values, suffix):
        for value in values:
            if value.endswith(suffix):
                return True
        return False

    compile_action = env.expect.that_target(target).action_named("KotlinCompile")
    parsed_flags = flags_and_values_of(compile_action)
    parsed_flags.transform(
        desc = "exported transitive classpath snapshot flag wiring",
        map_each = lambda item: (
            item[0] == "--classpath_snapshots" and
            _has_snapshot_suffix(item[1], env.ctx.attr.want_exported_snapshot_suffix)
        ),
    ).contains(True)

def _snapshot_flag_wiring_exports_transitive_test(name):
    exported_dep_name = name + "_exported_dep"
    exporter_name = name + "_exporter"
    subject_name = name + "_subject"

    kt_jvm_library(
        name = exported_dep_name,
        srcs = [util.empty_file(exported_dep_name + ".kt")],
        tags = ["manual"],
    )
    kt_jvm_library(
        name = exporter_name,
        srcs = [util.empty_file(exporter_name + ".kt")],
        exports = [exported_dep_name],
        tags = ["manual"],
    )
    kt_jvm_library(
        name = subject_name,
        srcs = [util.empty_file(subject_name + ".kt")],
        deps = [exporter_name],
        tags = ["manual"],
    )

    analysis_test(
        name = name,
        impl = _snapshot_flag_wiring_exports_transitive_test_impl,
        target = subject_name,
        attr_values = {
            "want_exported_snapshot_suffix": exported_dep_name + ".classpath-snapshot",
        },
        attrs = {
            "want_exported_snapshot_suffix": attr.string(),
        },
    )

def _snapshot_flag_wiring_transitive_java_only_dep_test_impl(env, target):
    def _has_snapshot_suffix(values, suffix):
        for value in values:
            if value.endswith(suffix):
                return True
        return False

    compile_action = env.expect.that_target(target).action_named("KotlinCompile")
    parsed_flags = flags_and_values_of(compile_action)
    parsed_flags.transform(
        desc = "transitive java-only dependency snapshot flag wiring",
        map_each = lambda item: (
            item[0] == "--classpath_snapshots" and
            _has_snapshot_suffix(item[1], env.ctx.attr.want_java_snapshot_suffix)
        ),
    ).contains(True)

def _snapshot_flag_wiring_transitive_java_only_dep_test(name):
    # kt subject -> kt middle -> java-only leaf. The leaf carries no KtJvmInfo, so its snapshot is
    # generated locally by the middle target; the subject sees it only if the middle publishes it
    # transitively. Guards the 2-hop Java-only IC gap (otherwise a silent miscompile).
    java_dep_name = name + "_java_dep"
    middle_dep_name = name + "_middle_dep"
    subject_name = name + "_subject"

    java_import(
        name = java_dep_name,
        jars = [util.empty_file(java_dep_name + ".jar")],
        tags = ["manual"],
    )
    kt_jvm_library(
        name = middle_dep_name,
        srcs = [util.empty_file(middle_dep_name + ".kt")],
        deps = [java_dep_name],
        tags = ["manual"],
    )
    kt_jvm_library(
        name = subject_name,
        srcs = [util.empty_file(subject_name + ".kt")],
        deps = [middle_dep_name],
        tags = ["manual"],
    )

    analysis_test(
        name = name,
        impl = _snapshot_flag_wiring_transitive_java_only_dep_test_impl,
        target = subject_name,
        attr_values = {
            "want_java_snapshot_suffix": middle_dep_name + ".non-kotlin-dep-0.classpath-snapshot",
        },
        attrs = {
            "want_java_snapshot_suffix": attr.string(),
        },
    )

def _snapshot_flag_wiring_export_only_shim_java_dep_test_impl(env, target):
    def _has_snapshot_suffix(values, suffix):
        for value in values:
            if value.endswith(suffix):
                return True
        return False

    compile_action = env.expect.that_target(target).action_named("KotlinCompile")
    parsed_flags = flags_and_values_of(compile_action)
    parsed_flags.transform(
        desc = "export-only shim java-only dependency snapshot flag wiring",
        map_each = lambda item: (
            item[0] == "--classpath_snapshots" and
            _has_snapshot_suffix(item[1], env.ctx.attr.want_java_snapshot_suffix)
        ),
    ).contains(True)

def _snapshot_flag_wiring_export_only_shim_java_dep_test(name):
    # kt subject -> sourceless export-only kt shim (exports a java-only dep) -> java-only leaf. The
    # shim runs no compile action, so it must still generate + publish the leaf's snapshot; otherwise
    # the subject never sees the leaf's ABI changes -- a silent IC miss through the re-export shim.
    java_dep_name = name + "_java_dep"
    shim_name = name + "_shim"
    subject_name = name + "_subject"

    java_import(
        name = java_dep_name,
        jars = [util.empty_file(java_dep_name + ".jar")],
        tags = ["manual"],
    )
    kt_jvm_library(
        name = shim_name,
        exports = [java_dep_name],
        tags = ["manual"],
    )
    kt_jvm_library(
        name = subject_name,
        srcs = [util.empty_file(subject_name + ".kt")],
        deps = [shim_name],
        tags = ["manual"],
    )

    analysis_test(
        name = name,
        impl = _snapshot_flag_wiring_export_only_shim_java_dep_test_impl,
        target = subject_name,
        attr_values = {
            "want_java_snapshot_suffix": shim_name + ".non-kotlin-dep-0.classpath-snapshot",
        },
        attrs = {
            "want_java_snapshot_suffix": attr.string(),
        },
    )

def _snapshot_export_only_shim_publishes_under_prune_test_impl(env, target):
    # Producers publish their full snapshot set regardless of their own prune state: pruning is a
    # consumer-side projection (jvm_deps), and a consumer may opt out of pruning per-target via the
    # kt_experimental_prune_transitive_deps_incompatible tag. So even when built under prune, the
    # sourceless export-only shim must still publish its Java-only export snapshot -- otherwise a
    # non-pruned consumer of this shim would silently miss that dependency's ABI changes.
    has_non_kotlin_snapshot = False
    for f in target[_KtJvmInfo].transitive_classpath_snapshots.to_list():
        if "non-kotlin-dep" in f.basename:
            has_non_kotlin_snapshot = True
    env.expect.that_bool(has_non_kotlin_snapshot).equals(True)

def _snapshot_export_only_shim_publishes_under_prune_test(name):
    java_dep_name = name + "_java_dep"
    shim_name = name + "_shim"

    java_import(
        name = java_dep_name,
        jars = [util.empty_file(java_dep_name + ".jar")],
        tags = ["manual"],
    )
    kt_jvm_library(
        name = shim_name,
        exports = [java_dep_name],
        tags = ["manual"],
    )

    analysis_test(
        name = name,
        impl = _snapshot_export_only_shim_publishes_under_prune_test_impl,
        target = shim_name,
        config_settings = {
            str(Label("@rules_kotlin//kotlin/settings:experimental_prune_transitive_deps")): True,
            str(Label("@rules_kotlin//kotlin/settings:experimental_strict_associate_dependencies")): False,
        },
    )

def _snapshot_pruned_consumer_drops_dep_java_snapshot_test_impl(env, target):
    def _has_suffix(values, suffix):
        for value in values:
            if value.endswith(suffix):
                return True
        return False

    compile_action = env.expect.that_target(target).action_named("KotlinCompile")

    # The middle Kotlin dep's own ABI snapshot survives pruning -- it is a direct dep, pulled via the
    # consumer's `direct` arm (the scalar classpath_snapshot field).
    flags_and_values_of(compile_action).transform(
        desc = "direct dep's own ABI snapshot kept under prune",
        map_each = lambda item: (
            item[0] == "--classpath_snapshots" and
            _has_suffix(item[1], env.ctx.attr.want_own_suffix)
        ),
    ).contains(True)

    # The middle dep's Java-only dep snapshot lives only in its transitive_classpath_snapshots depset,
    # which the consumer drops under prune. So it must NOT reach the consumer's compile.
    flags_and_values_of(compile_action).transform(
        desc = "dependency's transitively-published Java-only snapshot dropped under prune",
        map_each = lambda item: (
            item[0] == "--classpath_snapshots" and
            _has_suffix(item[1], "non-kotlin-dep-0.classpath-snapshot")
        ),
    ).contains_none_of([True])

def _snapshot_pruned_consumer_drops_dep_java_snapshot_test(name):
    java_dep_name = name + "_java_dep"
    middle_dep_name = name + "_middle_dep"
    subject_name = name + "_subject"

    java_import(
        name = java_dep_name,
        jars = [util.empty_file(java_dep_name + ".jar")],
        tags = ["manual"],
    )
    kt_jvm_library(
        name = middle_dep_name,
        srcs = [util.empty_file(middle_dep_name + ".kt")],
        deps = [java_dep_name],
        tags = ["manual"],
    )
    kt_jvm_library(
        name = subject_name,
        srcs = [util.empty_file(subject_name + ".kt")],
        deps = [middle_dep_name],
        tags = ["manual"],
    )

    analysis_test(
        name = name,
        impl = _snapshot_pruned_consumer_drops_dep_java_snapshot_test_impl,
        target = subject_name,
        config_settings = {
            str(Label("@rules_kotlin//kotlin/settings:experimental_prune_transitive_deps")): True,
            str(Label("@rules_kotlin//kotlin/settings:experimental_strict_associate_dependencies")): False,
        },
        attr_values = {
            "want_own_suffix": middle_dep_name + ".classpath-snapshot",
        },
        attrs = {
            "want_own_suffix": attr.string(),
        },
    )

def snapshot_action_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _snapshot_action_test,
            _snapshot_flag_wiring_test,
            _snapshot_flag_wiring_transitive_test,
            _snapshot_flag_wiring_java_only_dep_test,
            _snapshot_flag_wiring_exports_transitive_test,
            _snapshot_flag_wiring_transitive_java_only_dep_test,
            _snapshot_flag_wiring_export_only_shim_java_dep_test,
            _snapshot_export_only_shim_publishes_under_prune_test,
            _snapshot_pruned_consumer_drops_dep_java_snapshot_test,
        ],
    )
