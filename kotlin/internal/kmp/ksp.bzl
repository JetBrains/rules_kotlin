"""KSP2 for Kotlin Multiplatform: a separate action runs the KSP command-line tool and declares its generated files.

The KSP compiler plugin that kt_jvm_library and kt_android_library run (`plugins = [kt_ksp_plugin]`) is not
available to the libraries of a kt_multiplatform_library, which have `kmp_fragments`, and Kotlin/Native has no
such plugin: both compile sources as the K2 fragments of one module, whose inputs a plugin of the compiler does
not see across fragments. These rules run the KSP command-line tool of the KSP release the toolchain pins
instead, as the Kotlin Gradle plugin does for a multiplatform module: `KSPJvmMain` for the JVM and Android,
`KSPNativeMain` for a konan target.

The output contract is a list of plain Kotlin files, never a srcjar or a directory: a library with
`kmp_fragments` compiles the files of its `srcs` as the leaf fragment, and a Kotlin/Native fragment needs
concrete source paths. KSP processes the sources of the platform before the common ones (see
_source_roots). See docs/kmp.md for usage.
"""

load("@rules_java//java:defs.bzl", "JavaInfo", "java_common")
load("//kotlin/internal:defs.bzl", "TOOLCHAIN_TYPE")
load("//kotlin/internal/native:klib.bzl", "collect_klib_deps")
load("//kotlin/internal/native:providers.bzl", "KtKlibInfo")
load("//kotlin/internal/native:toolchains.bzl", "KT_NATIVE_TOOLCHAIN_TYPE")
load("//kotlin/internal/native:transition.bzl", "TRANSITION_ATTRS", "kt_native_transition")
load("//src/main/starlark/core/plugin:providers.bzl", "KspPluginInfo")

_ANDROID_SDK_TOOLCHAIN_TYPE = Label("@rules_android//toolchains/android_sdk:toolchain_type")

# The work directory of the action stands for a temporary directory the script creates.
_WORK = "__KSP_WORK__"

def _check_option(ctx, key, value, owner):
    """Fails on an option the KSP command line cannot carry.

    The tool splits `-processor-options` at every `:` and an option at every `=`, of which it keeps
    the first two parts, with no escape: it would cut the value short, or read its rest as another
    option. The params file of the action holds one argument per line.
    """
    for part, text in [("key", key), ("value", value)]:
        for separator in [":", "=", "\n"]:
            if separator in text:
                fail(("%s: the KSP option '%s' of %s has %s in its %s: the KSP command-line tool separates options " +
                      "with ':' and a key from its value with '=', without an escape; pass a key and a value " +
                      "without ':', '=' and line breaks") % (ctx.label, key, owner, repr(separator), part))

def _processors(ctx):
    classpath = depset(transitive = [processor[DefaultInfo].files for processor in ctx.attr.processors])
    options = {}
    for processor in ctx.attr.processors:
        for key, value in processor[KspPluginInfo].options.items():
            _check_option(ctx, key, value, "the processor %s" % processor.label)
            if key in options and options[key] != value:
                fail("%s: conflicting KSP option '%s' of the processors" % (ctx.label, key))
            options[key] = value
    for key, value in ctx.attr.processor_options.items():
        _check_option(ctx, key, value, "processor_options")
        options[key] = value
    return struct(classpath = classpath, options = options)

def _declare_outputs(ctx):
    seen = {}
    outputs = []
    for rel in ctx.attr.generated:
        if not rel.endswith(".kt") or rel.startswith("/") or ".." in rel.split("/"):
            fail("%s: generated '%s' must be a relative path of a .kt file" % (ctx.label, rel))
        if rel in seen:
            fail("%s: generated lists '%s' twice" % (ctx.label, rel))
        seen[rel] = True
        outputs.append(struct(rel = rel, file = ctx.actions.declare_file("%s/%s" % (ctx.label.name, rel))))
    if not outputs:
        fail("%s: generated lists no file: declare the files the processors generate" % ctx.label)
    return outputs

def _tool_classpath(ctx):
    return depset(transitive = [dep[JavaInfo].transitive_runtime_jars for dep in ctx.attr._ksp])

def _source_roots(ctx):
    """The sources in the order of the KSP Gradle plugin for a platform compilation: the platform's, then the common ones.

    The Gradle plugin lists the source sets of the compilation from its default source set (the platform's)
    to the ones it depends on (the common ones), with no common source roots. KSP2 puts them all in one
    module, without the multiplatform mode of the compiler, so a type with an `expect` declaration in the
    common sources and an `actual` one in the platform sources is the declaration KSP sees first: the
    actual, as in the compilation of the platform, only in this order.
    """
    common = {src: True for src in ctx.files.common_srcs}
    return [src for src in ctx.files.srcs if src not in common] + ctx.files.common_srcs

