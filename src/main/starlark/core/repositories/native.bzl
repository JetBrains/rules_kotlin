"""Module extension that provisions the Kotlin/Native prebuilt distributions, link bundles and Build Tools API.

For every exec host of EXEC_HOSTS (kotlin/internal/native/targets.bzl), whatever the OS of the
client, it creates:
- `com_github_jetbrains_kotlin_native_<host>`, the prebuilt distribution of the host, which
  compiles klibs for every target the host builds for;
- `com_github_jetbrains_kotlin_native_deps_<host>`, the LLVM/libffi/lldb/cross-toolchain bundle
  kt_native_binary links with, for the targets of `kotlin_native.targets(...)`, with a view per
  target of the host.

It also creates, once:
- `com_github_jetbrains_kotlin_native_btapi`, the Kotlin/Native Build Tools API implementation of
  the release, whose `runtime` klib compilations load with the compiler jar of the distribution;
  empty for a release without one, whose klibs compile with the konanc command line;
- `kotlin_native_build_tools_api`, the Build Tools API jar of KOTLIN_NATIVE_VERSION, which the
  launcher of the Kotlin/Native actions is compiled against and bundles, whatever release the
  `version` tag selects.

Repositories are only fetched when a native target is built, so JVM-only builds download none.
"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/native:targets.bzl", "EXEC_HOSTS")
load(
    ":native_compiler.bzl",
    "KOTLIN_NATIVE_BTAPI_API",
    "KOTLIN_NATIVE_VERSION",
    "collect_kotlin_native_config",
    "kotlin_native_btapi",
    "kotlin_native_btapi_repository",
    "kotlin_native_btapi_runtime",
    "kotlin_native_bundle",
    "kotlin_native_compiler_repository",
    "kotlin_native_deps_repository",
    "kotlin_native_distribution",
)

KOTLIN_NATIVE_REPO = "com_github_jetbrains_kotlin_native_"
KOTLIN_NATIVE_DEPS_REPO = "com_github_jetbrains_kotlin_native_deps_"
KOTLIN_NATIVE_BTAPI_REPO = "com_github_jetbrains_kotlin_native_btapi"
KOTLIN_NATIVE_BTAPI_API_REPO = "kotlin_native_build_tools_api"

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

    # The Build Tools API implementation klib compilations of the selected release load.
    runtime = kotlin_native_btapi_runtime(config.btapi)
    kotlin_native_btapi_repository(
        name = KOTLIN_NATIVE_BTAPI_REPO,
        urls = runtime.urls,
        sha256 = runtime.sha256,
        version = config.version,
    )

    # The Build Tools API the launcher is compiled against: the one of the release rules_kotlin
    # pins, as the launcher ships with rules_kotlin.
    api = kotlin_native_btapi(KOTLIN_NATIVE_VERSION, {})
    if api == None:
        fail("Kotlin/Native %s, which rules_kotlin pins, has no Build Tools API in KOTLIN_NATIVE_BTAPI " % KOTLIN_NATIVE_VERSION +
             "(src/main/starlark/core/repositories/native_compiler.bzl): pin a release with one, " +
             "2.5.20-dev-4986 or newer, with scripts/upgrade_kotlin.sh upgrade-native")
    http_file(
        name = KOTLIN_NATIVE_BTAPI_API_REPO,
        urls = api[KOTLIN_NATIVE_BTAPI_API].urls,
        sha256 = api[KOTLIN_NATIVE_BTAPI_API].sha256,
        downloaded_file_path = KOTLIN_NATIVE_BTAPI_API + ".jar",
    )

    return module_ctx.extension_metadata(reproducible = True)

_version_tag = tag_class(
    doc = "The Kotlin/Native release to use instead of the one rules_kotlin pins. Only the root " +
          "module may declare it. A release downloads from GitHub, a dev build (e.g. " +
          "2.5.20-dev-5696) from the Kotlin dev Maven repository. The link dependencies " +
          "rules_kotlin pins, with the LLVM of the release (KOTLIN_NATIVE_LLVM in " +
          "native_compiler.bzl), are checked against the release when they are fetched.",
    attrs = {
        "btapi_sha256": attr.string_dict(
            doc = "The sha256 of the Kotlin/Native Build Tools API implementation of the release " +
                  "per Maven artifact id: kotlin-build-tools-impl, kotlin-build-tools-cri-impl and " +
                  "kotlin-daemon-client, all of them or none. It overrides the checksums " +
                  "rules_kotlin pins for the release (KOTLIN_NATIVE_BTAPI in native_compiler.bzl). " +
                  "A release without pinned checksums and without these compiles klibs with the " +
                  "konanc command line, whatever experimental_native_build_tools_api says.",
        ),
        "sha256": attr.string_dict(
            doc = "The sha256 of the kotlin-native-prebuilt archive per exec host (linux-x86_64, " +
                  "macos-aarch64). It overrides the checksum rules_kotlin pins for the release " +
                  "(KOTLIN_NATIVE_PREBUILT in native_compiler.bzl). An archive of a release " +
                  "without pinned checksums and without one here downloads unverified.",
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
