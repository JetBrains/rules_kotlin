"""kt_native_framework: links a static Apple framework.

The srcs compile into a private klib, which the link includes in `<name>.framework` with the klibs
of the deps and exports (see link.bzl). The framework is named after the target, and so is the
prefix of its Objective-C names. Its header declares the API of the srcs and of the exports.

The framework is a directory, which rules_apple cannot import: apple_static_framework_import takes
the files of a framework. The output group framework_files copies them out of the directory.
"""

load(":link.bzl", "LINK_ATTRS", "link_native")
load(":providers.bzl", "KtKlibInfo")
load(":targets.bzl", "KONAN_TARGETS")
load(":toolchains.bzl", "KT_NATIVE_TOOLCHAIN_TYPE")
load(":transition.bzl", "kt_native_transition")

# The output group of the files of the framework: its binary, header, module map and Info.plist.
FRAMEWORK_FILES_OUTPUT_GROUP = "framework_files"

# Copies each file of the framework ($1) to its output: the arguments that follow are pairs of a
# path in the framework and an output. -L copies the files the symlinks of a macOS framework lead to.
_COPY_FRAMEWORK_FILES = """\
set -eu
framework="$1"
shift
while [ "$#" -gt 0 ]; do
  cp -L "$framework/$1" "$2"
  shift 2
done
"""

def _framework_files(ctx, tc, framework):
    """Registers the action copying the files rules_apple imports out of the framework directory.

    The files are under `_kt_native/<name>.framework/`, with the layout of an iOS framework, which
    rules_apple reads from their paths: the binary `<name>`, `Headers/<name>.h`,
    `Modules/module.modulemap` and `Info.plist`. A macOS framework has the versioned layout of a
    macOS bundle, whose Info.plist is in Resources/.

    Args:
      ctx: the context of kt_native_framework.
      tc: the Kotlin/Native toolchain of the framework.
      framework: the framework directory.

    Returns:
      The list of the copied files.
    """
    name = ctx.label.name
    plist = "Info.plist"
    if KONAN_TARGETS[tc.konan_target].apple_platform == "macos":
        plist = "Resources/Info.plist"

    args = ctx.actions.args()

    # The path of the directory itself, which path mapping maps like the outputs.
    args.add_all([framework], expand_directories = False)
    files = []
    for path, source in [
        (name, name),
        ("Headers/%s.h" % name, "Headers/%s.h" % name),
        ("Modules/module.modulemap", "Modules/module.modulemap"),
        ("Info.plist", plist),
    ]:
        output = ctx.actions.declare_file("_kt_native/%s.framework/%s" % (name, path))
        args.add(source)
        args.add(output)
        files.append(output)

    ctx.actions.run_shell(
        mnemonic = "KotlinNativeFrameworkFiles",
        progress_message = "Collecting the files of Kotlin/Native framework %{label}",
        inputs = [framework],
        outputs = files,
        command = _COPY_FRAMEWORK_FILES,
        arguments = [args],
        execution_requirements = {"supports-path-mapping": "1"},
    )
    return files

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
    return [
        DefaultInfo(files = depset([framework])),
        OutputGroupInfo(**{FRAMEWORK_FILES_OUTPUT_GROUP: depset(_framework_files(ctx, tc, framework))}),
    ]

kt_native_framework = rule(
    doc = """Links a static framework, `<name>.framework`, for the Apple konan target of the build's platform.

    Experimental. The framework is a directory, named after the target like the prefix of its Objective-C names.
    The link dependencies of the target must be staged: see kotlin_native.targets(...).

    The output group `framework_files` holds the files of the framework, copied out of the directory into
    `_kt_native/<name>.framework/` when a build requests them: the static library `<name>`, the umbrella header
    `Headers/<name>.h`, the module map `Modules/module.modulemap` and `Info.plist`. rules_apple imports a framework
    from its files, so an iOS app links the framework through a filegroup of the group, and the framework follows the
    platform of the app (`--ios_multi_cpus`):

    ```bzl
    kt_native_framework(
        name = "Shared",
        bundle_id = "org.example.Shared",
        exports = ["//shared"],
    )

    filegroup(
        name = "Shared_files",
        srcs = [":Shared"],
        output_group = "framework_files",
    )

    apple_static_framework_import(
        name = "Shared_import",
        framework_imports = [":Shared_files"],
        # What the Kotlin/Native runtime links with.
        sdk_dylibs = ["c++", "objc"],
        sdk_frameworks = ["Foundation", "UIKit"],
    )
    ```

    A swift_library then depends on `:Shared_import` and imports the module `Shared`. See examples/kmp_app.""",
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
    cfg = kt_native_transition,
    toolchains = [KT_NATIVE_TOOLCHAIN_TYPE],
)
