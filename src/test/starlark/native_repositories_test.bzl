"""Unit tests for the Kotlin/Native tables and the pure helpers of the kotlin_native extension."""

load(
    "@bazel_skylib//lib:unittest.bzl",
    "asserts",
    "unittest",
)
load("@build_bazel_apple_support//configs:platforms.bzl", "APPLE_PLATFORMS_CONSTRAINTS")

# buildifier: disable=bzl-visibility
load(
    "//kotlin/internal/native:targets.bzl",
    "APPLE_VENDOR_CONSTRAINT",
    "EXEC_HOSTS",
    "KONAN_TARGETS",
    "konan_platform_constraints",
)
load(
    "//src/main/starlark/core/repositories:native_compiler.bzl",
    "KOTLIN_NATIVE_ARCHIVES",
    "KOTLIN_NATIVE_DEPS",
    "KOTLIN_NATIVE_PREBUILT",
    "KOTLIN_NATIVE_VERSION",
    "check_bundle_against_properties",
    "collect_kotlin_native_config",
    "konan_link_dependencies",
    "kotlin_native_bundle",
    "kotlin_native_compiler_build_file",
    "kotlin_native_deps_build_file",
    "kotlin_native_distribution",
    "parse_konan_properties",
)

# The apple_support platform (@build_bazel_apple_support//platforms) of each Apple konan target.
_APPLE_SUPPORT_PLATFORMS = {
    "ios_arm64": "ios_arm64",
    "ios_simulator_arm64": "ios_sim_arm64",
    "macos_arm64": "darwin_arm64",
}

# apple_support names the arm64 CPU by the alias @platforms//cpu:arm64 of @platforms//cpu:aarch64.
_CONSTRAINT_ALIASES = {
    str(Label("@platforms//cpu:arm64")): str(Label("@platforms//cpu:aarch64")),
}

def _canonical(constraints):
    """The constraint values as sorted canonical label strings, with aliases resolved."""
    names = [str(Label(constraint)) for constraint in constraints]
    return sorted([_CONSTRAINT_ALIASES.get(name, name) for name in names])

def _apple_support_platform_constraints(konan_target):
    """The constraint values of the apple_support platform of an Apple konan target."""
    return _canonical(
        APPLE_PLATFORMS_CONSTRAINTS[_APPLE_SUPPORT_PLATFORMS[konan_target]] + [APPLE_VENDOR_CONSTRAINT],
    )

def _exec_hosts_build_known_targets_test(ctx):
    """Every exec host compiles for itself and for konan targets the platforms package declares."""
    env = unittest.begin(ctx)

    for key, host in EXEC_HOSTS.items():
        asserts.equals(env, key.replace("-", "_"), host.repo_suffix)
        asserts.equals(env, sorted(host.targets), host.targets)
        asserts.true(env, host.konan_host in host.targets, key)
        for target in host.targets:
            asserts.true(env, target in KONAN_TARGETS, "%s: unknown konan target %s" % (key, target))

    return unittest.end(env)

def _every_target_has_an_exec_host_test(ctx):
    """Every konan target is compiled by at least one exec host."""
    env = unittest.begin(ctx)

    for target in KONAN_TARGETS:
        hosts = [key for key, host in EXEC_HOSTS.items() if target in host.targets]
        asserts.true(env, len(hosts) > 0, target)

    return unittest.end(env)

def _apple_targets_only_on_macos_test(ctx):
    """Only a macOS exec host compiles for Apple targets, as those need Xcode."""
    env = unittest.begin(ctx)

    macos = str(Label("@platforms//os:macos"))
    for key, host in EXEC_HOSTS.items():
        on_macos = macos in _canonical(host.constraints)
        for target in host.targets:
            if KONAN_TARGETS[target].is_apple:
                asserts.true(env, on_macos, "%s: Apple target %s on a non-macOS host" % (key, target))

    return unittest.end(env)

