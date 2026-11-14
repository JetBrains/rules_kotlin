"""kt_native_library: compiles Kotlin sources into a Kotlin/Native klib.

The konan target is the one of the resolved toolchain (the build's --platforms), not a rule
attribute. The klib action is the shared one of klib.bzl; linking is handled separately by
kt_native_binary, kt_native_test and kt_native_framework (see link.bzl). With kmp_fragments, the
sources a kt_multiplatform_library shares compile with the srcs, as K2 fragments (see
//kotlin/internal/kmp:fragments.bzl). Like every Kotlin/Native rule, it builds with the Kotlin
platform type native (see transition.bzl).
"""

load("//kotlin/internal/kmp:fragment.bzl", "KtFragmentInfo")
load("//kotlin/internal/kmp:fragments.bzl", "collect_fragments")
load("//src/main/starlark/core/plugin:providers.bzl", "KtCompilerPluginInfo")
load(":klib.bzl", "collect_klib_deps", "kt_native_compile", "native_module_name")
load(":providers.bzl", "KtKlibInfo")
load(":toolchains.bzl", "KT_NATIVE_TOOLCHAIN_TYPE")
load(":transition.bzl", "TRANSITION_ATTRS", "kt_native_transition")

def _kt_native_library_impl(ctx):
    tc = ctx.toolchains[KT_NATIVE_TOOLCHAIN_TYPE]
    module_name = native_module_name(ctx)
    fragments = collect_fragments(ctx, ctx.attr.kmp_fragments, tc.konan_target, ctx.files.srcs)
    klib_deps = collect_klib_deps(tc.konan_target, ctx.attr.deps + ctx.attr.exports)

    klib = ctx.actions.declare_file(ctx.label.name + ".klib")
    kt_native_compile(
        ctx,
        output = klib,
        srcs = ctx.files.srcs,
        klib_deps = klib_deps,
        module_name = module_name,
        plugins = ctx.attr.plugins,
        opts = ctx.attr.opts,
        fragments = fragments,
        progress_message = "Compiling Kotlin/Native klib %{label} (" + tc.konan_target + ")",
    )

    exports = [export[KtKlibInfo] for export in ctx.attr.exports]
    return [
        DefaultInfo(files = depset([klib])),
        KtKlibInfo(
            cc_info = None,
            exported_klibs = depset(
                [export.klib for export in exports],
                transitive = [export.exported_klibs for export in exports],
            ),
            klib = klib,
            konan_target = tc.konan_target,
            module_name = module_name,
            platform = "native",
            transitive_klibs = depset([klib], transitive = [klib_deps]),
        ),
    ]

kt_native_library = rule(
    doc = """Compiles Kotlin sources into a Kotlin/Native klib, for the konan target of the build's platform.

    Experimental. Build for a konan target with `--platforms`, e.g.
    `--platforms=@rules_kotlin//kotlin/native/platforms:linux_x64`; the host platform builds for the
    host's target.""",
    implementation = _kt_native_library_impl,
    attrs = dict(TRANSITION_ATTRS, **{
        "deps": attr.label_list(
            doc = "The klibs the sources compile against, e.g. kt_native_library targets. They are for the same konan target.",
            providers = [KtKlibInfo],
        ),
        "exports": attr.label_list(
            doc = """Klibs the sources compile against that the library also re-exports: its dependents compile against
            them as if they listed them in their own deps.""",
            providers = [KtKlibInfo],
        ),
        "kmp_fragments": attr.label_list(
            doc = """The K2 fragments of a `kt_multiplatform_library` that the srcs refine: the sources the library shares
            with other platforms. `kt_multiplatform_library` sets it from the sources each platform lists; it is not set
            by hand. The Kotlin sources of the fragments, and of the fragments they refine, compile with the srcs in one
            compilation (`-Xmulti-platform`), against the deps, so the `actual` declarations of the srcs implement the
            `expect` ones of the fragments; the srcs are the leaf fragment, named after the konan target. Expect/actual
            classes are Beta in Kotlin: the rule passes `-Xexpect-actual-classes`, which acknowledges it.""",
            providers = [KtFragmentInfo],
        ),
        "module_name": attr.string(
            doc = """The Kotlin module name, which is the unique_name of the klib. By default it is derived from the label,
            as for the JVM rules.""",
        ),
        "opts": attr.string_list(
            doc = "More konanc options, e.g. `-opt-in=kotlin.ExperimentalStdlibApi`. They follow the options of the rule.",
        ),
        "plugins": attr.label_list(
            doc = """Kotlin compiler plugins (kt_compiler_plugin) to run during the compilation. The Kotlin/Native compiler
            loads them in the embeddable compiler dialect.""",
            providers = [KtCompilerPluginInfo],
            cfg = "exec",
        ),
        "srcs": attr.label_list(
            doc = "Kotlin sources.",
            allow_files = [".kt"],
        ),
    }),
    cfg = kt_native_transition,
    toolchains = [KT_NATIVE_TOOLCHAIN_TYPE],
    provides = [KtKlibInfo],
)
