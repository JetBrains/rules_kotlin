"""Repository rules + tables for the Kotlin/Native prebuilt distribution, its link dependencies and its Build Tools API.

Parallels `kotlin_compiler_repository` (compiler.bzl): download_and_extract a
host-specific `kotlin-native-prebuilt-<os>-<arch>-<version>` archive and expose the parts
of the distribution konanc reads (konan/, the stdlib, the platform libraries of each target)
as DirectoryInfo trees.

The distribution alone is sufficient for `-produce library` (host and cross-target); no
LLVM/sysroot download is required for klib compilation (that is a binary-linking concern,
see `kotlin_native_deps_repository` below). Klib compilation through the Kotlin Build Tools API
loads the implementation jars of `kotlin_native_btapi_repository` on top of it.

The tables and the pure helpers at the end of the file (bundle composition, tag collection,
konan.properties parsing and cross-check) are unit-tested by
//src/test/starlark:native_repositories_tests.
"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "get_auth")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/native:targets.bzl", "EXEC_HOSTS", "KONAN_TARGETS")

# Kotlin/Native version. It is pinned apart from the Kotlin compiler of the JVM toolchain
# (versions.KOTLIN_CURRENT_COMPILER_RELEASE), so it can move to a dev build of the next release on
# its own: klibs are coupled to the Kotlin/Native compiler that produced them, not to the JVM one.
# scripts/upgrade_kotlin.sh upgrade-native rewrites it, with the tables below.
KOTLIN_NATIVE_VERSION = "2.5.20-dev-5696"

# The prebuilt distribution archive of each exec host of EXEC_HOSTS, named after the release.
KOTLIN_NATIVE_PREBUILT_ARCHIVE = {
    "linux-x86_64": "kotlin-native-prebuilt-linux-x86_64-{version}",
    "macos-aarch64": "kotlin-native-prebuilt-macos-aarch64-{version}",
}

# The sha256 of the prebuilt distribution of each exec host of EXEC_HOSTS, per pinned Kotlin/Native
# release: KOTLIN_NATIVE_VERSION, and the older releases a root module may still select with
# kotlin_native.version(...) without giving checksums. The `.sha256` files published next to each
# archive hold them: on the GitHub release page for a release, in the Kotlin dev Maven repository
# for a dev build. A release that is not here downloads unverified unless its tag gives the
# checksums.
KOTLIN_NATIVE_PREBUILT = {
    "2.4.21": {
        "linux-x86_64": "4935d8c8da90a2d2a8ff51da7d2c264c0d6026e1d35a8f169e218d9209965678",
        "macos-aarch64": "bf4edb526d91e17d0862102f69250525d788e79011f86c2c64362749adf260ae",
    },
    "2.5.20-dev-5696": {
        "linux-x86_64": "a298f1ade6138044b547047424ef0cff2983cfbc006d97a493090c610e148d32",
        "macos-aarch64": "7fef64437214694d9a1454fb1da76302151fa7487b3d102e5cc258c3b78bbacd",
    },
}

_URL_TEMPLATE = "https://github.com/JetBrains/kotlin/releases/download/v{version}/{archive}.tar.gz"

# Dev builds (e.g. 2.5.20-dev-5696) are no GitHub releases: the Kotlin dev Maven repository
# publishes their distributions, with the exec host as the classifier, and their jars.
_MAVEN_DEV = "https://redirector.kotlinlang.org/maven/dev"
_MAVEN_CENTRAL = "https://repo1.maven.org/maven2"
_DEV_URL_TEMPLATE = "{repository}/org/jetbrains/kotlin/kotlin-native-prebuilt/{version}/kotlin-native-prebuilt-{version}-{host}.tar.gz"
_JAR_URL_TEMPLATE = "{repository}/org/jetbrains/kotlin/{artifact}/{version}/{artifact}-{version}.jar"

# The Maven artifacts of the Kotlin/Native Build Tools API of each pinned Kotlin/Native release, by
# artifact id: kotlin-build-tools-api, the API the launcher is compiled against, and the
# implementation a klib compilation loads with the compiler jar of the distribution
# (KOTLIN_NATIVE_BTAPI_RUNTIME). The `.sha256` files published next to each jar hold the checksums.
# A release that is not here compiles klibs with the konanc command line, unless its tag gives the
# checksums of the implementation. Releases older than 2.5.20-dev-4986 have no Kotlin/Native Build
# Tools API at all.
KOTLIN_NATIVE_BTAPI = {
    "2.5.20-dev-5696": {
        "kotlin-build-tools-api": "d5f237685c4e076d931308e6bda65fd1458876c06d8d3973895400096eaaefc5",
        "kotlin-build-tools-cri-impl": "5fc10c82daf0d72be5121da6388453835fe93d3e92b2ddd189539924c3ad6616",
        "kotlin-build-tools-impl": "d766343a23aac92d7af9c72d1768fdecd0b7e99be6f57fe18800c7e18bb68f8c",
        "kotlin-daemon-client": "cc1849dff7d55605e8b3228ed3148b8d15c04761504d61c2ba1b78fea1a84e6f",
    },
}

# The Build Tools API artifact the launcher is compiled against.
KOTLIN_NATIVE_BTAPI_API = "kotlin-build-tools-api"

# The Build Tools API implementation artifacts a klib compilation loads, besides the compiler jar of
# the distribution.
KOTLIN_NATIVE_BTAPI_RUNTIME = ["kotlin-build-tools-cri-impl", "kotlin-build-tools-impl", "kotlin-daemon-client"]

# The generated BUILD files load these by canonical label, which resolves in any repository.
_DIRECTORY_BZL = str(Label("@bazel_skylib//rules/directory:directory.bzl"))
_SUBDIRECTORY_BZL = str(Label("@bazel_skylib//rules/directory:subdirectory.bzl"))
_TOOLCHAINS_BZL = str(Label("//kotlin/internal/native:toolchains.bzl"))

_COMPILER_BUILD = """\
load("{directory_bzl}", "directory")
load("{subdirectory_bzl}", "subdirectory")