def _only_apple_platforms_carry_the_apple_vendor_test(ctx):
    """A platform carries apple_support's Apple vendor constraint exactly when its target is Apple."""
    env = unittest.begin(ctx)

    apple = str(APPLE_VENDOR_CONSTRAINT)
    for name, target in KONAN_TARGETS.items():
        asserts.equals(env, target.is_apple, apple in _canonical(konan_platform_constraints(name)), name)
        asserts.false(env, apple in _canonical(target.constraints), name)

    return unittest.end(env)

def _ios_platforms_match_apple_support_test(ctx):
    """The iOS platforms carry exactly the constraints of apple_support's ios_arm64 and ios_sim_arm64."""
    env = unittest.begin(ctx)

    for target in ["ios_arm64", "ios_simulator_arm64"]:
        asserts.equals(
            env,
            _apple_support_platform_constraints(target),
            _canonical(konan_platform_constraints(target)),
        )

    return unittest.end(env)

def _apple_support_platforms_satisfy_the_targets_test(ctx):
    """apple_support's platforms satisfy the constraints the toolchains and config_settings match on."""
    env = unittest.begin(ctx)

    asserts.equals(
        env,
        sorted([name for name, target in KONAN_TARGETS.items() if target.is_apple]),
        sorted(_APPLE_SUPPORT_PLATFORMS.keys()),
    )
    for target in _APPLE_SUPPORT_PLATFORMS:
        theirs = _apple_support_platform_constraints(target)
        for constraint in _canonical(KONAN_TARGETS[target].constraints):
            asserts.true(env, constraint in theirs, "%s: %s" % (target, constraint))

    return unittest.end(env)

_GCC_AARCH64 = "aarch64-unknown-linux-gnu-gcc-8.3.0-glibc-2.25-kernel-4.9-2"
_GCC_X86_64 = "x86_64-unknown-linux-gnu-gcc-8.3.0-glibc-2.19-kernel-4.9-2"
_LIBFFI_LINUX = "libffi-3.2.1-2-linux-x86-64"
_LIBFFI_MACOS = "libffi-3.3-1-macos-arm64"
_LLDB_LINUX = "lldb-4-linux"
_LLDB_MACOS = "lldb-4-macos"
_LLVM_LINUX = "llvm-21-x86_64-linux-essentials-116"
_LLVM_LINUX_DEV = "llvm-21-x86_64-linux-dev-116"
_LLVM_MACOS = "llvm-21-aarch64-macos-essentials-97"
_QEMU_AARCH64 = "qemu-aarch64-static-5.1.0-linux-2"

