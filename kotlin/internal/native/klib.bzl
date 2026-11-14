"""The actions every Kotlin/Native rule runs: konanc, through the KonanLauncher of the toolchain.

kt_native_compile compiles sources into a klib, and kt_native_link links klibs into an executable,
a test runner or a framework, as the Kotlin Gradle plugin does: a linking rule first compiles its
own sources into a private klib (see link.bzl).

KonanLauncher (src/main/kotlin/io/bazel/kotlin/native/KonanLauncher.kt) creates the action-local
scratch directories, stages the link dependencies, replaces EXECROOT_PLACEHOLDER with the absolute
working directory of the action and runs the tool in-process, with the in-sandbox distribution as
konan.home. The actions are hermetic and reproducible:

- their inputs are only the parts of the distribution their konan target needs (the toolchain's
  compile_inputs), plus the link dependencies of the target when they link;
- konanc never downloads (airplaneMode) and writes only into the scratch directories next to its
  output, which the launcher deletes when the tool is done;
- the paths konanc records (of the sources in a klib, in debug info) are relative to the execroot.

The arguments go through a params file, and every path into the output tree in them comes from a
File, so the actions support path mapping (--experimental_output_paths=strip).
"""

load("//kotlin/internal/utils:utils.bzl", "utils")
load("//src/main/starlark/core/plugin:providers.bzl", "KtCompilerPluginInfo")
load(":providers.bzl", "KtKlibInfo")
load(":toolchains.bzl", "KT_NATIVE_TOOLCHAIN_TYPE")

# KonanLauncher replaces it with the absolute working directory of the action, as konanc sees it.
EXECROOT_PLACEHOLDER = "__EXECROOT__"

# The scratch directories, named after the output, so they are unique per target and configuration
# and follow the output under path mapping.
_DATA_DIR = "%s.konan_data"
_AUTO_CACHE_DIR = "%s.konan_cache"

_ENV = {
    # As the distribution's bin/run_konan sets it (the in-process compiler also sets it itself).
    "LIBCLANG_DISABLE_CRASH_RECOVERY": "1",
    # For the processes the compiler starts, e.g. xcrun; the action env is otherwise empty.
    "PATH": "/usr/bin:/bin",
}

_EXECUTION_REQUIREMENTS = {
    "supports-path-mapping": "1",
}

def native_module_name(ctx):
    """The module name of a native target: its module_name, or one derived from its label.

    The derived name follows the JVM rules, so klibs of the same name in different packages do not
    clash: konanc tells klibs apart by their unique_name, the module name.

    Args:
      ctx: the context of a rule with a module_name attribute.

    Returns:
      The module name.
    """
    return utils.derive_module_name(ctx)

def collect_klib_deps(konan_target, deps):
    """The klibs a compilation against `deps` needs: their transitive klibs.

    konanc resolves the `depends=` of a klib by name among the libraries it gets with -l only (it has
    no library search path), so a compilation gets the full transitive closure. The `depends=` of the
    klib it produces then lists that closure too, not only the direct deps.

    Args:
      konan_target: the konan target of the compilation.
      deps: targets providing KtKlibInfo, which must be Kotlin/Native klibs of `konan_target`.

    Returns:
      A depset of the klib Files.
    """
    for dep in deps:
        info = dep[KtKlibInfo]
        if info.platform != "native":
            fail("dep %s is a %s klib, not a Kotlin/Native one" % (dep.label, info.platform))
        if info.konan_target != konan_target:
            fail("dep {dep} is for target {dt}, but this target is {t}".format(
                dep = dep.label,
                dt = info.konan_target,
                t = konan_target,
            ))
    return depset(transitive = [dep[KtKlibInfo].transitive_klibs for dep in deps])

def _konanc_args(ctx, tc, *, produce, output, module_name = None, stage_link_deps = False):
    """The arguments every konanc action starts with: the launcher's own, then the common konanc ones.

    Args:
      ctx: the context of a rule using the Kotlin/Native toolchain type.
      tc: the Kotlin/Native toolchain.
      produce: the konanc output kind: library, program or framework.
      output: the File konanc produces, a directory for a framework.
      module_name: the module name, or None for none.
      stage_link_deps: whether the launcher stages the link dependencies of the konan target.

    Returns:
      The Args, to which the caller adds the arguments of its action.
    """
    args = ctx.actions.args()
    args.use_param_file("@%s", use_always = True)
    args.set_param_file_format("multiline")

    # Args.add rejects a directory, the output of a framework, but add_all takes one as it is.
    outputs = [output]

    # The launcher's own arguments.
    args.add("--tool", "konanc")
    args.add("--konan-home", tc.konan_home.path)
    args.add_all("--data-dir", outputs, format_each = _DATA_DIR, expand_directories = False)
    args.add_all("--auto-cache-dir", outputs, format_each = _AUTO_CACHE_DIR, expand_directories = False)
    if stage_link_deps:
        args.add_all([d.path for d in tc.konan_deps.dirs], before_each = "--staged-deps")
    args.add("--")

    # konanc's arguments.
    args.add("-produce", produce)
    args.add("-target", tc.konan_target)
    if module_name:
        args.add("-module-name", module_name)
    args.add_all(outputs, format_each = "-Xkonan-data-dir=" + _DATA_DIR, expand_directories = False)
    args.add_all(outputs, format_each = "-Xauto-cache-dir=" + _AUTO_CACHE_DIR, expand_directories = False)

    # A dependency konanc would download fails with its own message, not a network error.
    args.add("-Xoverride-konan-properties=airplaneMode=true")

    # Paths relative to the execroot, independent of the checkout location and the sandbox.
    args.add("-Xklib-relative-path-base=" + EXECROOT_PLACEHOLDER)
    args.add("-Xdebug-prefix-map=%s=." % EXECROOT_PLACEHOLDER)
    return args