def _run(ctx, *, main_class, ksp_args, libraries, extra_inputs, language_version, api_version, stdlib = None, platform_libs = None, mnemonic):
    """Registers the action running a KSP command-line tool; returns the DefaultInfo of the generated files."""
    java_runtime = ctx.attr._host_java_runtime[java_common.JavaRuntimeInfo]
    processors = _processors(ctx)
    outputs = _declare_outputs(ctx)
    tool_classpath = _tool_classpath(ctx)

    params = ctx.actions.args()
    params.use_param_file("%s", use_always = True)
    params.set_param_file_format("multiline")
    params.add("-Xmx2g")
    params.add_joined("-cp", tool_classpath, join_with = ":")
    params.add(main_class)
    params.add("-module-name=" + ctx.attr.module_name if ctx.attr.module_name else "-module-name=" + ctx.label.name)
    params.add_joined(_source_roots(ctx), join_with = ":", format_joined = "-source-roots=%s")
    params.add_joined(libraries, join_with = ":", format_joined = "-libraries=%s", omit_if_empty = False)
    if processors.options:
        params.add("-processor-options=" + ":".join(["%s=%s" % item for item in sorted(processors.options.items())]))
    params.add("-project-base-dir=" + _WORK + "/base")
    params.add("-output-base-dir=" + _WORK + "/base")
    params.add("-caches-dir=" + _WORK + "/caches")
    params.add("-class-output-dir=" + _WORK + "/class")
    params.add("-kotlin-output-dir=" + _WORK + "/kotlin")
    params.add("-resource-output-dir=" + _WORK + "/resource")
    params.add("-incremental=false")
    params.add("-language-version=" + (ctx.attr.language_version or language_version))
    params.add("-api-version=" + (ctx.attr.api_version or api_version))
    params.add_all(ksp_args)
    params.add_joined(processors.classpath, join_with = ":", omit_if_empty = False)

    out_args = ctx.actions.args()
    out_args.use_param_file("%s", use_always = True)
    out_args.set_param_file_format("multiline")
    for output in outputs:
        out_args.add(output.rel)
        out_args.add(output.file)

    arguments = [java_runtime.java_executable_exec_path, params, out_args]
    if platform_libs:
        arguments.extend([stdlib, platform_libs])

    ctx.actions.run(
        executable = ctx.executable._script,
        arguments = arguments,
        inputs = depset(
            ctx.files.srcs + ctx.files.common_srcs,
            transitive = [
                tool_classpath,
                processors.classpath,
                java_runtime.files,
                libraries,
                extra_inputs,
            ],
        ),
        outputs = [output.file for output in outputs],
        mnemonic = mnemonic,
        progress_message = "Running KSP %{label}",
        toolchain = None,
        use_default_shell_env = True,
    )
    return [DefaultInfo(files = depset([output.file for output in outputs]))]

def _kt_jvm_ksp_sources_impl(ctx):
    kotlin = ctx.toolchains[TOOLCHAIN_TYPE]
    compile_jars = [dep[JavaInfo].transitive_compile_time_jars for dep in ctx.attr.deps]
    stdlib = [dep[JavaInfo].transitive_compile_time_jars for dep in ctx.attr._stdlib]
    android_jars = []
    android_sdk = ctx.toolchains[_ANDROID_SDK_TOOLCHAIN_TYPE]
    if ctx.attr.android:
        if not android_sdk:
            fail("%s: android = True needs a registered Android SDK toolchain" % ctx.label)
        android_jars = [android_sdk.android_sdk_info.android_jar]
    libraries = depset(android_jars, transitive = compile_jars + stdlib)
    return _run(
        ctx,
        main_class = "com.google.devtools.ksp.cmdline.KSPJvmMain",
        ksp_args = [
            "-jvm-target=" + (ctx.attr.jvm_target or kotlin.jvm_target),
            "-java-output-dir=" + _WORK + "/java",
        ],
        libraries = libraries,
        extra_inputs = depset(),
        language_version = kotlin.language_version,
        api_version = kotlin.api_version,
        mnemonic = "KspJvm",
    )