# An excerpt of the konan/konan.properties of the macOS distribution of Kotlin/Native 2.4.21,
# copied verbatim: the entries the link dependencies of the supported exec hosts and targets
# resolve through, and a few of their neighbors.
_KONAN_PROPERTIES_MACOS_2_4_21 = """\
#
# Copyright 2010-2018 JetBrains s.r.o.
#
dependenciesUrl = https://download.jetbrains.com/kotlin/native

toolchainDependency.linux_x64 = x86_64-unknown-linux-gnu-gcc-8.3.0-glibc-2.19-kernel-4.9-2
toolchainDependency.linux_arm64 = aarch64-unknown-linux-gnu-gcc-8.3.0-glibc-2.25-kernel-4.9-2

dependencies.macos_x64 = \\
    lldb-4-macos

llvmHome.macos_arm64 = $llvm.macos_arm64.user
targetToolchain.macos_arm64 = target-toolchain-xcode_26.4_17E192
libffiDir.macos_arm64 = libffi-3.3-1-macos-arm64
osVersionMin.macos_arm64 = $minVersion.macos

dependencies.macos_arm64 = \\
    lldb-4-macos

targetToolchain.macos_arm64-ios_arm64 = target-toolchain-xcode_26.4_17E192
targetToolchain.macos_arm64-ios_simulator_arm64 = target-toolchain-xcode_26.4_17E192

# Linux x86-64.
llvmHome.linux_x64 = $llvm.linux_x64.dev
libffiDir.linux_x64 = libffi-3.2.1-2-linux-x86-64

gccToolchain.linux_x64 = $toolchainDependency.linux_x64
targetToolchain.linux_x64 = $gccToolchain.linux_x64/x86_64-unknown-linux-gnu
dependencies.linux_x64 = \\
    $toolchainDependency.linux_x64 \\
    lldb-4-linux

targetToolchain.macos_arm64-linux_x64 = $llvmHome.macos_arm64
dependencies.macos_arm64-linux_x64 = \\
    $toolchainDependency.linux_x64

# Linux arm64
gccToolchain.linux_arm64 = $toolchainDependency.linux_arm64

targetToolchain.linux_x64-linux_arm64 = $gccToolchain.linux_arm64/aarch64-unknown-linux-gnu
targetToolchain.macos_arm64-linux_arm64 = $llvmHome.macos_arm64

emulatorDependency.linux_x64-linux_arm64 = qemu-aarch64-static-5.1.0-linux-2

dependencies.linux_x64-linux_arm64 = \\
    $toolchainDependency.linux_arm64
dependencies.mingw_x64-linux_arm64 = \\
    $toolchainDependency.linux_arm64 \\
    $toolchainDependency.mingw_x64
dependencies.macos_arm64-linux_arm64 = \\
    $toolchainDependency.linux_arm64

llvm.linux_x64.dev=llvm-21-x86_64-linux-dev-116
llvm.linux_x64.user=llvm-21-x86_64-linux-essentials-116
llvm.macos_arm64.dev=llvm-21-aarch64-macos-dev-97
llvm.macos_arm64.user=llvm-21-aarch64-macos-essentials-97
"""

# The konan.properties of each exec host's distribution. The Linux one differs from the macOS one
# only in the LLVM each host links with: every distribution points its own host at the
# essentials LLVM and the other hosts at the dev one.
_KONAN_PROPERTIES_2_4_21 = {
    "linux-x86_64": _KONAN_PROPERTIES_MACOS_2_4_21.replace(
        "llvmHome.macos_arm64 = $llvm.macos_arm64.user",
        "llvmHome.macos_arm64 = $llvm.macos_arm64.dev",
    ).replace(
        "llvmHome.linux_x64 = $llvm.linux_x64.dev",
        "llvmHome.linux_x64 = $llvm.linux_x64.user",
    ),
    "macos-aarch64": _KONAN_PROPERTIES_MACOS_2_4_21,
}

def _native_module(name, is_root, version = None, targets = None):
    return struct(
        name = name,
        is_root = is_root,
        tags = struct(version = version or [], targets = targets or []),
    )

def _tables_belong_to_the_default_release_test(ctx):
    """The pinned tables and the konan.properties excerpt belong to the default release.

    A Kotlin release bump changes the distributions: update KOTLIN_NATIVE_PREBUILT,
    KOTLIN_NATIVE_ARCHIVES, KOTLIN_NATIVE_DEPS and the excerpt together with it.
    """
    env = unittest.begin(ctx)

    asserts.equals(env, "2.4.21", KOTLIN_NATIVE_VERSION, "update the Kotlin/Native tables for the new release")

    return unittest.end(env)

def _deps_cover_every_exec_host_target_test(ctx):
    """Every exec host has a distribution and pinned link dependencies for exactly its targets."""
    env = unittest.begin(ctx)

    asserts.equals(env, sorted(EXEC_HOSTS.keys()), sorted(KOTLIN_NATIVE_PREBUILT.keys()))
    asserts.equals(env, sorted(EXEC_HOSTS.keys()), sorted(KOTLIN_NATIVE_DEPS.keys()))
    used = {}
    for key, host in EXEC_HOSTS.items():
        deps = KOTLIN_NATIVE_DEPS[key]
        asserts.equals(env, host.targets, sorted(deps.targets.keys()), key)
        for name in deps.host + [name for names in deps.targets.values() for name in names]:
            asserts.true(env, name in KOTLIN_NATIVE_ARCHIVES, "%s: %s is not pinned" % (key, name))
            used[name] = None
        for target in host.targets:
            if KONAN_TARGETS[target].is_apple and target != host.konan_host:
                asserts.equals(env, [], deps.targets[target], "%s: %s links with Xcode" % (key, target))
    asserts.equals(env, sorted(KOTLIN_NATIVE_ARCHIVES.keys()), sorted(used.keys()))

    return unittest.end(env)

