"""Module extension that provisions the Kotlin/Native prebuilt distributions and link bundles.

For every exec host of EXEC_HOSTS (kotlin/internal/native/targets.bzl), whatever the OS of the
client, it creates:
- `com_github_jetbrains_kotlin_native_<host>`, the prebuilt distribution of the host, which
  compiles klibs for every target the host builds for;
- `com_github_jetbrains_kotlin_native_deps_<host>`, the LLVM/libffi/lldb/cross-toolchain bundle
  kt_native_binary links with, for the targets of `kotlin_native.targets(...)`, with a view per
  target of the host.

Repositories are only fetched when a native target is built, so JVM-only builds download none.
"""

# buildifier: disable=bzl-visibility
load("//kotlin/internal/native:targets.bzl", "EXEC_HOSTS")
load(
    ":native_compiler.bzl",
    "collect_kotlin_native_config",
    "kotlin_native_bundle",
    "kotlin_native_compiler_repository",
    "kotlin_native_deps_repository",
    "kotlin_native_distribution",
)

KOTLIN_NATIVE_REPO = "com_github_jetbrains_kotlin_native_"
KOTLIN_NATIVE_DEPS_REPO = "com_github_jetbrains_kotlin_native_deps_"

def _kotlin_native_impl(module_ctx):
    config = collect_kotlin_native_config(module_ctx.modules)
    for host_key, host in EXEC_HOSTS.items():
        dist = kotlin_native_distribution(host_key, config.version, config.sha256[host_key])
        dist_repo = KOTLIN_NATIVE_REPO + host.repo_suffix
        kotlin_native_compiler_repository(
            name = dist_repo,
            urls = dist.urls,
            sha256 = dist.sha256,
            strip_prefix = dist.strip_prefix,
            konan_targets = host.targets,
        )

        # Pre-staged LLVM/libffi/lldb/cross-toolchain bundle for binary linking (kt_native_binary).
        bundle = kotlin_native_bundle(host_key, config.targets, config.version)
        kotlin_native_deps_repository(
            name = KOTLIN_NATIVE_DEPS_REPO + host.repo_suffix,
            archives = bundle.archives,
            views = bundle.views,
            unstaged_targets = bundle.unstaged,
            konan_host = host.konan_host,
            konan_properties = "@%s//:konan/konan.properties" % dist_repo,
            version = config.version,
        )

    return module_ctx.extension_metadata(reproducible = True)

_version_tag = tag_class(
    doc = "The Kotlin/Native release to use instead of the one rules_kotlin pins. Only the root " +
          "module may declare it. The link dependencies rules_kotlin pins, with the LLVM of the " +
          "release (KOTLIN_NATIVE_LLVM in native_compiler.bzl), are checked against the release " +
          "when they are fetched.",
    attrs = {
        "sha256": attr.string_dict(
            doc = "The sha256 of the kotlin-native-prebuilt archive per exec host (linux-x86_64, " +
                  "macos-aarch64). An archive without one downloads unverified.",
        ),
        "version": attr.string(mandatory = True, doc = "The Kotlin/Native release, e.g. 2.4.21."),
    },
)

_targets_tag = tag_class(
    doc = "The konan targets to stage link dependencies for; all of them by default. Only the " +
          "root module may declare it. klibs compile for every target regardless, but " +
          "kt_native_binary only links for these.",
    attrs = {
        "targets": attr.string_list(
            mandatory = True,
            doc = "Konan targets of //kotlin/native/platforms, e.g. [\"linux_x64\", \"macos_arm64\"].",
        ),
    },
)

kotlin_native = module_extension(
    implementation = _kotlin_native_impl,
    tag_classes = {
        "targets": _targets_tag,
        "version": _version_tag,
    },
)
