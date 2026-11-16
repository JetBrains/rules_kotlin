"""Providers for Kotlin/Native rules."""

KtKlibInfo = provider(
    doc = """A Kotlin library compiled to a .klib.

    The Kotlin/Native rules produce and consume klibs for a konan target. `platform` leaves room for
    the klibs of other Kotlin platforms (JS, Wasm), which share the format.""",
    fields = {
        "cc_info": "(CcInfo or None) The C libraries the klib binds, which a binary linking it needs; None until cinterop is supported.",
        "compile_klib": "(File) The klib dependents compile against: the header klib of the target, its declarations without function bodies, when it writes one (see the build setting experimental_native_header_klibs), else `klib`.",
        "exported_klibs": "(depset[File]) The klibs this target re-exports to its dependents: its exports and theirs.",
        "klib": "(File) The .klib this target produces.",
        "konan_target": "(str or None) The konan target the klib is compiled for, e.g. linux_x64; None for a klib of another platform.",
        "module_name": "(str) The module name, the unique_name of the klib manifest.",
        "platform": "(str) The Kotlin platform of the klib: 'native' (later also 'js', 'wasm_js' or 'wasm_wasi').",
        "transitive_compile_klibs": "(depset[File]) The compile_klib of the target and those of its deps and exports, transitively: what a compilation against it reads.",
        "transitive_klibs": "(depset[File]) The klib and the klibs of its deps and exports, transitively: the full klibs, which a link of it reads.",
    },
)
