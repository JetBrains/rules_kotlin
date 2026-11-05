"""The Kotlin/Native toolchain: one registered toolchain per (exec host, konan target).

Mirrors define_kt_toolchain (kotlin/internal/toolchains.bzl) but carries the konan
distribution + target string instead of the JVM compiler. A host distribution compiles
klibs for every target the host builds for, so all of a host's toolchains share its
`konan_home`, `konan` and `stdlib`, and differ in `konan_target`, its platform libraries,
its link dependencies and `target_compatible_with`.

Every toolchain also carries the KonanLauncher binary its actions run (see klib.bzl), the konan
target of its exec host, whose binaries a test can run there, and, for an Apple target, the
environment and execution requirements of an action using Xcode.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//rules/directory:providers.bzl", "DirectoryInfo")
load("@build_bazel_apple_support//lib:apple_support.bzl", "apple_support")
load("@build_bazel_apple_support//xcode:providers.bzl", "XcodeVersionInfo")
load(":targets.bzl", "EXEC_HOSTS", "KONAN_TARGETS")

KT_NATIVE_TOOLCHAIN_TYPE = Label("//kotlin/internal/native:kt_native_toolchain_type")

KonanDepsInfo = provider(
    doc = "The link dependencies of a konan target on an exec host: a view of a link bundle repository.",
    fields = {
        "dirs": "(list[DirectoryInfo]) The dependency directories, in the order of `names`.",
        "files": "(depset[File]) Every file of the dependency directories.",
        "konan_target": "(str) The konan target the dependencies link for.",
        "names": "(list[str]) The names konanc looks the dependencies up by in KONAN_DATA_DIR/dependencies.",
        "staged": "(bool) Whether the bundle stages the target; nothing links for it otherwise.",
    },
)

def _kt_native_deps_view_impl(ctx):
    dirs = [dep[DirectoryInfo] for dep in ctx.attr.deps]
    if dirs and not ctx.attr.staged:
        fail("an unstaged view has no dependencies, but %s lists %s" % (ctx.label, ctx.attr.deps))
    return [KonanDepsInfo(
        dirs = dirs,
        files = depset(transitive = [d.transitive_files for d in dirs]),
        konan_target = ctx.attr.konan_target,
        names = [d.path.rpartition("/")[2] for d in dirs],
        staged = ctx.attr.staged,
    )]

kt_native_deps_view = rule(
    doc = "The link dependencies of one konan target, out of a Kotlin/Native link bundle repository.",
    implementation = _kt_native_deps_view_impl,
    attrs = {
        "deps": attr.label_list(
            doc = "the dependency directories (subdirectory targets of the bundle)",
            providers = [DirectoryInfo],
        ),
        "konan_target": attr.string(
            doc = "the konan target the dependencies link for",
            mandatory = True,
            values = sorted(KONAN_TARGETS.keys()),
        ),
        "staged": attr.bool(
            doc = "False for a target left out of kotlin_native.targets(...), which has no dependencies",
            default = True,
        ),
    },
    provides = [KonanDepsInfo],
)

def _kt_native_toolchain_impl(ctx):
    konan_target = ctx.attr.konan_target
    konan_home = ctx.attr.konan_home[DirectoryInfo]
    konan = ctx.attr.konan[DirectoryInfo]
    stdlib = ctx.attr.stdlib[DirectoryInfo]
    platform_libs = ctx.attr.platform_libs[DirectoryInfo]
    konan_deps = ctx.attr.konan_deps[KonanDepsInfo]

    # konanc gets konan_home as -Dkonan.home and only the other trees as inputs, so they must
    # be where it looks for them under konan_home.
    for attr_name, tree, relative in [
        ("konan", konan, "konan"),
        ("stdlib", stdlib, "klib/common/stdlib"),
        ("platform_libs", platform_libs, "klib/platform/" + konan_target),
    ]:
        if tree.path != konan_home.path + "/" + relative:
            fail("%s must be %s/%s, not %s" % (attr_name, konan_home.path, relative, tree.path))
    if konan_deps.konan_target != konan_target:
        fail("konan_deps link for %s, but the toolchain is for %s" % (konan_deps.konan_target, konan_target))

    # What apple_support.run adds to an action (DEVELOPER_DIR and SDKROOT of the selected Xcode,
    # darwin and Xcode execution requirements), with the SDK of the konan target rather than of the
    # --apple_platform_type the apple configuration fragment reads.
    target = KONAN_TARGETS[konan_target]
    action_env = {}
    execution_requirements = {}
    if target.is_apple:
        xcode_config = ctx.attr._xcode_config[XcodeVersionInfo]
        action_env.update(apple_common.apple_host_system_env(xcode_config))
        action_env.update(apple_common.target_apple_env(
            xcode_config,
            getattr(apple_common.platform, target.apple_platform),
        ))
        execution_requirements["requires-darwin"] = ""
        execution_requirements.update(xcode_config.execution_info())

    return [platform_common.ToolchainInfo(
        action_env = action_env,
        compile_inputs = depset(transitive = [
            konan.transitive_files,
            stdlib.transitive_files,
            platform_libs.transitive_files,
        ]),
        execution_requirements = execution_requirements,
        is_apple = target.is_apple,
        konan = konan,
        konan_deps = konan_deps,
        konan_home = konan_home,
        konan_host = ctx.attr.konan_host,
        konan_target = konan_target,
        launcher = ctx.attr.launcher[DefaultInfo].files_to_run,
        platform_libs = platform_libs,
        stdlib = stdlib,
    )]

_kt_native_toolchain = rule(
    doc = "A Kotlin/Native toolchain. Use define_kt_native_toolchain, not this directly.",
    implementation = _kt_native_toolchain_impl,
    attrs = dicts.add({
        "konan": attr.label(
            doc = "konan/ of the distribution: the compiler and konan.properties",
            mandatory = True,
            providers = [DirectoryInfo],
        ),
        "konan_deps": attr.label(
            doc = "the link dependencies of konan_target (a kt_native_deps_view)",
            mandatory = True,
            providers = [KonanDepsInfo],
        ),
        "konan_home": attr.label(
            doc = "the distribution root, which konanc gets as -Dkonan.home",
            mandatory = True,
            providers = [DirectoryInfo],
        ),
        "konan_host": attr.string(
            doc = "the konan target of the exec host, whose binaries run there (e.g. linux_x64)",
            mandatory = True,
            values = sorted(KONAN_TARGETS.keys()),
        ),
        "konan_target": attr.string(
            doc = "the konan target this toolchain compiles for (e.g. macos_arm64)",
            mandatory = True,
            values = sorted(KONAN_TARGETS.keys()),
        ),
        "launcher": attr.label(
            doc = "the KonanLauncher binary, which runs the tools of the distribution in every action",
            default = Label("//src/main/kotlin:konan_launcher"),
            executable = True,
            cfg = "exec",
        ),
        "platform_libs": attr.label(
            doc = "klib/platform/<konan_target> of the distribution",
            mandatory = True,
            providers = [DirectoryInfo],
        ),
        "stdlib": attr.label(
            doc = "klib/common/stdlib of the distribution",
            mandatory = True,
            providers = [DirectoryInfo],
        ),
    }, apple_support.action_required_attrs()),
    fragments = ["apple"],
    provides = [platform_common.ToolchainInfo],
)

def define_kt_native_toolchain(
        name,
        konan_target,
        konan_host,
        konan_home,
        konan,
        stdlib,
        platform_libs,
        konan_deps,
        exec_compatible_with,
        target_compatible_with,
        visibility = ["//visibility:public"]):
    """Defines a native toolchain impl + its registration (one per (exec, target)).

    The impl is tagged manual: the toolchain refers to it without analyzing it, so wildcard
    builds such as //... do not fetch the distribution and link bundle repositories.

    Args:
      name: the name of the toolchain; the impl is <name>_impl.
      konan_target: the konan target the toolchain compiles for.
      konan_host: the konan target of the exec host (EXEC_HOSTS[...].konan_host).
      konan_home: the DirectoryInfo of the distribution root.
      konan: the DirectoryInfo of konan/ under konan_home.
      stdlib: the DirectoryInfo of klib/common/stdlib under konan_home.
      platform_libs: the DirectoryInfo of klib/platform/<konan_target> under konan_home.
      konan_deps: the kt_native_deps_view of konan_target.
      exec_compatible_with: the constraints of the exec host.
      target_compatible_with: the constraints of konan_target.
      visibility: the visibility of the toolchain and its impl.
    """
    impl_name = name + "_impl"
    _kt_native_toolchain(
        name = impl_name,
        konan_target = konan_target,
        konan_host = konan_host,
        konan_home = konan_home,
        konan = konan,
        stdlib = stdlib,
        platform_libs = platform_libs,
        konan_deps = konan_deps,
        tags = ["manual"],
        visibility = visibility,
    )
    native.toolchain(
        name = name,
        toolchain_type = KT_NATIVE_TOOLCHAIN_TYPE,
        toolchain = ":" + impl_name,
        exec_compatible_with = exec_compatible_with,
        target_compatible_with = target_compatible_with,
        visibility = visibility,
    )

# buildifier: disable=unnamed-macro
def define_kt_native_toolchains():
    """Defines a toolchain per exec host of EXEC_HOSTS and konan target the host builds for.

    Each is named <host repo suffix>_<target>, e.g. macos_aarch64_ios_simulator_arm64, and uses
    the distribution and link bundle repositories the kotlin_native module extension
    (src/main/starlark/core/repositories/native.bzl) creates for its host.
    """
    for host in EXEC_HOSTS.values():
        dist = "@com_github_jetbrains_kotlin_native_%s//" % host.repo_suffix
        deps = "@com_github_jetbrains_kotlin_native_deps_%s//" % host.repo_suffix
        for target in host.targets:
            define_kt_native_toolchain(
                name = "%s_%s" % (host.repo_suffix, target),
                konan_target = target,
                konan_host = host.konan_host,
                konan_home = dist + ":home",
                konan = dist + ":konan",
                stdlib = dist + ":stdlib",
                platform_libs = dist + ":platform_" + target,
                konan_deps = deps + ":" + target,
                exec_compatible_with = host.constraints,
                target_compatible_with = KONAN_TARGETS[target].constraints,
            )