def _archives_are_pinned_test(ctx):
    """Every archive downloads over https, is named after its directory and has a sha256."""
    env = unittest.begin(ctx)

    for name, (url, sha256) in KOTLIN_NATIVE_ARCHIVES.items():
        asserts.true(env, url.startswith("https://"), url)
        asserts.true(env, url.endswith("/%s.tar.gz" % name), url)
        asserts.equals(env, 64, len(sha256), name)
        asserts.equals(env, "", sha256.lstrip("0123456789abcdef"), name)
    for key, spec in KOTLIN_NATIVE_PREBUILT.items():
        asserts.equals(env, 64, len(spec.sha256), key)
        asserts.equals(env, "", spec.sha256.lstrip("0123456789abcdef"), key)

    return unittest.end(env)

def _parser_follows_java_properties_test(ctx):
    """The parser reads separators, comments and continued lines as java.util.Properties does."""
    env = unittest.begin(ctx)

    asserts.equals(
        env,
        {
            "a": "1",
            "b": "2",
            "c": "3",
            "d": "4",
            "e": "x yz",
            "f": "",
            "g": "last",
            "h": "",
            "i": "a=b",
        },
        parse_konan_properties("\n".join([
            "# a comment does not continue \\",
            "a = 1",
            "! nor does this one \\",
            "b=2",
            "c: 3",
            "d 4",
            "  e =  x \\",
            "       y\\",
            "z",
            "f = \\",
            "",
            "g = 7",
            "g = last",
            "i = a=b",
            "h = \\",
        ])),
    )

    return unittest.end(env)

def _parser_reads_konan_properties_test(ctx):
    """The parser reads the entries of konan.properties and joins their continued values."""
    env = unittest.begin(ctx)

    properties = parse_konan_properties(_KONAN_PROPERTIES_2_4_21["macos-aarch64"])
    asserts.equals(env, "https://download.jetbrains.com/kotlin/native", properties["dependenciesUrl"])
    asserts.equals(env, "lldb-4-macos", properties["dependencies.macos_arm64"])
    asserts.equals(env, "$toolchainDependency.linux_x64 lldb-4-linux", properties["dependencies.linux_x64"])
    asserts.equals(env, "$llvm.linux_x64.dev", properties["llvmHome.linux_x64"])
    asserts.equals(env, "$llvm.macos_arm64.user", properties["llvmHome.macos_arm64"])
    asserts.equals(env, _LLVM_LINUX, properties["llvm.linux_x64.user"])
    asserts.equals(env, [], [key for key in properties if key.startswith("#")])

    linux = parse_konan_properties(_KONAN_PROPERTIES_2_4_21["linux-x86_64"])
    asserts.equals(env, "$llvm.linux_x64.user", linux["llvmHome.linux_x64"])
    asserts.equals(env, "$llvm.macos_arm64.dev", linux["llvmHome.macos_arm64"])

    return unittest.end(env)

def _link_dependencies_resolve_references_test(ctx):
    """References resolve recursively and missing ones to nothing; circular ones stay unresolved."""
    env = unittest.begin(ctx)

    properties = {
        "a": "$b x",
        "b": "$a",
        "dependencies": "fallback",
        "dependencies.h-t": "$missing dep",
        "libffiDir.h": "ffi",
        "llvmHome.h": "$a",
    }
    asserts.equals(env, ["$a", "dep", "ffi", "x"], konan_link_dependencies(properties, "h", "t"))
    asserts.equals(env, ["$a", "fallback", "ffi", "x"], konan_link_dependencies(properties, "h", "other"))

    return unittest.end(env)