def _run_konanc(ctx, tc, *, args, inputs, output, mnemonic, progress_message):
    """Registers the konanc action of `args`, which the KonanLauncher of the toolchain runs."""
    ctx.actions.run(
        executable = tc.launcher,
        arguments = [args],
        inputs = inputs,
        outputs = [output],
        env = dict(_ENV, **tc.action_env),
        execution_requirements = dict(_EXECUTION_REQUIREMENTS, **tc.execution_requirements),
        mnemonic = mnemonic,
        progress_message = progress_message,
        toolchain = KT_NATIVE_TOOLCHAIN_TYPE,
    )

def kt_native_compile(
        ctx,
        *,
        output,
        srcs,
        klib_deps,
        module_name,
        progress_message,
        plugins = [],
        opts = [],
        friends = [],
        fragments = None):
    """Registers the action compiling `srcs` into a klib with konanc, for the konan target of the toolchain.

    Args:
      ctx: the context of a rule using the Kotlin/Native toolchain type.
      output: the klib File konanc produces.
      srcs: the Kotlin source Files.
      klib_deps: a depset of the klibs to compile against (see collect_klib_deps).
      module_name: the module name, the unique_name of the klib.
      progress_message: the progress message of the action.
      plugins: targets providing KtCompilerPluginInfo. The plugins of the compile phase run, from
        their embeddable classpath (Kotlin/Native has no kapt stub phase).
      opts: more konanc options, after the ones of the rules.
      friends: klib Files of `klib_deps` whose internal declarations the sources see. konanc
        matches them by the path of their -l argument, so they must be Files of `klib_deps`.
      fragments: the K2 fragments of a multiplatform compilation, from collect_fragments of
        //kotlin/internal/kmp:fragments.bzl, or None. The sources of the fragments, `srcs` among
        them, compile instead of `srcs`, with the fragment flags.
    """
    tc = ctx.toolchains[KT_NATIVE_TOOLCHAIN_TYPE]
    compile_plugins = [
        plugin
        for plugin in [target[KtCompilerPluginInfo] for target in plugins]
        if plugin.compile
    ]
    plugin_jars = depset(transitive = [plugin.embeddable_classpath for plugin in compile_plugins])

    args = _konanc_args(ctx, tc, produce = "library", output = output, module_name = module_name)
    if fragments:
        srcs = fragments.srcs
        fragments.add_args(args)
    args.add_all(plugin_jars, format_each = "-Xplugin=%s")
    for plugin in compile_plugins:
        for option in plugin.options:
            args.add("-P", "plugin:%s:%s=%s" % (plugin.id, option.key, option.value))
    args.add_all(klib_deps, before_each = "-l")
    args.add_joined("-friend-modules", friends, join_with = ":")
    args.add_all(opts)
    args.add("-o", output)
    args.add_all(srcs)

    _run_konanc(
        ctx,
        tc,
        args = args,
        inputs = depset(srcs, transitive = [klib_deps, plugin_jars, tc.compile_inputs]),
        output = output,
        mnemonic = "KotlinNativeKlibCompile",
        progress_message = progress_message,
    )

def kt_native_link(
        ctx,
        *,
        produce,
        output,
        klib_deps,
        progress_message,
        main_klib = None,
        export_klibs = depset(),
        extra_args = [],
        opts = []):
    """Registers the action linking klibs with konanc, for the konan target of the toolchain.

    The action stages the link dependencies of the target, which the toolchain must stage (see
    KonanDepsInfo.staged). It passes no module name: a framework is named after its output.

    Args:
      ctx: the context of a rule using the Kotlin/Native toolchain type.
      produce: the konanc output kind: program or framework.
      output: the File konanc produces: an executable, or the directory of a framework.
      klib_deps: a depset of the klibs to link (see collect_klib_deps), without `main_klib`.
      progress_message: the progress message of the action.
      main_klib: the klib File whose content the output includes, like the sources of a one-step
        link (the entry point, the tests of a test runner); None to link `klib_deps` only.
      export_klibs: a depset of klib Files of `klib_deps` a framework exports. konanc matches
        them by the path of their -l argument, so they must be Files of `klib_deps`.
      extra_args: the konanc options of the rule, e.g. -generate-test-runner.
      opts: more konanc options, after the ones of the rules.
    """
    tc = ctx.toolchains[KT_NATIVE_TOOLCHAIN_TYPE]

    args = _konanc_args(ctx, tc, produce = produce, output = output, stage_link_deps = True)

    # An Apple link would otherwise also write <output>.dSYM, which is not an output of the action.
    args.add("-Xadd-light-debug=disable")
    args.add_all(extra_args)

    # konanc needs the included klib as an absolute path, and not also with -l: it would see two
    # libraries of the same unique_name.
    if main_klib:
        args.add(main_klib, format = "-Xinclude=" + EXECROOT_PLACEHOLDER + "/%s")
    args.add_all(klib_deps, before_each = "-l")
    args.add_all(export_klibs, format_each = "-Xexport-library=%s")
    args.add_all(opts)
    args.add_all("-o", [output], expand_directories = False)

    _run_konanc(
        ctx,
        tc,
        args = args,
        inputs = depset(
            [main_klib] if main_klib else [],
            transitive = [klib_deps, tc.compile_inputs, tc.konan_deps.files],
        ),
        output = output,
        mnemonic = "KotlinNativeLink",
        progress_message = progress_message,
    )
