"""kt_native_binary: link a Kotlin/Native executable.

Compiles .kt sources + transitive klib deps into a native executable for the resolved
konan target (`-produce program`), with the shared action of klib.bzl.

Binary linking needs the konan dependency bundle (LLVM + libffi + lldb + cross-toolchain)
that klib compilation does not. The bundle of each exec host is pre-fetched by its
`com_github_jetbrains_kotlin_native_deps_<host>` repository (at repo-fetch time), and the
launcher stages the target's dependency dirs into the action-local konan data dir, so this
action runs **sandboxed with no network** (verified for linux_x64 with
--sandbox_default_allow_network=false).

Caveat: Apple *targets* still need a local Xcode SDK for the platform sysroot (read from
the host via xcrun); that part is not vendorable. Non-Apple cross targets (e.g. linux_x64)
are fully hermetic. The targets a bundle stages are the ones of kotlin_native.targets(...)
— see src/main/starlark/core/repositories/native_compiler.bzl.
"""

load(":klib.bzl", "collect_klib_deps", "kt_native_compile", "native_module_name")
load(":providers.bzl", "KtKlibInfo")
load(":toolchains.bzl", "KT_NATIVE_TOOLCHAIN_TYPE")

def _kt_native_binary_impl(ctx):
    tc = ctx.toolchains[KT_NATIVE_TOOLCHAIN_TYPE]
    if not tc.konan_deps.staged:
        fail(("%s: the Kotlin/Native link dependencies of %s are not staged, so nothing links for it; " +
              "add '%s' to kotlin_native.targets(...) in the root MODULE.bazel") %
             (ctx.label, tc.konan_target, tc.konan_target))

    binary = ctx.actions.declare_file(ctx.label.name + ".kexe")
    kt_native_compile(
        ctx,
        produce = "program",
        output = binary,
        srcs = ctx.files.srcs,
        klib_deps = collect_klib_deps(tc.konan_target, ctx.attr.deps),
        module_name = native_module_name(ctx),
        stage_link_deps = True,
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
            providers = [KtKlibInfo],
        ),
        "module_name": attr.string(
            doc = "The Kotlin module name; by default it is derived from the label, as for the JVM rules.",
        ),
        "srcs": attr.label_list(
            doc = "Kotlin sources (must define an entry point / main).",
            allow_files = [".kt"],
        ),
    },
    toolchains = [KT_NATIVE_TOOLCHAIN_TYPE],
)