def _link_dependencies_add_the_emulator_test(ctx):
    """A Linux target also needs the emulator of its host, as konan's GCC configurables add it; other targets do not."""
    env = unittest.begin(ctx)

    properties = {
        "emulatorDependency.h-ios_t": "simulator",
        "emulatorDependency.h-linux_t": "$qemu",
        "qemu": "qemu-t",
    }
    asserts.equals(env, ["qemu-t"], konan_link_dependencies(properties, "h", "linux_t"))
    asserts.equals(env, [], konan_link_dependencies(properties, "h", "linux_other"))
    asserts.equals(env, [], konan_link_dependencies(properties, "h", "ios_t"))

    return unittest.end(env)

def _link_dependencies_match_the_table_test(ctx):
    """konan.properties of 2.4.21 requires exactly the table's dependencies for every host and target."""
    env = unittest.begin(ctx)

    for key, host in EXEC_HOSTS.items():
        properties = parse_konan_properties(_KONAN_PROPERTIES_2_4_21[key])
        deps = KOTLIN_NATIVE_DEPS[key]
        for target in host.targets:
            asserts.equals(
                env,
                sorted(deps.host + deps.targets[target]),
                konan_link_dependencies(properties, host.konan_host, target),
                "%s -> %s" % (key, target),
            )

    linux = parse_konan_properties(_KONAN_PROPERTIES_2_4_21["linux-x86_64"])
    asserts.equals(
        env,
        [_LIBFFI_LINUX, _LLDB_LINUX, _LLVM_LINUX, _GCC_X86_64],
        konan_link_dependencies(linux, "linux_x64", "linux_x64"),
    )

    # Only a Linux host has an emulator for another Linux target.
    asserts.equals(
        env,
        [_GCC_AARCH64, _LIBFFI_LINUX, _LLVM_LINUX, _QEMU_AARCH64],
        konan_link_dependencies(linux, "linux_x64", "linux_arm64"),
    )
    macos = parse_konan_properties(_KONAN_PROPERTIES_2_4_21["macos-aarch64"])
    asserts.equals(
        env,
        [_GCC_AARCH64, _LIBFFI_MACOS, _LLVM_MACOS],
        konan_link_dependencies(macos, "macos_arm64", "linux_arm64"),
    )
    for target in ["ios_arm64", "ios_simulator_arm64"]:
        asserts.equals(env, [_LIBFFI_MACOS, _LLVM_MACOS], konan_link_dependencies(macos, "macos_arm64", target))

    return unittest.end(env)

def _cross_check_accepts_the_bundles_test(ctx):
    """The bundles of every exec host pass the cross-check against konan.properties of 2.4.21."""
    env = unittest.begin(ctx)

    for key, host in EXEC_HOSTS.items():
        properties = parse_konan_properties(_KONAN_PROPERTIES_2_4_21[key])
        views = kotlin_native_bundle(key, host.targets).views
        asserts.equals(env, [], check_bundle_against_properties(properties, host.konan_host, views), key)

    return unittest.end(env)

def _cross_check_reports_differences_test(ctx):
    """The cross-check names every dependency konan.properties requires but the bundle lacks, and vice versa."""
    env = unittest.begin(ctx)

    properties = dict(parse_konan_properties(_KONAN_PROPERTIES_2_4_21["macos-aarch64"]))
    properties["dependencies.macos_arm64"] = "lldb-4-macos lldb-5-macos"
    views = dict(kotlin_native_bundle("macos-aarch64", ["linux_x64", "macos_arm64"]).views)
    views["linux_x64"] = views["linux_x64"] + ["zlib-extra"]
    asserts.equals(
        env,
        [
            "linux_x64: rules_kotlin stages zlib-extra, which konan.properties does not require",
            "macos_arm64: konan.properties requires lldb-5-macos, which rules_kotlin does not stage",
        ],
        check_bundle_against_properties(properties, "macos_arm64", views),
    )

    return unittest.end(env)

