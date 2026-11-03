"""Repository rule + host table for the Kotlin/Native prebuilt distribution.

Parallels `kotlin_compiler_repository` (compiler.bzl): download_and_extract a
host-specific `kotlin-native-prebuilt-<os>-<arch>-<version>` archive and expose the
konanc launcher + the whole distribution tree.

The distribution alone is sufficient for `-produce library` (host and cross-target); no
LLVM/sysroot download is required for klib compilation (that is a binary-linking concern,
see `kotlin_native_deps_repository` below).
"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "get_auth")
load(":versions.bzl", "versions")

# Kotlin/Native version. Kept in lockstep with the Kotlin compiler release train
# (klibs are coupled to the compiler version that produced them).
KOTLIN_NATIVE_VERSION = versions.KOTLIN_CURRENT_COMPILER_RELEASE.version

# Per-host prebuilt distribution. Keyed by "<os>-<cpu>" as derived from the module
# extension's host detection. The sha256 values belong to KOTLIN_NATIVE_VERSION; bump them
# together with the Kotlin release (see the `.sha256` files published next to each
# archive on the GitHub release page).
KOTLIN_NATIVE_PREBUILT = {
    "linux-x86_64": struct(
        sha256 = "4935d8c8da90a2d2a8ff51da7d2c264c0d6026e1d35a8f169e218d9209965678",
        archive = "kotlin-native-prebuilt-linux-x86_64-{version}",
    ),
    "macos-aarch64": struct(
        sha256 = "bf4edb526d91e17d0862102f69250525d788e79011f86c2c64362749adf260ae",
        archive = "kotlin-native-prebuilt-macos-aarch64-{version}",
    ),
}

_URL_TEMPLATE = "https://github.com/JetBrains/kotlin/releases/download/v{version}/{archive}.tar.gz"

_BUILD = """\
package(default_visibility = ["//visibility:public"])

# The konanc launcher (a bash script that shells run_konan -> JVM).
exports_files(["bin/konanc"])

# The entire distribution tree (bin/, klib/, konan/) as compile inputs; konanc resolves
# run_konan + konan/lib jars + bundled platform klibs relative to itself.
filegroup(
    name = "home",
    srcs = glob(["**"], exclude = ["BUILD.bazel", "WORKSPACE", "MODULE.bazel"]),
)
"""

def _kotlin_native_compiler_impl(repository_ctx):
    attr = repository_ctx.attr
    repository_ctx.download_and_extract(
        attr.urls,
        sha256 = attr.sha256,
        stripPrefix = attr.strip_prefix,
        auth = get_auth(repository_ctx, attr.urls),
    )
    repository_ctx.file("BUILD.bazel", _BUILD, executable = False)

    # Bazel <8.3.0 lacks repository_ctx.repo_metadata
    if not hasattr(repository_ctx, "repo_metadata"):
        return None
    return repository_ctx.repo_metadata(reproducible = attr.sha256 != "")

kotlin_native_compiler_repository = repository_rule(
    implementation = _kotlin_native_compiler_impl,
    attrs = {
        "sha256": attr.string(doc = "sha256 of the prebuilt archive"),
        "strip_prefix": attr.string(doc = "archive top-level directory to strip"),
        "urls": attr.string_list(doc = "URLs for the prebuilt archive", mandatory = True),
    },
)

# --- konan dependency bundle (LLVM / sysroot / cross-toolchain) for binary linking ---
#
# klib compilation needs none of these. Binary linking (`-produce program`) does: konanc
# otherwise downloads them to ~/.konan on first run. Pre-staging them (here) + reproducing
# konanc's `dependencies/.extracted` marker lets the link action run sandboxed with no
# network. Keyed by build host; a host's bundle covers all targets it can build (the
# LLVM/libffi/lldb are host artifacts, the *-gcc-* cross-toolchain is target-specific).
# Apple *targets* additionally need a local Xcode SDK (not vendorable here).
#
# The dependency names must match the ones the distribution's `konan/konan.properties`
# asks for (`llvm.<host>.user`, `libffiDir.<host>`, `dependencies.<host>[-<target>]`,
# `toolchainDependency.<target>`); re-check them on every Kotlin release bump.
_DEPS_BASE = "https://download.jetbrains.com/kotlin/native"

KOTLIN_NATIVE_DEPS = {
    "macos-aarch64": {
        # name (== archive top dir == konanc dependency dir) : (url, sha256)
        "libffi-3.3-1-macos-arm64": (_DEPS_BASE + "/libffi-3.3-1-macos-arm64.tar.gz", "8ca0102ad5b626e8b1699f311ab098354a90154ea3e44951f28ebdd256862ba9"),
        "lldb-4-macos": (_DEPS_BASE + "/lldb-4-macos.tar.gz", "069193359103d4e4a4653f236e7a963e266a4a366905e858d4a68e701f43866e"),
        "llvm-21-aarch64-macos-essentials-97": (_DEPS_BASE + "/resources/llvm/21-aarch64-macos/llvm-21-aarch64-macos-essentials-97.tar.gz", "62fd78f090353aa7b2c6601ad6f95bd7a0b0558b18f86978043cc878321b408a"),
        "x86_64-unknown-linux-gnu-gcc-8.3.0-glibc-2.19-kernel-4.9-2": (_DEPS_BASE + "/x86_64-unknown-linux-gnu-gcc-8.3.0-glibc-2.19-kernel-4.9-2.tar.gz", "a048397d50fb5a2bd6cc0f89d5a30e0b8ff0373ebff9c1d78ce1f1fb7f185a50"),
    },
}

_DEPS_BUILD = """\
package(default_visibility = ["//visibility:public"])