package(default_visibility = ["//visibility:public"])

# The link bundle repository checks its dependencies against it.
exports_files(["konan/konan.properties"])

# What konanc reads under -Dkonan.home: the compiler (konan/), the stdlib and the platform
# libraries of the targets this host builds for. bin/ stays out, as run_konan resolves the
# real repository path, outside the sandbox, and so does klib/cache, which konanc does not need.
directory(
    name = "home",
    srcs = glob({srcs}),
)

subdirectory(
    name = "konan",
    parent = ":home",
    path = "konan",
)

subdirectory(
    name = "stdlib",
    parent = ":home",
    path = "klib/common/stdlib",
)
"""

_COMPILER_PLATFORM_LIBS = """
subdirectory(
    name = "platform_{target}",
    parent = ":home",
    path = "klib/platform/{target}",
)
"""

def kotlin_native_compiler_build_file(konan_targets):
    """The BUILD file of a distribution repository.

    Args:
      konan_targets: the konan targets the host of the distribution builds for.

    Returns:
      The content of the BUILD file.
    """
    srcs = ["konan/**", "klib/common/stdlib/**"] + ["klib/platform/%s/**" % target for target in konan_targets]
    content = _COMPILER_BUILD.format(
        directory_bzl = _DIRECTORY_BZL,
        subdirectory_bzl = _SUBDIRECTORY_BZL,
        srcs = repr(srcs),
    )
    return content + "".join([_COMPILER_PLATFORM_LIBS.format(target = target) for target in konan_targets])

def _kotlin_native_compiler_impl(repository_ctx):
    attr = repository_ctx.attr
    repository_ctx.download_and_extract(
        attr.urls,
        sha256 = attr.sha256,
        stripPrefix = attr.strip_prefix,
        auth = get_auth(repository_ctx, attr.urls),
    )
    repository_ctx.file("BUILD.bazel", kotlin_native_compiler_build_file(attr.konan_targets), executable = False)

    # Bazel <8.3.0 lacks repository_ctx.repo_metadata
    if not hasattr(repository_ctx, "repo_metadata"):
        return None
    return repository_ctx.repo_metadata(reproducible = attr.sha256 != "")

kotlin_native_compiler_repository = repository_rule(
    implementation = _kotlin_native_compiler_impl,
    attrs = {
        "konan_targets": attr.string_list(
            doc = "the konan targets of the host, whose platform libraries the repository exposes",
            mandatory = True,
        ),
        "sha256": attr.string(doc = "sha256 of the prebuilt archive"),
        "strip_prefix": attr.string(doc = "archive top-level directory to strip"),
        "urls": attr.string_list(doc = "URLs for the prebuilt archive", mandatory = True),
    },
)

# --- konan dependency bundle (LLVM / libffi / lldb / cross-toolchain / emulator) for binary linking ---
#
# klib compilation needs none of these. Binary linking (`-produce program`) does: konanc
# otherwise downloads them to ~/.konan on first run. Pre-staging them (here), with the link
# launcher reproducing konanc's `dependencies/.extracted` marker per action, lets the link
# action run sandboxed with no network. Apple *targets* additionally need a local Xcode SDK
# (not vendorable here).
_DEPS_BASE = "https://download.jetbrains.com/kotlin/native"

# Every link dependency of KOTLIN_NATIVE_LLVM and KOTLIN_NATIVE_DEPS: name (== archive top dir ==
# konanc dependency dir) : (url, sha256). Only the LLVM archives have a matching `.sha256` file
# next to them; compute the others by downloading the archive.
KOTLIN_NATIVE_ARCHIVES = {
    "aarch64-unknown-linux-gnu-gcc-8.3.0-glibc-2.25-kernel-4.9-2": (_DEPS_BASE + "/aarch64-unknown-linux-gnu-gcc-8.3.0-glibc-2.25-kernel-4.9-2.tar.gz", "a026ede10b5dc2f2dcba91115338040ba62558ca14cf1a18cfba50768b245385"),
    "libffi-3.2.1-2-linux-x86-64": (_DEPS_BASE + "/libffi-3.2.1-2-linux-x86-64.tar.gz", "9d817bbca098a2fa0f1d5a8b9e57674c30d100bb4c6aeceff18d8acc5b9f382c"),
    "libffi-3.3-1-macos-arm64": (_DEPS_BASE + "/libffi-3.3-1-macos-arm64.tar.gz", "8ca0102ad5b626e8b1699f311ab098354a90154ea3e44951f28ebdd256862ba9"),
    "lldb-4-linux": (_DEPS_BASE + "/lldb-4-linux.tar.gz", "b1e145c859f44071f66231cfc98c8c16a480cbf47139fcd5dd2df4bf041fdfda"),
    "lldb-4-macos": (_DEPS_BASE + "/lldb-4-macos.tar.gz", "069193359103d4e4a4653f236e7a963e266a4a366905e858d4a68e701f43866e"),
    "llvm-21-aarch64-macos-essentials-97": (_DEPS_BASE + "/resources/llvm/21-aarch64-macos/llvm-21-aarch64-macos-essentials-97.tar.gz", "62fd78f090353aa7b2c6601ad6f95bd7a0b0558b18f86978043cc878321b408a"),
    "llvm-21-x86_64-linux-essentials-116": (_DEPS_BASE + "/resources/llvm/21-x86_64-linux/llvm-21-x86_64-linux-essentials-116.tar.gz", "0b1f290214dd7ec20e2506210967e0ebd735cdefc3a3b4485bbccb439fa78e5b"),
    "qemu-aarch64-static-5.1.0-linux-2": (_DEPS_BASE + "/qemu-aarch64-static-5.1.0-linux-2.tar.gz", "87b618ef95bc9883069c47ee625e287d1c38154e94bc7de7df8706d57e3e50e5"),
    "x86_64-unknown-linux-gnu-gcc-8.3.0-glibc-2.19-kernel-4.9-2": (_DEPS_BASE + "/x86_64-unknown-linux-gnu-gcc-8.3.0-glibc-2.19-kernel-4.9-2.tar.gz", "a048397d50fb5a2bd6cc0f89d5a30e0b8ff0373ebff9c1d78ce1f1fb7f185a50"),
}

# The LLVM each exec host of EXEC_HOSTS links with, per Kotlin/Native release: the essentials
# build its distribution names in `llvm.<host>.user` of its `konan/konan.properties` (the
# kotlin-native/gradle.properties of the release tag no longer names it). The LLVM is the link
# dependency that changes between releases, the others (KOTLIN_NATIVE_DEPS) rarely. A release
# that is not here stages no LLVM, and its link bundle fails with the one its konan.properties
# requires when it is fetched: add the release here and its archives to KOTLIN_NATIVE_ARCHIVES
# (their `.sha256` files are published next to them).
KOTLIN_NATIVE_LLVM = {
    "2.4.21": {
        "linux-x86_64": "llvm-21-x86_64-linux-essentials-116",
        "macos-aarch64": "llvm-21-aarch64-macos-essentials-97",
    },
    "2.5.20-dev-5696": {
        "linux-x86_64": "llvm-21-x86_64-linux-essentials-116",
        "macos-aarch64": "llvm-21-aarch64-macos-essentials-97",
    },
}

# The link dependencies of each exec host of EXEC_HOSTS besides its LLVM, by name: `host` ones to
# link for any target (libffi) and `targets` ones on top of them for that target (lldb for the host
# itself, the *-gcc-* cross-toolchain for Linux, and on a Linux host the qemu emulator of another
# Linux target, which konanc requires to link although it only runs tests with it). iOS targets
# add none, as Xcode provides their toolchain and SDK.
#
# With the LLVM of the release, they must be exactly the ones the `konan/konan.properties` of the
# host's own distribution asks for (see konan_link_dependencies): each distribution points its
# host at the essentials LLVM (`llvm.<host>.user`), but other hosts at the dev one. The deps
# repository checks that when it is fetched; re-check them on every Kotlin release bump.
KOTLIN_NATIVE_DEPS = {
    "linux-x86_64": struct(
        host = ["libffi-3.2.1-2-linux-x86-64"],
        targets = {
            "linux_arm64": ["aarch64-unknown-linux-gnu-gcc-8.3.0-glibc-2.25-kernel-4.9-2", "qemu-aarch64-static-5.1.0-linux-2"],
            "linux_x64": ["lldb-4-linux", "x86_64-unknown-linux-gnu-gcc-8.3.0-glibc-2.19-kernel-4.9-2"],
        },
    ),
    "macos-aarch64": struct(
        host = ["libffi-3.3-1-macos-arm64"],
        targets = {
            "ios_arm64": [],
            "ios_simulator_arm64": [],
            "linux_arm64": ["aarch64-unknown-linux-gnu-gcc-8.3.0-glibc-2.25-kernel-4.9-2"],
            "linux_x64": ["x86_64-unknown-linux-gnu-gcc-8.3.0-glibc-2.19-kernel-4.9-2"],
            "macos_arm64": ["lldb-4-macos"],
        },
    ),
}

_DEPS_BUILD = """\
load("{directory_bzl}", "directory")
load("{subdirectory_bzl}", "subdirectory")
load("{toolchains_bzl}", "kt_native_deps_view")