def _cross_check_needs_the_host_distribution_test(ctx):
    """A bundle checked against another host's distribution reports the LLVM variant that one expects."""
    env = unittest.begin(ctx)

    macos = parse_konan_properties(_KONAN_PROPERTIES_2_4_21["macos-aarch64"])
    views = kotlin_native_bundle("linux-x86_64", ["linux_arm64"]).views
    asserts.equals(
        env,
        [
            "linux_arm64: konan.properties requires %s, which rules_kotlin does not stage" % _LLVM_LINUX_DEV,
            "linux_arm64: rules_kotlin stages %s, which konan.properties does not require" % _LLVM_LINUX,
        ],
        check_bundle_against_properties(macos, "linux_x64", views),
    )

    return unittest.end(env)

def _bundle_stages_the_requested_targets_test(ctx):
    """A bundle holds the requested targets' dependencies, plus the host ones if any target is requested."""
    env = unittest.begin(ctx)

    ios = kotlin_native_bundle("macos-aarch64", ["ios_arm64"])
    asserts.equals(env, [_LIBFFI_MACOS, _LLVM_MACOS], sorted(ios.archives.keys()))
    asserts.equals(env, {"ios_arm64": [_LIBFFI_MACOS, _LLVM_MACOS]}, ios.views)
    asserts.equals(env, ["ios_simulator_arm64", "linux_arm64", "linux_x64", "macos_arm64"], ios.unstaged)

    linux = kotlin_native_bundle("linux-x86_64", ["ios_arm64"])
    asserts.equals(env, {}, linux.archives)
    asserts.equals(env, {}, linux.views)
    asserts.equals(env, ["linux_arm64", "linux_x64"], linux.unstaged)

    example = kotlin_native_bundle("macos-aarch64", ["linux_x64", "macos_arm64"])
    asserts.equals(env, [_LIBFFI_MACOS, _LLDB_MACOS, _LLVM_MACOS, _GCC_X86_64], sorted(example.archives.keys()))
    asserts.equals(env, [_LIBFFI_MACOS, _LLVM_MACOS, _GCC_X86_64], example.views["linux_x64"])
    asserts.equals(env, [_LIBFFI_MACOS, _LLDB_MACOS, _LLVM_MACOS], example.views["macos_arm64"])
    for name, archive in example.archives.items():
        asserts.equals(env, list(KOTLIN_NATIVE_ARCHIVES[name]), archive, name)

    return unittest.end(env)

def _bundle_stages_every_target_by_default_test(ctx):
    """With the default targets, every target of every exec host links."""
    env = unittest.begin(ctx)

    targets = collect_kotlin_native_config([]).targets
    for key, host in EXEC_HOSTS.items():
        bundle = kotlin_native_bundle(key, targets)
        asserts.equals(env, host.targets, sorted(bundle.views.keys()), key)
        asserts.equals(env, [], bundle.unstaged, key)

    return unittest.end(env)

def _config_defaults_test(ctx):
    """Without tags, the extension provides the pinned release and stages every konan target."""
    env = unittest.begin(ctx)

    config = collect_kotlin_native_config([_native_module("root", True), _native_module("dependency", False)])
    asserts.equals(env, KOTLIN_NATIVE_VERSION, config.version)
    asserts.equals(env, {key: spec.sha256 for key, spec in KOTLIN_NATIVE_PREBUILT.items()}, config.sha256)
    asserts.equals(env, sorted(KONAN_TARGETS.keys()), config.targets)

    return unittest.end(env)