# The pre-staged konan dependency tree (dependencies/<dep>/ + dependencies/.extracted).
# kt_native_binary stages this into a writable KONAN_DATA_DIR so konanc skips its download.
filegroup(
    name = "deps",
    srcs = glob(["dependencies/**"], allow_empty = False),
)
"""

def _kotlin_native_deps_impl(repository_ctx):
    names = []
    for name, (url, sha256) in sorted(repository_ctx.attr.deps.items()):
        repository_ctx.download_and_extract(
            url,
            sha256 = sha256,
            output = "dependencies",
            auth = get_auth(repository_ctx, [url]),
        )
        names.append(name)

    # The marker konanc reads to know which dependencies are already present.
    repository_ctx.file(
        "dependencies/.extracted",
        content = "\n".join(names) + "\n",
        executable = False,
    )
    repository_ctx.file("BUILD.bazel", _DEPS_BUILD, executable = False)

    # Bazel <8.3.0 lacks repository_ctx.repo_metadata
    if not hasattr(repository_ctx, "repo_metadata"):
        return None
    return repository_ctx.repo_metadata(
        reproducible = all([sha256 for (_, sha256) in repository_ctx.attr.deps.values()]),
    )

kotlin_native_deps_repository = repository_rule(
    implementation = _kotlin_native_deps_impl,
    attrs = {
        "deps": attr.string_list_dict(
            doc = "map of dependency dir name -> [url, sha256]",
            mandatory = True,
        ),
    },
)

def kotlin_native_deps_for_host(os_name, cpu_name):
    """Returns the konan dependency bundle to stage for the host, or fails if unsupported.

    Args:
      os_name: normalized host OS (e.g. "macos").
      cpu_name: normalized host CPU (e.g. "aarch64").

    Returns:
      A dict of dependency dir name -> [url, sha256].
    """
    host = "{os}-{cpu}".format(os = os_name, cpu = cpu_name)
    table = KOTLIN_NATIVE_DEPS.get(host)
    if not table:
        fail("No Kotlin/Native dependency bundle configured for host '%s' (supported: %s)" %
             (host, ", ".join(sorted(KOTLIN_NATIVE_DEPS.keys()))))
    return {name: [url, sha256] for name, (url, sha256) in table.items()}

def kotlin_native_dist_for_host(os_name, cpu_name):
    """Returns the prebuilt distribution coordinates for the host, or fails if unsupported.

    Args:
      os_name: normalized host OS (e.g. "macos").
      cpu_name: normalized host CPU (e.g. "aarch64").

    Returns:
      A (url_list, sha256, strip_prefix) tuple.
    """
    host = "{os}-{cpu}".format(os = os_name, cpu = cpu_name)
    spec = KOTLIN_NATIVE_PREBUILT.get(host)
    if not spec:
        fail("No Kotlin/Native prebuilt distribution configured for host '%s' (supported: %s)" %
             (host, ", ".join(sorted(KOTLIN_NATIVE_PREBUILT.keys()))))
    archive = spec.archive.format(version = KOTLIN_NATIVE_VERSION)
    url = _URL_TEMPLATE.format(version = KOTLIN_NATIVE_VERSION, archive = archive)
    return ([url], spec.sha256, archive)