_COMMON_ATTRS = {
    "api_version": attr.string(
        doc = "The `-api-version` of KSP; by default the one of the Kotlin toolchain.",
    ),
    "common_srcs": attr.label_list(
        doc = """The Kotlin sources the platform shares with other platforms, a subset of `srcs`. KSP processes them after
        the sources of the platform alone, as the KSP Gradle plugin orders the source sets of a platform compilation: a
        type with an `expect` declaration in the common sources and an `actual` one in the platform sources resolves to
        the actual, with its constructors and members, as it does in the compilation of the platform.""",
        allow_files = [".kt"],
    ),
    "generated": attr.string_list(
        doc = """The Kotlin files the processors generate, relative to the output root of KSP: the directory of the
        package and the file name, e.g. `com/example/InjectAppComponent.kt`. The files are outputs of the target,
        under a directory of its name, to list in the `srcs` of the platform library. The action fails on a file the
        processors write that is not listed, and on one listed that they do not write.""",
        mandatory = True,
    ),
    "language_version": attr.string(
        doc = "The `-language-version` of KSP; by default the one of the Kotlin toolchain.",
    ),
    "module_name": attr.string(
        doc = "The module name KSP is given; by default the name of the target.",
    ),
    "processor_options": attr.string_dict(
        doc = """More KSP options, as `ksp.arg` of Gradle, on top of those of the `processors`. A key or a value with
        `:`, `=` or a line break fails the analysis: the KSP command line has no escape for them.""",
    ),
    "processors": attr.label_list(
        doc = "The KSP processors, as kt_ksp_plugin targets: their runtime classpath is the one KSP loads them from, and their options are passed on.",
        providers = [KspPluginInfo],
        cfg = "exec",
    ),
    "srcs": attr.label_list(
        doc = "The Kotlin sources KSP processes: every source the platform compiles, those it shares and its own.",
        allow_files = [".kt"],
        mandatory = True,
    ),
    # The JDK of the exec platform runs KSP, as the one of the Kotlin compiler: the java runtime toolchain
    # type resolves for the target platform, which a konan target is not.
    "_host_java_runtime": attr.label(
        default = Label("@bazel_tools//tools/jdk:current_host_java_runtime"),
        cfg = "exec",
        providers = [java_common.JavaRuntimeInfo],
    ),
    "_ksp": attr.label_list(
        default = [
            Label("//kotlin/compiler:symbol-processing-aa"),
            Label("//kotlin/compiler:symbol-processing-common-deps"),
            Label("//kotlin/compiler:symbol-processing-api"),
            Label("//kotlin/compiler:ksp-intellij-kotlinx-coroutines-core-jvm"),
            Label("//kotlin/compiler:kotlin-stdlib"),
        ],
        providers = [JavaInfo],
        cfg = "exec",
    ),
    "_script": attr.label(
        default = Label("//kotlin/internal/kmp:ksp_run"),
        cfg = "exec",
        executable = True,
    ),
}

kt_jvm_ksp_sources = rule(
    doc = """Runs KSP2 (`KSPJvmMain`) over the sources of a JVM or Android platform and declares the Kotlin files it generates.

    Experimental. See "KSP for a multiplatform library" in docs/kmp.md. Compiling the generated files: list the
    target in the `srcs_jvm` or `srcs_android` of the kt_multiplatform_library, and in no other list, so they are
    the leaf fragment of that platform.""",
    implementation = _kt_jvm_ksp_sources_impl,
    attrs = dict(_COMMON_ATTRS, **{
        "android": attr.bool(
            doc = "Whether the sources use the Android APIs: the Android SDK jar is a library of KSP (needs the Android SDK toolchain of rules_android).",
        ),
        "deps": attr.label_list(
            doc = "The libraries of the platform the sources compile against, e.g. the JVM variant of the KMP libraries: their compile jars are the libraries of KSP.",
            providers = [JavaInfo],
        ),
        "jvm_target": attr.string(
            doc = "The `-jvm-target` of KSP; by default the one of the Kotlin toolchain.",
        ),
        "_stdlib": attr.label_list(
            default = [Label("//kotlin/compiler:kotlin-stdlib")],
            providers = [JavaInfo],
        ),
    }),
    toolchains = [
        TOOLCHAIN_TYPE,
        config_common.toolchain_type(_ANDROID_SDK_TOOLCHAIN_TYPE, mandatory = False),
    ],
)

def _kt_native_ksp_sources_impl(ctx):
    tc = ctx.toolchains[KT_NATIVE_TOOLCHAIN_TYPE]
    kotlin = ctx.toolchains[TOOLCHAIN_TYPE]
    klibs = collect_klib_deps(tc.konan_target, ctx.attr.deps)
    stdlib = tc.stdlib
    platform_libs = tc.platform_libs
    libraries = depset([], transitive = [klibs])
    return _run(
        ctx,
        main_class = "com.google.devtools.ksp.cmdline.KSPNativeMain",
        ksp_args = ["-target=" + tc.konan_target],
        libraries = libraries,
        extra_inputs = depset(transitive = [stdlib.transitive_files, platform_libs.transitive_files]),
        language_version = kotlin.language_version,
        api_version = kotlin.api_version,
        stdlib = stdlib.path,
        platform_libs = platform_libs.path,
        mnemonic = "KspNative",
    )

kt_native_ksp_sources = rule(
    doc = """Runs KSP2 (`KSPNativeMain`) over the sources of a konan target and declares the Kotlin files it generates.

    Experimental. See "KSP for a multiplatform library" in docs/kmp.md. The target is for the konan target of the
    build's platform, like kt_native_library: its `deps` are klibs of that target, which KSP resolves symbols
    against, with the standard library and platform libraries of the distribution. List it in the `srcs` of the
    kt_native_library of the platform, or in the srcs of the group or the platform of a kt_multiplatform_library
    whose konan targets compile them, e.g. its `srcs_apple` for the Apple targets.""",
    implementation = _kt_native_ksp_sources_impl,
    attrs = dict(_COMMON_ATTRS, **dict(TRANSITION_ATTRS, **{
        "deps": attr.label_list(
            doc = "The klibs of the konan target the sources compile against: their transitive klibs are the libraries of KSP.",
            providers = [KtKlibInfo],
        ),
    })),
    cfg = kt_native_transition,
    toolchains = [
        KT_NATIVE_TOOLCHAIN_TYPE,
        TOOLCHAIN_TYPE,
    ],
)
