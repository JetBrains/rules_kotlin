"""Providers for Kotlin/Native rules."""

KtKlibInfo = provider(
    doc = "A Kotlin/Native library compiled to a .klib, for one konan target.",
    fields = {
        "compile_klib": "(File) The klib dependents compile against: the header klib of the target, its declarations without function bodies, when it writes one (see the build setting experimental_native_header_klibs), else `klib`.",
        "exported_klibs": "(depset[File]) The klibs this target re-exports to its dependents: its exports and theirs.",
        "klib": "(File) The .klib this target produces.",
        "konan_target": "(str) The konan target the klib is compiled for, e.g. linux_x64.",
        "transitive_compile_klibs": "(depset[File]) The compile_klib of the target and those of its deps and exports, transitively: what a compilation against it reads.",
        "transitive_klibs": "(depset[File]) The klib and the klibs of its deps and exports, transitively: the full klibs, which a link of it reads.",
    },
)
