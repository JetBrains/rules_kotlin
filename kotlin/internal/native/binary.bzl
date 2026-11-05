"""kt_native_binary: links a Kotlin/Native executable.

The srcs compile into a private klib, which the link includes in `<name>.kexe` with the klibs of the
deps (see link.bzl). The konan target is the one of the resolved toolchain (the build's
--platforms), and the executable runs on a host of that target, e.g. with `bazel run` on the host.
"""

load(":link.bzl", "LINK_ATTRS", "link_native")
load(":toolchains.bzl", "KT_NATIVE_TOOLCHAIN_TYPE")

def _kt_native_binary_impl(ctx):
    tc = ctx.toolchains[KT_NATIVE_TOOLCHAIN_TYPE]
    binary = ctx.actions.declare_file(ctx.label.name + ".kexe")
    link_native(
        ctx,
        rule_kind = "kt_native_binary",
        produce = "program",
        output = binary,
        progress_message = "Linking Kotlin/Native binary %{label} (" + tc.konan_target + ")",
    )
    return [DefaultInfo(executable = binary, files = depset([binary]))]

kt_native_binary = rule(
    doc = """Links a Kotlin/Native executable, `<name>.kexe`, for the konan target of the build's platform.

    Experimental. The entry point, `main`, is in the srcs or in a dep. The link dependencies of the target
    must be staged: see kotlin_native.targets(...).""",
    implementation = _kt_native_binary_impl,
    attrs = LINK_ATTRS,
    executable = True,
    toolchains = [KT_NATIVE_TOOLCHAIN_TYPE],
)