package(default_visibility = ["//visibility:public"])
"""

_DEPS_ROOT = """
# The link dependencies, laid out as konanc keeps them under KONAN_DATA_DIR/dependencies.
directory(
    name = "root",
    srcs = glob(["dependencies/**"]),
)
"""

_DEPS_DIRECTORY = """
subdirectory(
    name = "{name}",
    parent = ":root",
    path = "dependencies/{name}",
)
"""

_DEPS_VIEW = """
# The link dependencies of {target}.
kt_native_deps_view(
    name = "{target}",
    konan_target = "{target}",
    deps = {deps},
)
"""

_DEPS_STUB = """
# {target} is not in kotlin_native.targets(...): its klibs compile, but nothing links for it.
kt_native_deps_view(
    name = "{target}",
    konan_target = "{target}",
    staged = False,
)
"""

def kotlin_native_deps_build_file(views, unstaged_targets):
    """The BUILD file of a link bundle repository, with a view per konan target of its host.

    Args:
      views: a dict of each staged konan target to the dependency names it links with.
      unstaged_targets: the konan targets of the host without link dependencies.

    Returns:
      The content of the BUILD file.
    """
    names = sorted({name: None for view in views.values() for name in view}.keys())
    content = _DEPS_BUILD.format(
        directory_bzl = _DIRECTORY_BZL,
        subdirectory_bzl = _SUBDIRECTORY_BZL,
        toolchains_bzl = _TOOLCHAINS_BZL,
    )
    if names:
        content += _DEPS_ROOT + "".join([_DEPS_DIRECTORY.format(name = name) for name in names])
    for target in sorted(views.keys() + unstaged_targets):
        if target in views:
            content += _DEPS_VIEW.format(target = target, deps = repr([":" + name for name in views[target]]))
        else:
            content += _DEPS_STUB.format(target = target)
    return content

_DEPS_MISMATCH = """\
Kotlin/Native {version} needs other link dependencies on {host} than the ones rules_kotlin pins \
(KOTLIN_NATIVE_LLVM and KOTLIN_NATIVE_DEPS in src/main/starlark/core/repositories/native_compiler.bzl), \
per {properties}:
  {problems}
