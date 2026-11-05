"""What the linking rules (kt_native_binary, kt_native_test, kt_native_framework) share.

They link in two actions, as the Kotlin Gradle plugin does: their srcs compile into a private klib,
_kt_native/<name>.klib, and the link includes that klib in the output with -Xinclude, next to the
klibs of the deps. A link can also use existing klibs as its main content, so a binary can take its
entry point from a dep, and a framework can consist of its exports alone.

Linking needs the link dependencies of the konan target (LLVM, libffi, the cross-toolchain), which
the `com_github_jetbrains_kotlin_native_deps_<host>` repository of each exec host stages for the
targets of kotlin_native.targets(...), so the link action runs sandboxed with no network. Apple
targets also need the SDK of the local Xcode, which konanc finds with xcrun.
"""

load("//src/main/starlark/core/plugin:providers.bzl", "KtCompilerPluginInfo")
load(":klib.bzl", "collect_klib_deps", "kt_native_compile", "kt_native_link", "native_module_name")
load(":providers.bzl", "KtKlibInfo")
load(":toolchains.bzl", "KT_NATIVE_TOOLCHAIN_TYPE")

LINK_ATTRS = {
    "deps": attr.label_list(
        doc = "The klibs to link, e.g. kt_native_library targets, which the srcs compile against. They are for the same konan target.",
        providers = [KtKlibInfo],
    ),
    "link_opts": attr.string_list(
        doc = "More konanc options of the link, e.g. `-opt`. They follow the options of the rule.",
    ),
    "module_name": attr.string(
        doc = """The Kotlin module name of the srcs, the unique_name of the klib they compile into. By default it is derived
        from the label, as for the JVM rules.""",
    ),
    "opts": attr.string_list(
        doc = "More konanc options of the compilation of the srcs, e.g. `-opt-in=kotlin.ExperimentalStdlibApi`.",
    ),
    "plugins": attr.label_list(
        doc = """Kotlin compiler plugins (kt_compiler_plugin) to run during the compilation of the srcs. The Kotlin/Native
        compiler loads them in the embeddable compiler dialect.""",
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
}

def link_native(
        ctx,
        *,
        rule_kind,
        produce,
        output,
        progress_message,
        extra_deps = [],
        friends = [],
        export_klibs = depset(),
        extra_args = []):
    """Registers the actions of a linking rule: the compilation of its srcs, if any, and the link.

    Args:
      ctx: the context of a rule with LINK_ATTRS, using the Kotlin/Native toolchain type.
      rule_kind: the name of the rule, for the error messages.
      produce: the konanc output kind of the link: program or framework.
      output: the File the link produces: an executable, or the directory of a framework.
      progress_message: the progress message of the link.
      extra_deps: more targets providing KtKlibInfo that the srcs compile against and the link
        links, e.g. the exports of a framework.
      friends: klib Files of the deps whose internal declarations the srcs see.
      export_klibs: a depset of klib Files of the deps that a framework exports.
      extra_args: the konanc options of the rule for the link.

    Returns:
      The private klib the srcs compile into, or None when the rule has no srcs.
    """
    if ctx.attr.source_sets:
        fail("%s: source_sets are reserved for Kotlin Multiplatform source sets, which %s does not support yet" %
             (ctx.label, rule_kind))
    tc = ctx.toolchains[KT_NATIVE_TOOLCHAIN_TYPE]
    if not tc.konan_deps.staged:
        fail(("%s: the Kotlin/Native link dependencies of %s are not staged, so nothing links for it; " +
              "add '%s' to kotlin_native.targets(...) in the root MODULE.bazel") %
             (ctx.label, tc.konan_target, tc.konan_target))

    klib_deps = collect_klib_deps(tc.konan_target, ctx.attr.deps + extra_deps)
    main_klib = None
    if ctx.files.srcs:
        main_klib = ctx.actions.declare_file("_kt_native/%s.klib" % ctx.label.name)
        kt_native_compile(
            ctx,
            output = main_klib,
            srcs = ctx.files.srcs,
            klib_deps = klib_deps,
            module_name = native_module_name(ctx),
            plugins = ctx.attr.plugins,
            opts = ctx.attr.opts,
            friends = friends,
            progress_message = "Compiling Kotlin/Native sources of %{label} (" + tc.konan_target + ")",
        )
    kt_native_link(
        ctx,
        produce = produce,
        output = output,
        klib_deps = klib_deps,
        main_klib = main_klib,
        export_klibs = export_klibs,
        extra_args = extra_args,
        opts = ctx.attr.link_opts,
        progress_message = progress_message,
    )
    return main_klib
