"""The action every Kotlin/Native rule runs: konanc, through the KonanLauncher of the toolchain.

KonanLauncher (src/main/kotlin/io/bazel/kotlin/native/KonanLauncher.kt) creates the action-local
scratch directories, stages the link dependencies, replaces EXECROOT_PLACEHOLDER with the absolute
working directory of the action and runs the tool in-process, with the in-sandbox distribution as
konan.home. The action is hermetic and reproducible:

- its inputs are only the parts of the distribution its konan target needs (the toolchain's
  compile_inputs), plus the link dependencies of the target when it links;
- konanc never downloads (airplaneMode) and writes only into the scratch directories next to its
  output, which the launcher deletes when the tool is done;
- the paths konanc records (of the sources in a klib, in debug info) are relative to the execroot.

The arguments go through a params file, and every path into the output tree in them comes from a
File, so the action supports path mapping (--experimental_output_paths=strip).
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

def kt_native_compile(
        ctx,
        *,
        produce,
        output,
        srcs,
        klib_deps,
        module_name,
        mnemonic,
        progress_message,
        plugins = [],
        opts = [],
        stage_link_deps = False):
    """Registers the action compiling `srcs` with konanc for the konan target of the toolchain.

    Args:
      ctx: the context of a rule using the Kotlin/Native toolchain type.
      produce: the konanc output kind, e.g. library or program.
      output: the File konanc produces, e.g. <name>.klib.
      srcs: the Kotlin source Files.
      klib_deps: a depset of the klibs to compile against (see collect_klib_deps).
      module_name: the module name, the unique_name of a klib.
      mnemonic: the mnemonic of the action.
      progress_message: the progress message of the action.
      plugins: targets providing KtCompilerPluginInfo. The plugins of the compile phase run, from
        their embeddable classpath (Kotlin/Native has no kapt stub phase).
      opts: more konanc options, after the ones of the rules.
      stage_link_deps: whether to stage the link dependencies of the konan target, which linking
        needs; the toolchain must stage them (see KonanDepsInfo.staged).
    """
    tc = ctx.toolchains[KT_NATIVE_TOOLCHAIN_TYPE]
    compile_plugins = [
        plugin
        for plugin in [target[KtCompilerPluginInfo] for target in plugins]
        if plugin.compile
    ]
    plugin_jars = depset(transitive = [plugin.embeddable_classpath for plugin in compile_plugins])

    args = ctx.actions.args()
    args.use_param_file("@%s", use_always = True)
    args.set_param_file_format("multiline")

    # The launcher's own arguments.
    args.add("--tool", "konanc")
    args.add("--konan-home", tc.konan_home.path)
    args.add("--data-dir", output, format = _DATA_DIR)
    args.add("--auto-cache-dir", output, format = _AUTO_CACHE_DIR)
    if stage_link_deps:
        args.add_all([d.path for d in tc.konan_deps.dirs], before_each = "--staged-deps")
    args.add("--")

    # konanc's arguments.
    args.add("-produce", produce)
    args.add("-target", tc.konan_target)
    args.add("-module-name", module_name)
    args.add(output, format = "-Xkonan-data-dir=" + _DATA_DIR)
    args.add(output, format = "-Xauto-cache-dir=" + _AUTO_CACHE_DIR)

    # A dependency konanc would download fails with its own message, not a network error.
    args.add("-Xoverride-konan-properties=airplaneMode=true")

    # Paths relative to the execroot, independent of the checkout location and the sandbox.
    args.add("-Xklib-relative-path-base=" + EXECROOT_PLACEHOLDER)
    args.add("-Xdebug-prefix-map=%s=." % EXECROOT_PLACEHOLDER)

    args.add_all(plugin_jars, format_each = "-Xplugin=%s")
    for plugin in compile_plugins:
        for option in plugin.options:
            args.add("-P", "plugin:%s:%s=%s" % (plugin.id, option.key, option.value))
    args.add_all(klib_deps, before_each = "-l")
    args.add_all(opts)
    args.add("-o", output)
    args.add_all(srcs)

    ctx.actions.run(
        executable = tc.launcher,
        arguments = [args],
        inputs = depset(
            srcs,
            transitive = [klib_deps, plugin_jars, tc.compile_inputs] +
                         ([tc.konan_deps.files] if stage_link_deps else []),
        ),
        outputs = [output],
        env = dict(_ENV, **tc.action_env),
        execution_requirements = dict(_EXECUTION_REQUIREMENTS, **tc.execution_requirements),
        mnemonic = mnemonic,
        progress_message = progress_message,
        toolchain = KT_NATIVE_TOOLCHAIN_TYPE,
    )