def _config_reads_the_root_tags_test(ctx):
    """The root module's tags pick the release, its checksums and the targets to stage."""
    env = unittest.begin(ctx)

    config = collect_kotlin_native_config([
        _native_module(
            "root",
            True,
            version = [struct(version = "2.4.30", sha256 = {"macos-aarch64": "abc"})],
            targets = [struct(targets = ["macos_arm64", "linux_x64", "linux_x64"])],
        ),
        _native_module("dependency", False),
    ])
    asserts.equals(env, "2.4.30", config.version)
    asserts.equals(env, {"linux-x86_64": "", "macos-aarch64": "abc"}, config.sha256)
    asserts.equals(env, ["linux_x64", "macos_arm64"], config.targets)

    dist = kotlin_native_distribution("macos-aarch64", config.version, config.sha256["macos-aarch64"])
    asserts.equals(
        env,
        ["https://github.com/JetBrains/kotlin/releases/download/v2.4.30/kotlin-native-prebuilt-macos-aarch64-2.4.30.tar.gz"],
        dist.urls,
    )
    asserts.equals(env, "abc", dist.sha256)
    asserts.equals(env, "kotlin-native-prebuilt-macos-aarch64-2.4.30", dist.strip_prefix)

    return unittest.end(env)

def _config_keeps_the_pinned_checksums_test(ctx):
    """A version tag for the pinned release keeps the pinned checksums it does not override."""
    env = unittest.begin(ctx)

    config = collect_kotlin_native_config([
        _native_module("root", True, version = [struct(version = KOTLIN_NATIVE_VERSION, sha256 = {})]),
    ])
    asserts.equals(env, {key: spec.sha256 for key, spec in KOTLIN_NATIVE_PREBUILT.items()}, config.sha256)

    return unittest.end(env)

def _config_stages_no_target_on_request_test(ctx):
    """An empty targets tag stages no link bundle, for builds that only compile klibs."""
    env = unittest.begin(ctx)

    config = collect_kotlin_native_config([_native_module("root", True, targets = [struct(targets = [])])])
    asserts.equals(env, [], config.targets)
    for key, host in EXEC_HOSTS.items():
        bundle = kotlin_native_bundle(key, config.targets)
        asserts.equals(env, {}, bundle.archives, key)
        asserts.equals(env, host.targets, bundle.unstaged, key)

    return unittest.end(env)

def _compiler_build_file_declares_the_trees_test(ctx):
    """The distribution BUILD file exposes konan/, the stdlib and each target's platform libraries."""
    env = unittest.begin(ctx)

    build_file = kotlin_native_compiler_build_file(["linux_arm64", "linux_x64"])
    for expected in [
        'exports_files(["konan/konan.properties"])',
        'srcs = glob(["konan/**", "klib/common/stdlib/**", "klib/platform/linux_arm64/**", "klib/platform/linux_x64/**"])',
        'name = "konan"',
        'path = "klib/common/stdlib"',
        'name = "platform_linux_arm64"',
        'path = "klib/platform/linux_x64"',
    ]:
        asserts.true(env, expected in build_file, expected)
    for excluded in ['"bin/**"', '"klib/cache/**"', "macos_arm64"]:
        asserts.false(env, excluded in build_file, excluded)

    return unittest.end(env)

def _deps_build_file_declares_a_view_per_target_test(ctx):
    """The bundle BUILD file has a directory per archive and a view per target of its host."""
    env = unittest.begin(ctx)

    bundle = kotlin_native_bundle("macos-aarch64", ["linux_x64", "macos_arm64"])
    build_file = kotlin_native_deps_build_file(bundle.views, bundle.unstaged)
    asserts.true(env, '"kt_native_deps_view")' in build_file, build_file)
    asserts.true(env, 'name = "root"' in build_file, build_file)
    for name in bundle.archives:
        asserts.true(env, 'path = "dependencies/%s"' % name in build_file, name)
    for target in EXEC_HOSTS["macos-aarch64"].targets:
        asserts.true(env, 'name = "%s"' % target in build_file, target)
    asserts.true(
        env,
        'deps = [":%s", ":%s", ":%s"]' % (_LIBFFI_MACOS, _LLDB_MACOS, _LLVM_MACOS) in build_file,
        build_file,
    )
    asserts.equals(env, len(bundle.unstaged), build_file.count("staged = False"))

    nothing = kotlin_native_deps_build_file({}, ["linux_arm64", "linux_x64"])
    asserts.false(env, 'name = "root"' in nothing, nothing)
    asserts.equals(env, 2, nothing.count("staged = False"))

    return unittest.end(env)

