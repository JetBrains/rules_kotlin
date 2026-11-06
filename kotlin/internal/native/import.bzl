"""kt_klib_import: a prebuilt klib of a konan target, e.g. one of a Maven library, as a dependency of the Kotlin/Native rules.

The import compiles nothing and needs no toolchain, so it analyzes on any host: its klib only
reaches a compilation or a link of its konan target, as collect_klib_deps checks, in the import for
its own deps and exports and in its consumers. It builds with the Kotlin platform type native, like
the other Kotlin/Native rules (see transition.bzl).
"""

load(":klib.bzl", "collect_klib_deps", "native_module_name")
load(":providers.bzl", "KtKlibInfo")
load(":targets.bzl", "KONAN_TARGETS")
load(":transition.bzl", "TRANSITION_ATTRS", "kt_native_transition")

def _kt_klib_import_impl(ctx):
    konan_target = ctx.attr.konan_target
    klib = ctx.file.klib
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
            konan_target = konan_target,
            module_name = native_module_name(ctx),
            platform = "native",
            transitive_klibs = depset(
                [klib],
                transitive = [collect_klib_deps(konan_target, ctx.attr.deps + ctx.attr.exports)],
            ),
        ),
    ]

kt_klib_import = rule(
    doc = """Imports a prebuilt klib of a konan target, which the Kotlin/Native rules compile against and link like the klib of a kt_native_library.

    Experimental. The klib is for one konan target, e.g. the klib of the `linuxx64` variant of a Kotlin
    Multiplatform library on Maven for `linux_x64`; its deps and exports are klibs of the same target.
    A consumer of another konan target fails. The cinterop klibs of a library are imports of their own,
    deps of the import of its main klib, so they follow it wherever it is compiled against or linked.""",
    implementation = _kt_klib_import_impl,
    attrs = dict(TRANSITION_ATTRS, **{
        "deps": attr.label_list(
            doc = """The klibs the klib depends on, e.g. its cinterop klibs: its consumers compile against them and link
            them with it. They are for the same konan target.""",
            providers = [KtKlibInfo],
        ),
        "exports": attr.label_list(
            doc = """Klibs the klib depends on and re-exports: its consumers compile against them as if they listed them
            in their own deps. They are for the same konan target.""",
            providers = [KtKlibInfo],
        ),
        "klib": attr.label(
            doc = "The .klib file.",
            allow_single_file = [".klib"],
            mandatory = True,
        ),
        "konan_target": attr.string(
            doc = "The konan target of the klib, e.g. `linux_x64`.",
            mandatory = True,
            values = sorted(KONAN_TARGETS.keys()),
        ),
        "module_name": attr.string(
            doc = """The module name of the klib, for information: konanc reads the unique_name of a klib from its manifest.
            By default it is derived from the label, as for the other rules.""",
        ),
    }),
    cfg = kt_native_transition,
    provides = [KtKlibInfo],
)
