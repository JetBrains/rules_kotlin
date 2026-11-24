"""kt_native_binary: links a Kotlin/Native executable.

The srcs compile into a private klib, which the link includes in `<name>.kexe` with the klibs of the
deps (see link.bzl).
"""

load(":link.bzl", "EXECUTABLE_ATTRS", "LINK_ATTRS", "executable_runfiles", "link_native")
load(":toolchains.bzl", "KT_NATIVE_TOOLCHAIN_TYPE")
load(":transition.bzl", "kt_native_transition")

def _kt_native_binary_impl(ctx):
    tc = ctx.toolchains[KT_NATIVE_TOOLCHAIN_TYPE]
    if not ctx.files.srcs and not ctx.attr.deps:
        fail("%s: kt_native_binary has neither srcs nor deps, so nothing to link; add the srcs with `main`, or the dep with it" % ctx.label)

    binary = ctx.actions.declare_file(ctx.label.name + ".kexe")
    link_native(
        ctx,
        produce = "program",
        output = binary,
        progress_message = "Linking Kotlin/Native binary %{label} (" + tc.konan_target + ")",
    )
    return [DefaultInfo(executable = binary, files = depset([binary]), runfiles = executable_runfiles(ctx))]

kt_native_binary = rule(
    doc = """Links a Kotlin/Native executable, `<name>.kexe`, for the konan target of the build's platform.

    Experimental. The entry point is the function `main` of the root package, in the srcs or in a dep; another
    function is named in full with the konanc option `-e`: `link_opts = ["-e", "org.example.main"]`. The link
    dependencies of the target must be staged: see kotlin_native.targets(...).""",
    implementation = _kt_native_binary_impl,
    attrs = dict(LINK_ATTRS, **EXECUTABLE_ATTRS),
    cfg = kt_native_transition,
    executable = True,
    toolchains = [KT_NATIVE_TOOLCHAIN_TYPE],
)
