"""kt_native_library: compiles Kotlin sources into a Kotlin/Native klib.

The konan target is the one of the resolved toolchain (the build's --platforms), not a rule
attribute. The klib action is the shared one of klib.bzl; binary linking is handled separately by
kt_native_binary (binary.bzl).
"""

load("//src/main/starlark/core/plugin:providers.bzl", "KtCompilerPluginInfo")
load(":klib.bzl", "collect_klib_deps", "kt_native_compile", "native_module_name")
load(":providers.bzl", "KtKlibInfo")
load(":toolchains.bzl", "KT_NATIVE_TOOLCHAIN_TYPE")

def _kt_native_library_impl(ctx):
    if ctx.attr.source_sets:
        fail("source_sets are reserved for Kotlin Multiplatform source sets, which kt_native_library does not support yet")
    tc = ctx.toolchains[KT_NATIVE_TOOLCHAIN_TYPE]
    module_name = native_module_name(ctx)
    klib_deps = collect_klib_deps(tc.konan_target, ctx.attr.deps + ctx.attr.exports)

    klib = ctx.actions.declare_file(ctx.label.name + ".klib")
    kt_native_compile(
        ctx,
        produce = "library",
        output = klib,
        srcs = ctx.files.srcs,
        klib_deps = klib_deps,
        module_name = module_name,
        plugins = ctx.attr.plugins,
        opts = ctx.attr.opts,
        mnemonic = "KotlinNativeKlibCompile",
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
    attrs = {
        "deps": attr.label_list(
            doc = "The klibs the sources compile against, e.g. kt_native_library targets. They are for the same konan target.",
            providers = [KtKlibInfo],
        ),
        "exports": attr.label_list(
            doc = """Klibs the sources compile against that the library also re-exports: its dependents compile against
            them as if they listed them in their own deps.""",
            providers = [KtKlibInfo],
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
        "source_sets": attr.label_list(
            doc = "Reserved for the Kotlin Multiplatform source sets to compile with the sources; not supported yet.",
        ),
        "srcs": attr.label_list(
            doc = "Kotlin sources.",
            allow_files = [".kt"],
        ),
    },
    toolchains = [KT_NATIVE_TOOLCHAIN_TYPE],
    provides = [KtKlibInfo],
)