rules_kotlin pins the LLVM of Kotlin/Native {pinned}. Use one of these releases, leave these targets \
out of kotlin_native.targets(...) to compile klibs only, or pin the link dependencies of this release \
in KOTLIN_NATIVE_ARCHIVES, KOTLIN_NATIVE_LLVM and KOTLIN_NATIVE_DEPS."""

def _kotlin_native_deps_impl(repository_ctx):
    attr = repository_ctx.attr

    # Checked before downloading anything, so a release with other dependencies fails fast.
    if attr.views:
        properties = parse_konan_properties(repository_ctx.read(repository_ctx.path(attr.konan_properties)))
        problems = check_bundle_against_properties(properties, attr.konan_host, attr.views)
        if problems:
            fail(_DEPS_MISMATCH.format(
                host = attr.konan_host,
                version = attr.version,
                pinned = ", ".join(sorted(KOTLIN_NATIVE_LLVM.keys())),
                properties = attr.konan_properties,
                problems = "\n  ".join(problems),
            ))

    for name, (url, sha256) in sorted(attr.archives.items()):
        repository_ctx.download_and_extract(
            url,
            sha256 = sha256,
            output = "dependencies",
            auth = get_auth(repository_ctx, [url]),
        )
        if not repository_ctx.path("dependencies/" + name).exists:
            fail("%s does not extract to dependencies/%s, the directory konanc looks it up in" % (url, name))
    repository_ctx.file(
        "BUILD.bazel",
        kotlin_native_deps_build_file(attr.views, attr.unstaged_targets),
        executable = False,
    )

    # Bazel <8.3.0 lacks repository_ctx.repo_metadata
    if not hasattr(repository_ctx, "repo_metadata"):
        return None
    return repository_ctx.repo_metadata(
        reproducible = all([sha256 for (_, sha256) in attr.archives.values()]),
    )

kotlin_native_deps_repository = repository_rule(
    implementation = _kotlin_native_deps_impl,
    attrs = {
        "archives": attr.string_list_dict(
            doc = "the dependency archives to download into dependencies/, as name -> [url, sha256]",
        ),
        "konan_host": attr.string(
            doc = "the konan name of the exec host, e.g. linux_x64",
            mandatory = True,
        ),
        "konan_properties": attr.label(
            doc = "konan/konan.properties of the host's distribution, which `views` must agree with",
            mandatory = True,
        ),
        "unstaged_targets": attr.string_list(
            doc = "the konan targets of the host without link dependencies, which get a stub view",
        ),
        "version": attr.string(
            doc = "the Kotlin/Native release of the distribution, named in the error of a mismatch",
            mandatory = True,
        ),
        "views": attr.string_list_dict(
            doc = "the dependency names each staged konan target of the host links with",
        ),
    },
)

# --- Kotlin/Native Build Tools API runtime of klib compilation ---
#
# With the build setting //kotlin/settings:experimental_native_build_tools_api on, the launcher
# compiles klibs with a NativeKlibCompilationOperation of the Kotlin Build Tools API: it loads
# these jars with the compiler jar of the distribution. A release without them compiles klibs with
# the konanc command line.

_BTAPI_BUILD = """\
package(default_visibility = ["//visibility:public"])