exec_hosts_build_known_targets_test = unittest.make(_exec_hosts_build_known_targets_test)
every_target_has_an_exec_host_test = unittest.make(_every_target_has_an_exec_host_test)
apple_targets_only_on_macos_test = unittest.make(_apple_targets_only_on_macos_test)
only_apple_platforms_carry_the_apple_vendor_test = unittest.make(_only_apple_platforms_carry_the_apple_vendor_test)
ios_platforms_match_apple_support_test = unittest.make(_ios_platforms_match_apple_support_test)
apple_support_platforms_satisfy_the_targets_test = unittest.make(_apple_support_platforms_satisfy_the_targets_test)
tables_belong_to_the_default_release_test = unittest.make(_tables_belong_to_the_default_release_test)
deps_cover_every_exec_host_target_test = unittest.make(_deps_cover_every_exec_host_target_test)
archives_are_pinned_test = unittest.make(_archives_are_pinned_test)
parser_follows_java_properties_test = unittest.make(_parser_follows_java_properties_test)
parser_reads_konan_properties_test = unittest.make(_parser_reads_konan_properties_test)
link_dependencies_resolve_references_test = unittest.make(_link_dependencies_resolve_references_test)
link_dependencies_add_the_emulator_test = unittest.make(_link_dependencies_add_the_emulator_test)
link_dependencies_match_the_table_test = unittest.make(_link_dependencies_match_the_table_test)
cross_check_accepts_the_bundles_test = unittest.make(_cross_check_accepts_the_bundles_test)
cross_check_reports_differences_test = unittest.make(_cross_check_reports_differences_test)
cross_check_needs_the_host_distribution_test = unittest.make(_cross_check_needs_the_host_distribution_test)
bundle_stages_the_requested_targets_test = unittest.make(_bundle_stages_the_requested_targets_test)
bundle_stages_every_target_by_default_test = unittest.make(_bundle_stages_every_target_by_default_test)
config_defaults_test = unittest.make(_config_defaults_test)
config_reads_the_root_tags_test = unittest.make(_config_reads_the_root_tags_test)
config_keeps_the_pinned_checksums_test = unittest.make(_config_keeps_the_pinned_checksums_test)
config_stages_no_target_on_request_test = unittest.make(_config_stages_no_target_on_request_test)
compiler_build_file_declares_the_trees_test = unittest.make(_compiler_build_file_declares_the_trees_test)
deps_build_file_declares_a_view_per_target_test = unittest.make(_deps_build_file_declares_a_view_per_target_test)

def native_repositories_test_suite(name):
    unittest.suite(
        name,
        exec_hosts_build_known_targets_test,
        every_target_has_an_exec_host_test,
        apple_targets_only_on_macos_test,
        only_apple_platforms_carry_the_apple_vendor_test,
        ios_platforms_match_apple_support_test,
        apple_support_platforms_satisfy_the_targets_test,
        tables_belong_to_the_default_release_test,
        deps_cover_every_exec_host_target_test,
        archives_are_pinned_test,
        parser_follows_java_properties_test,
        parser_reads_konan_properties_test,
        link_dependencies_resolve_references_test,
        link_dependencies_add_the_emulator_test,
        link_dependencies_match_the_table_test,
        cross_check_accepts_the_bundles_test,
        cross_check_reports_differences_test,
        cross_check_needs_the_host_distribution_test,
        bundle_stages_the_requested_targets_test,
        bundle_stages_every_target_by_default_test,
        config_defaults_test,
        config_reads_the_root_tags_test,
        config_keeps_the_pinned_checksums_test,
        config_stages_no_target_on_request_test,
        compiler_build_file_declares_the_trees_test,
        deps_build_file_declares_a_view_per_target_test,
    )
