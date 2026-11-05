"""kt_native_framework: links a static Apple framework.

The srcs compile into a private klib, which the link includes in `<name>.framework` with the klibs
of the deps and exports (see link.bzl). The framework is named after the target, and so is the
prefix of its Objective-C names. Its header declares the API of the srcs and of the exports.
"""

load(":link.bzl", "LINK_ATTRS", "link_native")
load(":providers.bzl", "KtKlibInfo")
load(":toolchains.bzl", "KT_NATIVE_TOOLCHAIN_TYPE")

def _kt_native_framework_impl(ctx):
    tc = ctx.toolchains[KT_NATIVE_TOOLCHAIN_TYPE]
    if not tc.is_apple:
        fail(("%s: kt_native_framework builds Apple frameworks, but this target is %s; " +
              "set target_compatible_with to skip it") % (ctx.label, tc.konan_target))

    extra_args = ["-Xstatic-framework"]
    if ctx.attr.bundle_id:
        extra_args.append("-Xbinary=bundleId=" + ctx.attr.bundle_id)
    exports = [export[KtKlibInfo] for export in ctx.attr.exports]

    framework = ctx.actions.declare_directory(ctx.label.name + ".framework")
    link_native(
        ctx,
        rule_kind = "kt_native_framework",
        produce = "framework",
        output = framework,
        extra_deps = ctx.attr.exports,
        export_klibs = depset(
            [export.klib for export in exports],
            transitive = [export.exported_klibs for export in exports],
        ),
        extra_args = extra_args,
        progress_message = "Linking Kotlin/Native framework %{label} (" + tc.konan_target + ")",
    )
    return [DefaultInfo(files = depset([framework]))]

kt_native_framework = rule(
    doc = """Links a static framework, `<name>.framework`, for the Apple konan target of the build's platform.

    Experimental. The framework is a directory, named after the target like the prefix of its Objective-C names.
    The link dependencies of the target must be staged: see kotlin_native.targets(...).""",
    implementation = _kt_native_framework_impl,
    attrs = dict(LINK_ATTRS, **{
        "bundle_id": attr.string(
            doc = "The CFBundleIdentifier of the framework; by default the compiler derives one from the sources.",
        ),
        "exports": attr.label_list(
            doc = """Klibs whose API the framework exports in its header, with their own exports. They are deps of the
            framework too.""",
            providers = [KtKlibInfo],
        ),
    }),
    toolchains = [KT_NATIVE_TOOLCHAIN_TYPE],
)