{comment}
filegroup(
    name = "runtime",
    srcs = {srcs},
)
"""

def kotlin_native_btapi_build_file(version, artifacts):
    """The BUILD file of a Kotlin/Native Build Tools API runtime repository.

    Args:
      version: the Kotlin/Native release of the runtime.
      artifacts: the Maven artifact ids of the jars of the repository, each downloaded as
        <artifact id>.jar; empty for a release without a runtime.

    Returns:
      The content of the BUILD file, whose filegroup `runtime` holds the jars.
    """
    if artifacts:
        comment = ("# The Kotlin/Native Build Tools API implementation of Kotlin/Native %s, which klib\n" +
                   "# compilations load with the compiler jar of the distribution.") % version
    else:
        comment = ("# Kotlin/Native %s has no Build Tools API implementation with known checksums: its klibs\n" +
                   "# compile with the konanc command line.") % version
    return _BTAPI_BUILD.format(comment = comment, srcs = repr([":%s.jar" % artifact for artifact in sorted(artifacts)]))

def kotlin_native_btapi_runtime(btapi):
    """The runtime jars of the Build Tools API artifacts of a release, as kotlin_native_btapi_repository takes them.

    Args:
      btapi: the artifacts of the release kotlin_native_btapi returns, or None.

    Returns:
      struct(urls, sha256): the URLs and the sha256 of each runtime artifact
      (KOTLIN_NATIVE_BTAPI_RUNTIME) by artifact id; empty for None.
    """
    runtime = KOTLIN_NATIVE_BTAPI_RUNTIME if btapi else []
    return struct(
        urls = {artifact: btapi[artifact].urls for artifact in runtime},
        sha256 = {artifact: btapi[artifact].sha256 for artifact in runtime},
    )

def _kotlin_native_btapi_impl(repository_ctx):
    attr = repository_ctx.attr
    for artifact, urls in sorted(attr.urls.items()):
        repository_ctx.download(
            url = urls,
            output = artifact + ".jar",
            sha256 = attr.sha256.get(artifact, ""),
            auth = get_auth(repository_ctx, urls),
        )
    repository_ctx.file(
        "BUILD.bazel",
        kotlin_native_btapi_build_file(attr.version, attr.urls.keys()),
        executable = False,
    )

    # Bazel <8.3.0 lacks repository_ctx.repo_metadata
    if not hasattr(repository_ctx, "repo_metadata"):
        return None
    return repository_ctx.repo_metadata(
        reproducible = all([attr.sha256.get(artifact, "") for artifact in attr.urls]),
    )

kotlin_native_btapi_repository = repository_rule(
    implementation = _kotlin_native_btapi_impl,
    doc = "The Kotlin/Native Build Tools API runtime of a release: its jars and a `runtime` " +
          "filegroup of them, empty for a release without one.",
    attrs = {
        "sha256": attr.string_dict(doc = "the sha256 of each jar by Maven artifact id"),
        "urls": attr.string_list_dict(
            doc = "the download URLs of each jar by Maven artifact id; empty for a release without a runtime",
        ),
        "version": attr.string(
            doc = "the Kotlin/Native release of the runtime",
            mandatory = True,
        ),
    },
)

# --- pure helpers: distribution coordinates, bundle composition, tags, konan.properties ---

def _is_dev(version):
    """Whether a Kotlin/Native version is a dev build, which only the Kotlin dev Maven repository publishes."""
    return "-dev-" in version

def kotlin_native_distribution(host_key, version, sha256):
    """The coordinates of the prebuilt distribution of a Kotlin/Native release for an exec host.

    A release downloads from its GitHub release page, a dev build (e.g. 2.5.20-dev-5696) from the
    Kotlin dev Maven repository. Both archives have the same top-level directory.

    Args:
      host_key: an exec host of EXEC_HOSTS, e.g. "linux-x86_64".
      version: the Kotlin/Native release.
      sha256: the sha256 of the archive, or "" to download it unverified.

    Returns:
      struct(urls, sha256, strip_prefix), the attributes of kotlin_native_compiler_repository.
    """
    archive = KOTLIN_NATIVE_PREBUILT_ARCHIVE[host_key].format(version = version)
    if _is_dev(version):
        url = _DEV_URL_TEMPLATE.format(repository = _MAVEN_DEV, version = version, host = host_key)
    else:
        url = _URL_TEMPLATE.format(version = version, archive = archive)
    return struct(
        urls = [url],
        sha256 = sha256,
        strip_prefix = archive,
    )

def kotlin_native_btapi(version, sha256):
    """The Build Tools API artifacts of a Kotlin/Native release, or None for a release without them.

    Args:
      version: the Kotlin/Native release, e.g. "2.5.20-dev-5696".
      sha256: the checksums of the runtime artifacts (KOTLIN_NATIVE_BTAPI_RUNTIME) by artifact id,
        e.g. the btapi_sha256 of the version tag; they override the ones KOTLIN_NATIVE_BTAPI pins.

    Returns:
      A dict of the API artifact (KOTLIN_NATIVE_BTAPI_API) and of each runtime artifact to
      struct(urls, sha256), from the Kotlin dev Maven repository for a dev build and Maven Central
      otherwise. None if neither KOTLIN_NATIVE_BTAPI nor `sha256` has the checksum of every runtime
      artifact. The API jar of a release KOTLIN_NATIVE_BTAPI does not pin has no checksum ("").
    """
    checksums = dict(KOTLIN_NATIVE_BTAPI.get(version, {}))
    checksums.update(sha256)
    if not all([artifact in checksums for artifact in KOTLIN_NATIVE_BTAPI_RUNTIME]):
        return None
    repository = _MAVEN_DEV if _is_dev(version) else _MAVEN_CENTRAL
    return {
        artifact: struct(
            urls = [_JAR_URL_TEMPLATE.format(repository = repository, artifact = artifact, version = version)],
            sha256 = checksums.get(artifact, ""),
        )
        for artifact in [KOTLIN_NATIVE_BTAPI_API] + KOTLIN_NATIVE_BTAPI_RUNTIME
    }

def kotlin_native_btapi_problems(sha256):
    """The problems of the btapi_sha256 of a kotlin_native.version tag.

    Args:
      sha256: the checksums of the tag, by Maven artifact id.

    Returns:
      A description per problem: an artifact that is not one of KOTLIN_NATIVE_BTAPI_RUNTIME, or the
      runtime artifacts a tag naming only some of them lacks. Empty for a tag that gives the
      checksum of every runtime artifact, or of none.
    """
    problems = [
        "%s is not a Build Tools API runtime artifact (%s)" % (artifact, ", ".join(KOTLIN_NATIVE_BTAPI_RUNTIME))
        for artifact in sorted(sha256.keys())
        if artifact not in KOTLIN_NATIVE_BTAPI_RUNTIME
    ]
    missing = [artifact for artifact in KOTLIN_NATIVE_BTAPI_RUNTIME if artifact not in sha256]
    if missing and len(missing) < len(KOTLIN_NATIVE_BTAPI_RUNTIME):
        problems.append("the checksum of %s is missing: give the one of every runtime artifact, or none" % ", ".join(missing))
    return problems

def kotlin_native_prebuilt_sha256(version):
    """The pinned sha256 of the prebuilt distribution of a Kotlin/Native release per exec host.

    Args:
      version: the Kotlin/Native release, e.g. "2.4.21".

    Returns:
      A dict of each exec host of EXEC_HOSTS to the sha256 of its archive, "" for a release that
      KOTLIN_NATIVE_PREBUILT does not pin.
    """
    pinned = KOTLIN_NATIVE_PREBUILT.get(version, {})
    return {host: pinned.get(host, "") for host in EXEC_HOSTS}

def kotlin_native_llvm(host_key, version):
    """The LLVM an exec host links with for a Kotlin/Native release, or None for a release without a pinned one.

    Args:
      host_key: an exec host of EXEC_HOSTS, e.g. "macos-aarch64".
      version: the Kotlin/Native release, e.g. "2.4.21".

    Returns:
      The name of the LLVM archive of KOTLIN_NATIVE_ARCHIVES, or None.
    """
    return KOTLIN_NATIVE_LLVM.get(version, {}).get(host_key)

def kotlin_native_bundle(host_key, targets, version = KOTLIN_NATIVE_VERSION):
    """The link-dependency bundle of an exec host for the konan targets to stage.

    The bundle holds the dependencies of the requested targets the host builds for, plus the
    host's own ones (the LLVM of the release, libffi) if there is at least one such target. The
    host's other targets stay unstaged: their klibs still compile, but nothing links for them. A
    release without a pinned LLVM (KOTLIN_NATIVE_LLVM) stages none, which the link bundle
    repository reports against konan.properties when it is fetched.

    Args:
      host_key: an exec host of EXEC_HOSTS, e.g. "macos-aarch64".
      targets: the konan targets to stage, e.g. collect_kotlin_native_config(...).targets.
      version: the Kotlin/Native release, e.g. collect_kotlin_native_config(...).version.

    Returns:
      struct(archives, views, unstaged): the archives to download as a dict of name to
      [url, sha256], the dependency names each staged target links with as a dict of target to
      names, and the targets of the host without a bundle.
    """
    deps = KOTLIN_NATIVE_DEPS[host_key]
    llvm = kotlin_native_llvm(host_key, version)
    host_deps = deps.host + ([llvm] if llvm else [])
    host_targets = EXEC_HOSTS[host_key].targets
    views = {
        target: sorted(host_deps + deps.targets[target])
        for target in host_targets
        if target in targets
    }
    names = sorted({name: None for view in views.values() for name in view}.keys())
    return struct(
        archives = {name: list(KOTLIN_NATIVE_ARCHIVES[name]) for name in names},
        views = views,
        unstaged = [target for target in host_targets if target not in targets],
    )

def collect_kotlin_native_config(modules):
    """Collects the `version` and `targets` tags of the kotlin_native extension.

    Only the root module may declare the tags, each at most once, so a dependency cannot change
    the Kotlin/Native release or the link bundles of a build. Without tags, the extension
    provides KOTLIN_NATIVE_VERSION and stages the link bundles of every konan target. A release
    of KOTLIN_NATIVE_PREBUILT gets its pinned checksums, which the sha256 of the tag overrides;
    any other release downloads unverified where the tag gives none. A release of
    KOTLIN_NATIVE_BTAPI gets its Build Tools API, as does one whose tag gives the checksums of
    every runtime artifact in btapi_sha256.

    Args:
      modules: the modules of the module extension context.

    Returns:
      struct(version, sha256, btapi, targets): the Kotlin/Native release, a dict of exec host to
      the sha256 of its distribution ("" if unknown), its Build Tools API artifacts as
      kotlin_native_btapi returns them (None without them), and the sorted konan targets to stage.
    """
    version_tag = None
    targets_tag = None
    for mod in modules:
        for tag in mod.tags.version:
            if not mod.is_root:
                fail("kotlin_native.version is available to the root module only; module %s declares %s" % (mod.name, tag.version))
            if version_tag != None:
                fail("kotlin_native.version is declared twice")
            version_tag = tag
        for tag in mod.tags.targets:
            if not mod.is_root:
                fail("kotlin_native.targets is available to the root module only; module %s declares %s" % (mod.name, tag.targets))
            if targets_tag != None:
                fail("kotlin_native.targets is declared twice")
            targets_tag = tag

    version = KOTLIN_NATIVE_VERSION
    sha256 = {}
    btapi_sha256 = {}
    if version_tag != None:
        for host in version_tag.sha256:
            if host not in EXEC_HOSTS:
                fail("kotlin_native.version: unsupported exec host %s in sha256 (supported: %s)" %
                     (host, ", ".join(EXEC_HOSTS.keys())))
        problems = kotlin_native_btapi_problems(version_tag.btapi_sha256)
        if problems:
            fail("kotlin_native.version: btapi_sha256 of %s: %s" % (version_tag.version, "; ".join(problems)))
        version = version_tag.version
        sha256 = version_tag.sha256
        btapi_sha256 = version_tag.btapi_sha256
    pinned = kotlin_native_prebuilt_sha256(version)
    sha256 = {host: sha256.get(host, pinned[host]) for host in EXEC_HOSTS}

    targets = sorted(KONAN_TARGETS.keys())
    if targets_tag != None:
        for target in targets_tag.targets:
            if target not in KONAN_TARGETS:
                fail("kotlin_native.targets: unsupported konan target %s (supported: %s)" %
                     (target, ", ".join(KONAN_TARGETS.keys())))
        targets = sorted({target: None for target in targets_tag.targets}.keys())

    return struct(
        version = version,
        sha256 = sha256,
        btapi = kotlin_native_btapi(version, btapi_sha256),
        targets = targets,
    )

def parse_konan_properties(text):
    """Parses the `konan/konan.properties` of a distribution as java.util.Properties does.

    It handles what the file uses: `#` and `!` comment lines, `key = value`, `key=value`,
    `key: value` and `key value` entries, and values continued on the next line after a
    trailing backslash. Other escape sequences are kept verbatim, as the file has none.

    Args:
      text: the content of the file.

    Returns:
      A dict of property name to its unresolved value. A later entry of a name wins.
    """
    properties = {}
    entry = None
    for line in text.splitlines():
        line = line.lstrip(" \t")
        if entry == None:
            if not line or line.startswith("#") or line.startswith("!"):
                continue
            entry = ""
        if _continues(line):
            entry += line[:-1]
            continue
        key, value = _split_property(entry + line)
        properties[key] = value
        entry = None
    if entry != None:
        key, value = _split_property(entry)
        properties[key] = value
    return properties

def _continues(line):
    """Whether a properties line continues on the next one: it ends in an odd number of backslashes."""
    return (len(line) - len(line.rstrip("\\"))) % 2 == 1

def _split_property(entry):
    """Splits a logical properties line into its key and its value."""
    separators = [i for i in [entry.find(c) for c in ("=", ":", " ", "\t")] if i >= 0]
    key_end = min(separators) if separators else len(entry)
    rest = entry[key_end:]
    separated = rest.startswith("=") or rest.startswith(":")
    rest = (rest[1:] if separated else rest).lstrip(" \t")
    if not separated and (rest.startswith("=") or rest.startswith(":")):
        rest = rest[1:].lstrip(" \t")
    return entry[:key_end], rest

def _tokens(value):
    """The whitespace-separated tokens of a property value."""
    return [token for token in value.replace("\t", " ").split(" ") if token]

# konan.properties nests references two levels deep; this only bounds a malformed file.
_MAX_RESOLUTION_STEPS = 1000

def _resolve_tokens(properties, value):
    """The tokens of a property value, with each `$name` token replaced by the tokens of `name`.

    That is how konan resolves the values it reads. A reference to a missing property resolves
    to nothing, as in konan, and a circular one stays as it is, so the cross-check reports it.
    """
    tokens = []
    pending = [(token, []) for token in reversed(_tokens(value))]
    for _ in range(_MAX_RESOLUTION_STEPS):
        if not pending:
            break
        token, seen = pending.pop()
        name = token[1:]
        if token.startswith("$") and name not in seen:
            pending.extend([(t, seen + [name]) for t in reversed(_tokens(properties.get(name, "")))])
        else:
            tokens.append(token)
    return tokens + [token for token, _ in reversed(pending)]

def _host_property(properties, key, suffix):
    """The value of `<key>.<suffix>`, or else of `<key>`, as konan looks a host property up."""
    name = key + "." + suffix
    return properties[name] if name in properties else properties.get(key, "")

def konan_link_dependencies(properties, konan_host, konan_target):
    """The dependencies konan needs on an exec host to link for a target, per konan.properties.

    Those are the host's LLVM (`llvmHome.<host>`) and libffi (`libffiDir.<host>`), plus
    `dependencies.<host>` to link for the host itself or `dependencies.<host>-<target>` for
    another target. The latter is absent for iOS targets, as Xcode provides their toolchain and
    SDK. A Linux target also needs its emulator, `emulatorDependency.<host>-<target>`, which
    konan's GCC configurables add to the dependencies: qemu, for linux_arm64 on linux_x64.

    Args:
      properties: the parsed konan.properties of the distribution.
      konan_host: the konan name of the exec host, e.g. "linux_x64".
      konan_target: the konan target to link for.

    Returns:
      The sorted dependency names, which are also their archive and directory names.
    """
    suffix = konan_host if konan_target == konan_host else konan_host + "-" + konan_target
    keys = [("llvmHome", konan_host), ("libffiDir", konan_host), ("dependencies", suffix)]
    if konan_target.startswith("linux_"):
        keys.append(("emulatorDependency", suffix))
    names = {}
    for key, key_suffix in keys:
        for name in _resolve_tokens(properties, _host_property(properties, key, key_suffix)):
            names[name] = None
    return sorted(names.keys())

def check_bundle_against_properties(properties, konan_host, views):
    """Compares the dependencies a bundle stages per target with the ones konan.properties requires.

    Args:
      properties: the parsed konan.properties of the distribution.
      konan_host: the konan name of the exec host of the bundle.
      views: a dict of konan target to the dependency names the bundle stages for it.

    Returns:
      A description per differing dependency; empty if the bundle has exactly the required ones.
    """
    problems = []
    for target in sorted(views.keys()):
        staged = views[target]
        required = konan_link_dependencies(properties, konan_host, target)
        problems.extend([
            "%s: konan.properties requires %s, which rules_kotlin does not stage" % (target, name)
            for name in required
            if name not in staged
        ])
        problems.extend([
            "%s: rules_kotlin stages %s, which konan.properties does not require" % (target, name)
            for name in sorted(staged)
            if name not in required
        ])
    return problems
