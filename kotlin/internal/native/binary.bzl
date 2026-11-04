"""kt_native_binary: link a Kotlin/Native executable.

Compiles .kt sources + transitive klib deps into a native executable for the resolved
konan target (`-produce program`).

Binary linking needs the konan dependency bundle (LLVM + libffi + lldb + cross-toolchain)
that klib compilation does not. The bundle of each exec host is pre-fetched by its
`com_github_jetbrains_kotlin_native_deps_<host>` repository (at repo-fetch time), and the
link launcher stages the target's dependency dirs into a writable KONAN_DATA_DIR, so this
action runs **sandboxed with no network** (verified for linux_x64 with
--sandbox_default_allow_network=false).

Caveat: Apple *targets* still need a local Xcode SDK for the platform sysroot (read from
the host via xcrun); that part is not vendorable. Non-Apple cross targets (e.g. linux_x64)
are fully hermetic. The targets a bundle stages are the ones of kotlin_native.targets(...)
— see src/main/starlark/core/repositories/native_compiler.bzl.
"""

load("@rules_java//java:defs.bzl", "java_common")
load(":providers.bzl", "KtNativeInfo")
load(":toolchains.bzl", "KT_NATIVE_TOOLCHAIN_TYPE")

def _kt_native_binary_impl(ctx):
    tc = ctx.toolchains[KT_NATIVE_TOOLCHAIN_TYPE]
    if not tc.konan_deps.staged:
        fail(("%s: the Kotlin/Native link dependencies of %s are not staged, so nothing links for it; " +
              "add '%s' to kotlin_native.targets(...) in the root MODULE.bazel") %
             (ctx.label, tc.konan_target, tc.konan_target))
    java_runtime = ctx.attr._java_runtime[java_common.JavaRuntimeInfo]
    module_name = ctx.attr.module_name or ctx.label.name

    transitive = []
    for dep in ctx.attr.deps:
        info = dep[KtNativeInfo]
        if info.konan_target != tc.konan_target:
            fail("dep {dep} is for target {dt}, but this target is {t}".format(
                dep = dep.label,
                dt = info.konan_target,
                t = tc.konan_target,
            ))
        transitive.append(info.transitive_klibs)
    dep_klibs = depset(transitive = transitive)

    binary = ctx.actions.declare_file(ctx.label.name + ".kexe")
    out_base = binary.path[:-len(".kexe")]  # konanc -produce program appends .kexe
    konan_data_dir = ctx.label.name + ".konan_data"  # action-local scratch (writable)
    auto_cache_dir = ctx.label.name + ".autocache"

    # launcher: <konan_home> <konan_data_dir> <auto_cache_dir> <n> <dep_dir>... [konanc args]
    args = ctx.actions.args()
    args.add(tc.konan_home.path)
    args.add(konan_data_dir)
    args.add(auto_cache_dir)
    args.add(str(len(tc.konan_deps.dirs)))
    args.add_all([d.path for d in tc.konan_deps.dirs])
    args.add("-produce", "program")
    args.add("-target", tc.konan_target)
    args.add("-module-name", module_name)
    args.add("-Xkonan-data-dir=" + konan_data_dir)
    args.add("-Xauto-cache-dir=" + auto_cache_dir)

    # A dependency missing from the bundle fails with konanc's own message, not a network error.
    args.add("-Xoverride-konan-properties=airplaneMode=true")
    args.add("-o", out_base)
    args.add_all(dep_klibs, before_each = "-l")
    args.add_all(ctx.files.srcs)

    ctx.actions.run(
        executable = ctx.executable._launcher,
        arguments = [args],
        inputs = depset(
            ctx.files.srcs,
            transitive = [dep_klibs, tc.compile_inputs, tc.konan_deps.files, java_runtime.files],
        ),
        outputs = [binary],
        env = {
            "JAVA_HOME": java_runtime.java_home,
            "KONAN_DATA_DIR": konan_data_dir,
        },
        mnemonic = "KotlinNativeLink",
        progress_message = "Linking Kotlin/Native binary %{label} (" + tc.konan_target + ")",
    )

    return [DefaultInfo(files = depset([binary]))]

kt_native_binary = rule(
    doc = "Links a Kotlin/Native executable for the resolved target.",
    implementation = _kt_native_binary_impl,
    attrs = {
        "deps": attr.label_list(
            doc = "kt_native_library targets (must be the same konan target).",
            providers = [KtNativeInfo],
        ),
        "module_name": attr.string(
            doc = "The Kotlin module name; defaults to the target name.",
        ),
        "srcs": attr.label_list(
            doc = "Kotlin sources (must define an entry point / main).",
            allow_files = [".kt"],
        ),
        "_java_runtime": attr.label(
            default = Label("@bazel_tools//tools/jdk:current_java_runtime"),
            cfg = "exec",
        ),
        "_launcher": attr.label(
            default = Label("//kotlin/internal/native:konanc_link_launcher"),
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = [KT_NATIVE_TOOLCHAIN_TYPE],
)
