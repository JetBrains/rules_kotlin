"""The pure part of the kmp_maven module extension (kmp_maven.bzl): inputs, manifest, names and generated files.

kmp_maven.install declares the Maven coordinates of Kotlin Multiplatform libraries, as an
`implementation(...)` of commonMain does in Gradle, and the platforms of the build.
bazel-kmp-resolver (https://github.com/JetBrains/bazel-kmp-resolver) resolves them into a manifest
pinned in the workspace, whose schema version 2 is the contract of its docs/manifest.md. From the
manifest, the extension generates, without resolving anything itself:
- a repository per Maven module, `<hub>__<group>_<artifact>_<version>`, which downloads its klibs,
  aar or jar by URL and integrity when a build needs them;
- the hub repository `<hub>`: per library `<lib>`, a kt_klib_import per klib and konan target, a
  kt_jvm_import or an aar_import per Android and JVM variant, an android_library or a
  kt_jvm_library of exports per redirect variant (a variant without artifact, standing for its
  dependencies), each named `<lib>.<platform>`, and an alias `<lib>` that selects the variant of
  its consumer; or, when the manifest is missing or stale, a package that fails with the command
  pinning it;
- `@<hub>//pin`, which runs the resolver to write the manifest.

These functions take no repository or module context, so //src/test/starlark:kmp_maven_tests
tests them against an excerpt of a manifest of the resolver.
"""

# buildifier: disable=bzl-visibility
load("//kotlin/internal/native:targets.bzl", "KONAN_TARGETS")

# The --platform values of the resolver that rules_kotlin supports.
KMP_PLATFORMS = ["jvm", "android"] + sorted(KONAN_TARGETS.keys())

# The order of the platforms in a manifest: the konan targets, then android, then jvm.
PLATFORM_ORDER = sorted(KONAN_TARGETS.keys()) + ["android", "jvm"]

# The --platform values of the resolver that rules_kotlin does not support yet, and why.
_UNSUPPORTED_PLATFORMS = {
    "wasmjs": "rules_kotlin has no Kotlin/Wasm rules",
}

KMP_DEFAULT_REPOSITORIES = ["https://repo1.maven.org/maven2"]

# The schema version of the manifests rules_kotlin reads.
MANIFEST_SCHEMA_VERSION = 2

# The release of bazel-kmp-resolver the pin targets run, the first one with generate-bazel-manifest
# and the konan platforms, and the sha256 of its asset of each host, as its release page publishes
# them. kmp_maven.resolver(version, sha256) pins another release.
KMP_RESOLVER_VERSION = "0.4.0"
KMP_RESOLVER_SHA256 = {
    "linux-arm64": "46fa847253b380e8787cbb0d2093529e63b294bfbab3d21862c6ab3d7a993790",
    "linux-x64": "133e362e7827a0c60f100e45cd4a955fb877e552e38e81cbb8992fdc0f5a4b4a",
    "macos-arm64": "022a2f5d3049ccc1134faf52f0eff0faf7cb2258664ead386dcb0513ae46a5d8",
    "macos-x64": "de51cd44afae07ce8a907ae3eb099d36bbf5d13b9e00ec7f32ad110d6a994b68",
    "windows-x64": "b4ce8b8f8f5f399a1e23f1be29f3457505f28d16b4e56d39c67d10a02ceba0b5",
}

# The release asset of each host, by the keys of KMP_RESOLVER_SHA256.
KMP_RESOLVER_ASSETS = {
    "linux-arm64": "bazel-kmp-resolver-linux-arm64",
    "linux-x64": "bazel-kmp-resolver-linux-x64",
    "macos-arm64": "bazel-kmp-resolver-macos-arm64",
    "macos-x64": "bazel-kmp-resolver-macos-x64",
    "windows-x64": "bazel-kmp-resolver-windows-x64.exe",
}
KMP_RESOLVER_URL = "https://github.com/avan1235/bazel-kmp-resolver/releases/download/{version}/{asset}"

# The repository of the resolver binary, which the extension declares once, and its target.
KMP_RESOLVER_REPOSITORY = "bazel_kmp_resolver"
KMP_RESOLVER_LABEL = "@%s//:bazel-kmp-resolver" % KMP_RESOLVER_REPOSITORY

# The generated BUILD files load and select by canonical label, which resolves in any repository.
_JVM_BZL = str(Label("//kotlin:jvm.bzl"))
_NATIVE_BZL = str(Label("//kotlin:native.bzl"))
_ANDROID_BZL = str(Label("@rules_android//rules:rules.bzl"))
_SH_BINARY_BZL = str(Label("@rules_shell//shell:sh_binary.bzl"))

# The kinds of target of a hub by the .bzl file they load from, in the order of the load statements,
# each loaded when the hub has a target of the kind.
_LOADS = [
    (_ANDROID_BZL, ["aar_import", "android_library"]),
    (_JVM_BZL, ["kt_jvm_import", "kt_jvm_library"]),
    (_NATIVE_BZL, ["kt_klib_import"]),
]
_BASH_RUNFILES = str(Label("@bazel_tools//tools/bash/runfiles"))
_NATIVE = str(Label("//kotlin/native/platforms:native"))
_ANDROID = str(Label("@platforms//os:android"))
_DEFAULT = "//conditions:default"

_ALPHANUMERICS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

# The characters of a shell word that needs no quotes.
_SHELL_SAFE = _ALPHANUMERICS + "@%+=:,./-_"

def _native_setting(konan_target):
    return str(Label("//kotlin/native/platforms:native_" + konan_target))

def _unique(values):
    return {value: None for value in values}.keys()

def _is_coordinate(value, parts = 3):
    segments = value.split(":")
    return len(segments) == parts and all([segment and segment.strip() == segment and " " not in segment for segment in segments])

def library_target_name(name):
    """The name of the alias of a library: its group:artifact, every character but letters and digits replaced by `_`.

    Args:
      name: a group:artifact, or a group:artifact:version.

    Returns:
      The name, e.g. org_jetbrains_kotlinx_kotlinx_coroutines_core.
    """
    return "".join([character if character in _ALPHANUMERICS else "_" for character in name.elems()])

def variant_target_name(library_name, platform):
    """The name of the target of a variant of a library: `<lib>.<platform>`.

    The `.` keeps the targets of the variants apart from the aliases of the libraries, whose names
    are letters, digits and `_` only: a library whose artifact ends in `-android` or `-jvm`, as the
    platform artifact of an AndroidX multiplatform library does when a POM-only library depends on
    it (`androidx.datastore:datastore-preferences-android` next to
    `androidx.datastore:datastore-preferences`), would otherwise name the same target as the
    variant of the library it is named after.

    Args:
      library_name: the name of the library, from library_target_name.
      platform: the platform of the variant, `jvm`, `android` or a konan target; or `native`, for the
        alias of the klibs of the library.

    Returns:
      The name, e.g. org_jetbrains_kotlinx_kotlinx_coroutines_core.jvm.
    """
    return "%s.%s" % (library_name, platform)

def module_repository_name(hub, variant_id):
    """The repository of the files of a Maven module: `<hub>__<group>_<artifact>_<version>`.

    Args:
      hub: the name of the install.
      variant_id: the group:artifact:version of the module, the variantId of its variants.

    Returns:
      The repository name.
    """
    return hub + "__" + library_target_name(variant_id)

def workspace_path(label):
    """The path of a file of the root module in its workspace.

    Args:
      label: the Label of the file.

    Returns:
      The path, e.g. `kmp_manifest.json` for //:kmp_manifest.json.
    """
    return label.package + "/" + label.name if label.package else label.name

def install_error(name, artifacts, repositories, platforms, substitutions, manifest, extra_dependencies = {}, ignore_published_checksums = [], excluded_artifacts = []):
    """The error of the attributes of a kmp_maven.install tag, or None when they are valid.

    Args:
      name: the name of the install.
      artifacts: its Maven coordinates.
      repositories: its Maven repositories.
      platforms: its platforms.
      substitutions: its substitutions.
      manifest: the Label of its manifest.
      extra_dependencies: its extra dependencies, `{"group:artifact": ["group:artifact", ...]}`.
      ignore_published_checksums: the libraries whose published checksums are ignored, `group:artifact:version`.
      excluded_artifacts: the libraries the hub leaves out, `group:artifact`.

    Returns:
      The message of the error, or None.
    """
    prefix = "kmp_maven.install(name = \"%s\"): " % name
    if name == KMP_RESOLVER_REPOSITORY:
        return prefix + "the name is the one of the repository of the resolver; use another one"
    if not artifacts:
        return prefix + "it declares no artifacts"
    for artifact in artifacts:
        if not _is_coordinate(artifact):
            return prefix + "artifact '%s' is not group:artifact:version" % artifact
    if not repositories:
        return prefix + "it declares no repositories"
    if not platforms:
        return prefix + "it declares no platforms"
    for platform in platforms:
        if platform in _UNSUPPORTED_PLATFORMS:
            return prefix + "platform '%s' is not supported yet: %s" % (platform, _UNSUPPORTED_PLATFORMS[platform])
        if platform not in KMP_PLATFORMS:
            return prefix + "platform '%s' is not supported; use jvm, android or a konan target: %s" % (
                platform,
                ", ".join(sorted(KONAN_TARGETS.keys())),
            )
    for substitution in substitutions:
        substituted, separator, substitute = substitution.partition("=")
        if not separator or not _is_coordinate(substituted, parts = 2) or not _is_coordinate(substitute):
            return prefix + "substitution '%s' is not group:artifact=group:artifact:version" % substitution
    for library, dependencies in extra_dependencies.items():
        if not _is_coordinate(library, parts = 2):
            return prefix + "the library '%s' of extra_dependencies is not group:artifact" % library
        for dependency in dependencies:
            if not _is_coordinate(dependency, parts = 2):
                return prefix + "extra dependency '%s' of %s is not group:artifact" % (dependency, library)
    for library in ignore_published_checksums:
        if not _is_coordinate(library):
            return prefix + "the library '%s' of ignore_published_checksums is not group:artifact:version" % library
    for library in excluded_artifacts:
        if not _is_coordinate(library, parts = 2):
            return prefix + "the library '%s' of excluded_artifacts is not group:artifact" % library
        if library in extra_dependencies:
            return prefix + "the library '%s' is excluded, yet extra_dependencies names it" % library
        for dependencies in extra_dependencies.values():
            if library in dependencies:
                return prefix + "the library '%s' is excluded, yet extra_dependencies names it" % library
    if manifest.repo_name:
        return prefix + "the manifest %s is not a file of the root module, whose workspace the pin target writes it into" % manifest
    return None

def normalized_inputs(artifacts, repositories, platforms, substitutions, ignore_published_checksums = []):
    """The resolution inputs of an install, normalized as the resolver records them in the header of a manifest.

    Args:
      artifacts: the Maven coordinates.
      repositories: the Maven repositories.
      platforms: the platforms.
      substitutions: the substitutions, `group:artifact=group:artifact:version`.
      ignore_published_checksums: the libraries whose published checksums are ignored, `group:artifact:version`.

    Returns:
      struct(platforms, coordinates, repositories, substitutions, ignored_published_checksums): the
      platforms in platform order, the coordinates sorted and the repositories in their order, each
      without duplicates, the substitutions sorted, the last one of a substituted library winning,
      and the libraries whose published checksums are ignored sorted, without duplicates.
    """
    substitute_of = {}
    for substitution in substitutions:
        substituted, _, substitute = substitution.partition("=")
        substitute_of[substituted] = substitute
    return struct(
        platforms = [platform for platform in PLATFORM_ORDER if platform in platforms],
        coordinates = sorted(_unique(artifacts)),
        repositories = list(_unique(repositories)),
        substitutions = sorted(["%s=%s" % (substituted, substitute) for substituted, substitute in substitute_of.items()]),
        ignored_published_checksums = sorted(_unique(ignore_published_checksums)),
    )

def resolver_release(version = None, sha256 = {}):
    """The release of bazel-kmp-resolver the pin targets run.

    Args:
      version: the version of the kmp_maven.resolver tag, or None without tag.
      sha256: the checksums by host of the tag.

    Returns:
      struct(version, sha256): KMP_RESOLVER_VERSION and its checksums without tag; otherwise the
      version of the tag, with its checksums over those rules_kotlin pins for the same version.
    """
    if version == None:
        return struct(version = KMP_RESOLVER_VERSION, sha256 = dict(KMP_RESOLVER_SHA256))
    pinned = KMP_RESOLVER_SHA256 if version == KMP_RESOLVER_VERSION else {}
    return struct(version = version, sha256 = dict(pinned, **sha256))

def collect_kmp_maven_config(modules):
    """Collects the install and resolver tags of the kmp_maven extension.

    Only the root module may declare the tags, as the pin targets write the manifests into its
    workspace: each install name once, and the resolver tag at most once.

    Args:
      modules: the modules of the module extension context.

    Returns:
      struct(installs, resolver): the installs in their order, each a struct(name, inputs, manifest,
      manifest_path, fetch_sources, extra_dependencies, excluded_artifacts) with the normalized
      inputs, and the resolver release (see resolver_release).
    """
    installs = []
    names = {}
    resolver_tag = None
    for mod in modules:
        for tag in mod.tags.install:
            if not mod.is_root:
                fail("kmp_maven.install is available to the root module only; module %s declares %s" % (mod.name, tag.name))
            if tag.name in names:
                fail("kmp_maven.install %s is declared twice" % tag.name)
            names[tag.name] = True
            extra_dependencies = getattr(tag, "extra_dependencies", {})
            ignore_published_checksums = getattr(tag, "ignore_published_checksums", [])
            excluded_artifacts = getattr(tag, "excluded_artifacts", [])
            error = install_error(tag.name, tag.artifacts, tag.repositories, tag.platforms, tag.substitutions, tag.manifest, extra_dependencies, ignore_published_checksums, excluded_artifacts)
            if error:
                fail(error)
            installs.append(struct(
                name = tag.name,
                inputs = normalized_inputs(tag.artifacts, tag.repositories, tag.platforms, tag.substitutions, ignore_published_checksums),
                manifest = tag.manifest,
                manifest_path = workspace_path(tag.manifest),
                fetch_sources = tag.fetch_sources,
                extra_dependencies = {library: sorted(_unique(dependencies)) for library, dependencies in extra_dependencies.items()},
                excluded_artifacts = sorted(_unique(excluded_artifacts)),
            ))
        for tag in mod.tags.resolver:
            if not mod.is_root:
                fail("kmp_maven.resolver is available to the root module only; module %s declares %s" % (mod.name, tag.version))
            if resolver_tag != None:
                fail("kmp_maven.resolver is declared twice")
            for host in tag.sha256:
                if host not in KMP_RESOLVER_ASSETS:
                    fail("kmp_maven.resolver: unsupported host %s in sha256 (supported: %s)" %
                         (host, ", ".join(sorted(KMP_RESOLVER_ASSETS.keys()))))
            resolver_tag = tag
    if resolver_tag == None:
        return struct(installs = installs, resolver = resolver_release())
    return struct(installs = installs, resolver = resolver_release(resolver_tag.version, resolver_tag.sha256))

def decode_manifest(content):
    """Decodes the content of a manifest file.

    Args:
      content: the content of the file, "" when it is missing.

    Returns:
      None for an empty file, the decoded JSON value otherwise, and False when it is not JSON.
    """
    if not content.strip():
        return None
    return json.decode(content, default = False)

def manifest_problem(hub, manifest_path, manifest, inputs):
    """What makes the manifest of an install unusable, or None when it is pinned for the inputs of the install.

    The resolver records the normalized inputs of a manifest in its header, so a manifest is stale
    when one of them differs from those of the install. Comparing them needs no resolver, and the
    inputsHash of the manifest, a SHA-256 digest, is not computable in Starlark.

    Args:
      hub: the name of the install.
      manifest_path: the path of the manifest in the workspace.
      manifest: the decoded manifest (see decode_manifest).
      inputs: the normalized inputs of the install (see normalized_inputs).

    Returns:
      The message, which tells how to pin the manifest, or None.
    """
    pin = "bazel run @%s//pin" % hub
    if manifest == None:
        return "@%s: the manifest %s is empty or missing; run '%s' to resolve %d artifacts for %s, then commit it" % (
            hub,
            manifest_path,
            pin,
            len(inputs.coordinates),
            ", ".join(inputs.platforms),
        )
    if type(manifest) != "dict":
        return "@%s: the manifest %s is not a JSON object, as the manifests of bazel-kmp-resolver are; run '%s' and commit it" % (
            hub,
            manifest_path,
            pin,
        )
    version = manifest.get("schemaVersion")
    if version != MANIFEST_SCHEMA_VERSION:
        return "@%s: the manifest %s has schemaVersion %s; rules_kotlin reads version %d: run '%s' and commit it" % (
            hub,
            manifest_path,
            version,
            MANIFEST_SCHEMA_VERSION,
            pin,
        )
    for field, declared, default in [
        ("askedPlatforms", inputs.platforms, None),
        ("askedCoordinates", inputs.coordinates, None),
        ("askedRepositories", inputs.repositories, None),
        ("askedSubstitutions", inputs.substitutions, None),
        # the resolver leaves the field out of the manifests ignoring no published checksum
        ("askedIgnoredPublishedChecksums", inputs.ignored_published_checksums, []),
    ]:
        recorded = manifest.get(field, default)
        if recorded != declared:
            return "@%s: the manifest %s is stale: its %s is %s, but kmp_maven.install(name = \"%s\") declares %s; run '%s' and commit it" % (
                hub,
                manifest_path,
                field,
                json.encode(recorded),
                hub,
                json.encode(declared),
                pin,
            )
    return None

def _platform(variant):
    """The platform of a variant: its konan target, android or jvm; None for a platform rules_kotlin does not support."""
    kind = variant.get("type")
    platform = variant.get("platform") if kind in ("klib", "redirect") else kind
    return platform if platform in PLATFORM_ORDER else None

def manifest_libraries(manifest):
    """The libraries of a manifest, by the name of their targets.

    The variants of a library are the ones of the platforms rules_kotlin supports: the `wasm_js`
    ones are left out. The versions of a group:artifact are one library, as each platform is
    resolved once, so a group:artifact has at most one variant per platform.

    Args:
      manifest: the decoded manifest.

    Returns:
      struct(libraries, error): a dict of target name to struct(name, group_artifact, ids,
      variants), the variants a dict of platform to variant in platform order; and the message of
      two libraries naming the same targets or having a variant of the same platform, or None.
    """
    libraries = {}
    for library_id in sorted(manifest.get("libraries", {}).keys()):
        variants = [variant for variant in manifest["libraries"][library_id].get("variants", []) if _platform(variant)]
        if not variants:
            continue
        group_artifact = library_id.rpartition(":")[0]
        name = library_target_name(group_artifact)
        library = libraries.get(name)
        if library == None:
            library = struct(name = name, group_artifact = group_artifact, ids = [], variants = {})
            libraries[name] = library
        elif library.group_artifact != group_artifact:
            return struct(libraries = {}, error = "libraries %s and %s both name the target %s" % (library.ids[0], library_id, name))
        library.ids.append(library_id)
        for variant in variants:
            platform = _platform(variant)
            if platform in library.variants:
                return struct(
                    libraries = {},
                    error = "libraries %s and %s both have a variant for %s" % (library.ids[0], library_id, platform),
                )
            library.variants[platform] = variant
    for library in libraries.values():
        ordered = {platform: library.variants[platform] for platform in PLATFORM_ORDER if platform in library.variants}
        library.variants.clear()
        library.variants.update(ordered)
    return struct(libraries = libraries, error = None)

def _file_name(artifact):
    """The name of the file of a Maven artifact, the last segment of its URLs."""
    return artifact["urls"][0].rpartition("/")[2]

def _variant_artifacts(variant, fetch_sources):
    """The Maven artifacts of a variant to download: its klibs, aar or jar, and its sources jar when fetched; none for a redirect."""
    kind = variant["type"]
    if kind == "klib":
        artifacts = [klib["artifact"] for klib in variant["klibs"]]
    elif kind == "android":
        artifacts = [variant["artifact"]]
    elif kind == "jvm":
        artifacts = [variant["jar"]]
    else:
        artifacts = []
    if fetch_sources and variant.get("sourceJar"):
        artifacts.append(variant["sourceJar"])
    return artifacts

def module_repositories(hub, manifest, fetch_sources):
    """The repositories of the Maven modules of a manifest, with the files each downloads.

    Args:
      hub: the name of the install.
      manifest: the decoded manifest.
      fetch_sources: whether the sources jars are downloaded too.

    Returns:
      A dict of repository name to a dict of file name to struct(integrity, urls): per Maven module
      (variantId) of the variants of the supported platforms, the klibs of a klib variant, the
      artifact of an android one and the jar of a jvm one, with their sources jars when
      fetch_sources. The android and jvm variants of a module share its repository. A redirect
      variant has no file, so a module of redirects alone has no repository.
    """
    repositories = {}
    for library in manifest_libraries(manifest).libraries.values():
        for variant in library.variants.values():
            artifacts = _variant_artifacts(variant, fetch_sources)
            if not artifacts:
                continue
            files = repositories.setdefault(module_repository_name(hub, variant["variantId"]), {})
            for artifact in artifacts:
                files[_file_name(artifact)] = struct(integrity = artifact["integrity"], urls = artifact["urls"])
    return {name: repositories[name] for name in sorted(repositories.keys())}

def module_build_file(file_names):
    """The BUILD file of the repository of a Maven module, which exports its files.

    Args:
      file_names: the names of the files of the repository.

    Returns:
      The content of the BUILD file.
    """
    return "\n".join([
        "# The files of a Maven module of kmp_maven. Generated by rules_kotlin.",
        "exports_files(",
        "    %s," % repr(sorted(file_names)),
        "    visibility = [\"//visibility:public\"],",
        ")",
        "",
    ])

def _value(value):
    """A Starlark literal of a string or a list of strings, for an attribute of a BUILD file."""
    if type(value) != "list":
        return repr(value)
    if len(value) == 1:
        return "[%s]" % repr(value[0])
    return "[\n" + "".join(["        %s,\n" % repr(item) for item in value]) + "    ]"

def _target(kind, name, attrs):
    """A target of a BUILD file, `kind(name = name, ...)`, with the attributes that have a value."""
    lines = ["%s(" % kind, "    name = %s," % repr(name)]
    for key, value in attrs:
        if value:
            lines.append("    %s = %s," % (key, _value(value)))
    lines.append(")")
    return "\n".join(lines)

def _select_alias(name, branches, no_match_error):
    """An alias of a select() of the branches, (condition, target) pairs."""
    lines = [
        "alias(",
        "    name = %s," % repr(name),
        "    actual = select(",
        "        {",
    ]
    lines.extend(["            %s: %s," % (repr(condition), repr(actual)) for condition, actual in branches])
    lines.append("        },")
    if no_match_error:
        lines.append("        no_match_error = %s," % repr(no_match_error))
    lines.extend(["    ),", ")"])
    return "\n".join(lines)

def _repository_file(hub, variant, artifact):
    return "@%s//:%s" % (module_repository_name(hub, variant["variantId"]), _file_name(artifact))

def _library_targets(hub, library, variant_of, fetch_sources, extra_dependencies = []):
    """The targets of a library, as (name, BUILD text) pairs: its imports, per variant, and its aliases.

    The extra dependencies, group:artifact each, are deps of every variant of the library, for its
    platform, as the dependencies of the metadata of the variant are: the dependencies its metadata
    omits, which the consumer declares (see hub_contents).
    """
    targets = []

    def dependencies_of(group_artifacts, platform):
        names = [library_target_name(group_artifact) for group_artifact in group_artifacts]
        return sorted([":" + variant_target_name(name, platform) for name in _unique(names) if variant_of(name, platform)])

    def aar_exports_of(group_artifacts):
        # The exports of an aar_import can only be imports: an android redirect is replaced by the
        # targets it forwards to (all its dependencies, as its android_library exports them),
        # following the redirects among them.
        names = {}
        pending = [library_target_name(group_artifact) for group_artifact in group_artifacts]
        seen = {}
        for _ in range(len(pending) + 10000):
            if not pending:
                break
            name = pending.pop()
            if name in seen:
                continue
            seen[name] = True
            variant = variant_of(name, "android")
            if not variant:
                continue
            if variant["type"] == "redirect":
                pending.extend([
                    library_target_name(group_artifact)
                    for group_artifact in variant.get("dependencies", []) + variant.get("exportedDependencies", [])
                ])
            else:
                names[name] = True
        return sorted([":" + variant_target_name(name, "android") for name in names])

    for platform, variant in library.variants.items():
        name = variant_target_name(library.name, platform)
        dependencies = variant.get("dependencies", []) + extra_dependencies
        exported = variant.get("exportedDependencies", [])
        if variant["type"] == "redirect":
            # android_library has no runtime_deps, so it exports every dependency; kt_jvm_library,
            # which unlike java_library forwards KtJvmInfo too, keeps the runtime-only ones in
            # runtime_deps. An aar_import exports the imports a redirect stands for (aar_exports_of).
            if platform == "android":
                targets.append((name, _target("android_library", name, [
                    ("exports", dependencies_of(dependencies + exported, platform)),
                ])))
            else:
                targets.append((name, _target("kt_jvm_library", name, [
                    ("exports", dependencies_of(exported, platform)),
                    ("runtime_deps", dependencies_of(dependencies, platform)),
                ])))
        elif variant["type"] == "klib":
            # The main klib is first; the cinterop klibs are imports of their own, deps of the main one.
            cinterops = []
            for position, klib in enumerate(variant["klibs"][1:]):
                cinterop = "%s.cinterop_%d" % (name, position)
                cinterops.append(":" + cinterop)
                targets.append((cinterop, _target("kt_klib_import", cinterop, [
                    ("klib", _repository_file(hub, variant, klib["artifact"])),
                    ("konan_target", platform),
                ])))
            targets.append((name, _target("kt_klib_import", name, [
                ("klib", _repository_file(hub, variant, variant["klibs"][0]["artifact"])),
                ("konan_target", platform),
                ("exports", dependencies_of(exported, platform)),
                ("deps", cinterops + dependencies_of(dependencies, platform)),
            ])))
        else:
            is_aar = variant["type"] == "android" and variant.get("packaging") == "aar"
            if is_aar:
                kind, files = "aar_import", ("aar", _repository_file(hub, variant, variant["artifact"]))
            else:
                artifact = variant["artifact"] if variant["type"] == "android" else variant["jar"]
                kind, files = "kt_jvm_import", ("jars", [_repository_file(hub, variant, artifact)])
            source_jar = variant.get("sourceJar") if fetch_sources else None
            targets.append((name, _target(kind, name, [
                files,
                ("srcjar", _repository_file(hub, variant, source_jar) if source_jar else None),
                ("exports", aar_exports_of(exported) if is_aar else dependencies_of(exported, platform)),
                ("deps", dependencies_of(dependencies + exported, platform)),
            ])))

    platforms = list(library.variants.keys())
    if platforms == ["jvm"]:
        targets.append((library.name, _target("alias", library.name, [("actual", ":" + variant_target_name(library.name, "jvm"))])))
        return targets

    resolved = "kmp_maven.install(name = \"%s\") resolved it for %s" % (hub, ", ".join(platforms))
    konan_targets = [platform for platform in platforms if platform in KONAN_TARGETS]
    branches = []
    if konan_targets:
        native = variant_target_name(library.name, "native")
        branches.append((_NATIVE, ":" + native))
        targets.append((native, _select_alias(
            native,
            [(_native_setting(target), ":" + variant_target_name(library.name, target)) for target in konan_targets],
            ("%s has no klib for the konan target of this Kotlin/Native target: %s. Add the target to the platforms " +
             "of the install and run 'bazel run @%s//pin', if the library publishes it.") % (library.group_artifact, resolved, hub),
        )))
    if "android" in library.variants:
        branches.append((_ANDROID, ":" + variant_target_name(library.name, "android")))
    if "jvm" in library.variants:
        branches.append((_DEFAULT, ":" + variant_target_name(library.name, "jvm")))
    targets.append((library.name, _select_alias(
        library.name,
        branches,
        None if "jvm" in library.variants else (
            "%s has no variant for this target: %s. A Kotlin/Native target takes its klib, an Android target its " +
            "android variant, any other target its jvm variant."
        ) % (library.group_artifact, resolved),
    )))
    return targets

def hub_contents(hub, manifest_path, manifest, fetch_sources, extra_dependencies = {}, excluded_artifacts = []):
    """The BUILD file of the hub repository of an install whose manifest is pinned, or why there is none.

    Per library `<lib>`, from its variants (the targets of the variants are `<lib>.<platform>`, see
    variant_target_name):
    - a kt_klib_import `<lib>.<t>` of the main klib of konan target `<t>`, and a kt_klib_import
      `<lib>.<t>.cinterop_<n>` per cinterop klib, in the deps of the main one;
    - an aar_import, or a kt_jvm_import for a jar, `<lib>.android`, and a kt_jvm_import `<lib>.jvm`;
    - for a redirect variant, a variant without artifact standing for its dependencies (the Android
      variants of the JetBrains Compose libraries redirect to the AndroidX ones, a POM-only library
      aggregates others), an android_library `<lib>.android` exporting its dependencies, or a
      kt_jvm_library `<lib>.jvm` without sources exporting the exported ones and keeping the others
      at runtime;
    - with klib variants, the alias `<lib>.native`, which selects `<lib>.<t>` on
      @rules_kotlin//kotlin/native/platforms:native_<t>;
    - the alias `<lib>`, which selects `<lib>.native` for the Kotlin/Native rules
      (@rules_kotlin//kotlin/native/platforms:native), `<lib>.android` on @platforms//os:android and
      `<lib>.jvm` by default; of `<lib>.jvm` alone for a JVM library.

    A dependency of a variant is the target of the same platform of its library: the exported ones
    are the exports of the import, and also its deps for the JVM and Android imports. The extra
    dependencies of a library, the ones its metadata omits, are deps of each of its variants as the
    dependencies of the metadata are; they must be libraries of the manifest.

    An excluded library has no targets, and the variants of the other libraries have no dep on it
    (the `exclude` of a Gradle configuration): e.g. the `jna-jpms` the natives of vlcj depend on,
    which carries the packages of the `jna` another library depends on. Its own dependencies go
    with it, unless another library depends on them; it must be a library of the manifest.

    Args:
      hub: the name of the install.
      manifest_path: the path of the manifest in the workspace.
      manifest: the decoded manifest, pinned for the inputs of the install (see manifest_problem).
      fetch_sources: whether the sources jars are the srcjar of the JVM and Android imports.
      extra_dependencies: the extra dependencies of the install, `{"group:artifact": ["group:artifact", ...]}`.
      excluded_artifacts: the libraries the hub leaves out, `group:artifact` each.

    Returns:
      struct(build_file, error): the content of the BUILD file, or the message of two libraries
      naming the same target, or of an extra dependency or an exclusion naming a library the
      manifest lacks.
    """
    prefix = "kmp_maven.install(name = \"%s\"): the manifest %s has " % (hub, manifest_path)
    collected = manifest_libraries(manifest)
    if collected.error:
        return struct(build_file = None, error = prefix + collected.error)
    libraries = dict(collected.libraries)
    for group_artifact in excluded_artifacts:
        name = library_target_name(group_artifact)
        if name not in libraries:
            return struct(
                build_file = None,
                error = prefix + "no library %s, which excluded_artifacts names; only a library of the manifest, a dependency of an artifact of the install, can be excluded" % group_artifact,
            )
        libraries.pop(name)

    def variant_of(name, platform):
        return libraries[name].variants.get(platform) if name in libraries else None

    extra_of = {}
    for group_artifact, dependencies in extra_dependencies.items():
        for coordinate in [group_artifact] + dependencies:
            if library_target_name(coordinate) not in libraries:
                return struct(
                    build_file = None,
                    error = prefix + "no library %s, which extra_dependencies names; add it to the artifacts of the install and run 'bazel run @%s//pin'" % (coordinate, hub),
                )
        extra_of[library_target_name(group_artifact)] = dependencies

    owners = {}
    sections = []
    kinds = {}
    for name in sorted(libraries.keys()):
        library = libraries[name]
        texts = ["# " + ", ".join(library.ids)]
        for target, text in _library_targets(hub, library, variant_of, fetch_sources, extra_of.get(name, [])):
            if target in owners:
                return struct(
                    build_file = None,
                    error = prefix + "libraries %s and %s that both name the target %s" % (owners[target], library.group_artifact, target),
                )
            owners[target] = library.group_artifact
            kinds[text.partition("(")[0]] = True
            texts.append(text)
        sections.append("\n".join(texts[:2]) + "".join(["\n\n" + text for text in texts[2:]]))

    lines = [
        "# The libraries of kmp_maven.install(name = \"%s\"), from the manifest %s. Generated by rules_kotlin." % (hub, manifest_path),
    ]
    for bzl, bzl_kinds in _LOADS:
        loaded = [kind for kind in bzl_kinds if kind in kinds]
        if loaded:
            lines.append("load(%s, %s)" % (repr(bzl), ", ".join([repr(kind) for kind in loaded])))
    lines.extend(["", "package(default_visibility = [\"//visibility:public\"])"])
    return struct(
        build_file = "\n".join(lines) + "".join(["\n\n" + section for section in sections]) + "\n",
        error = None,
    )

def hub_build_file(hub, manifest_path, manifest, fetch_sources, extra_dependencies = {}, excluded_artifacts = []):
    """The BUILD file of the hub repository of an install whose manifest is pinned (see hub_contents).

    Args:
      hub: the name of the install.
      manifest_path: the path of the manifest in the workspace.
      manifest: the decoded manifest, pinned for the inputs of the install (see manifest_problem).
      fetch_sources: whether the sources jars are the srcjar of the JVM and Android imports.
      extra_dependencies: the extra dependencies of the install (see hub_contents).
      excluded_artifacts: the libraries the hub leaves out (see hub_contents).

    Returns:
      The content of the BUILD file. Fails when two libraries name the same target, or when an extra
      dependency or an exclusion names a library the manifest lacks.
    """
    contents = hub_contents(hub, manifest_path, manifest, fetch_sources, extra_dependencies, excluded_artifacts)
    if contents.error:
        fail(contents.error)
    return contents.build_file

def unpinned_build_file(hub, problem):
    """The BUILD file of the hub repository of an install whose manifest is not pinned: it fails with the problem.

    Args:
      hub: the name of the install.
      problem: the message of manifest_problem.

    Returns:
      The content of the BUILD file.
    """
    return "\n".join([
        "# kmp_maven.install(name = \"%s\") has no manifest pinned for its inputs: its targets fail with how to pin" % hub,
        "# it, which @%s//pin does. Generated by rules_kotlin." % hub,
        "fail(%s)" % repr(problem),
        "",
    ])

def pin_build_file(hub, resolver):
    """The BUILD file of `@<hub>//pin`, the sh_binary pinning the manifest of the install.

    Args:
      hub: the name of the install.
      resolver: the label of the resolver binary.

    Returns:
      The content of the BUILD file.
    """
    return "\n".join([
        "# bazel run @%s//pin: pins the manifest of the install with bazel-kmp-resolver. Generated by rules_kotlin." % hub,
        "load(%s, \"sh_binary\")" % repr(_SH_BINARY_BZL),
        "",
        "sh_binary(",
        "    name = \"pin\",",
        "    srcs = [\"pin.sh\"],",
        "    args = [%s]," % repr("$(rlocationpath %s)" % resolver),
        "    data = [%s]," % repr(resolver),
        "    deps = [%s]," % repr(_BASH_RUNFILES),
        ")",
        "",
    ])

_PIN_SCRIPT = """\
#!/usr/bin/env bash
# Pins the manifest of kmp_maven.install(name = "%{hub}"): resolves its artifacts with
# bazel-kmp-resolver and writes %{manifest_path} into the workspace. Generated by rules_kotlin.
# Usage: bazel run @%{hub}//pin [-- <more options of generate-bazel-manifest>]

# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \\
  source "$0.runfiles/$f" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
  { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---

set -euo pipefail

if [[ -z "${BUILD_WORKSPACE_DIRECTORY:-}" ]]; then
  echo >&2 "ERROR: run 'bazel run @%{hub}//pin', which writes the manifest into the workspace"
  exit 1
fi

resolver="$(rlocation "$1")"
shift
manifest="$BUILD_WORKSPACE_DIRECTORY"/%{manifest_word}
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/rules_kotlin/bazel-kmp-resolver"

"$resolver" generate-bazel-manifest \\
  --output-manifest-file="$manifest" \\
  --cache-dir="$cache_dir" \\
  %{options} \\
  "$@"

echo "Wrote $manifest for kmp_maven.install(name = \\"%{hub}\\"): commit it."
"""

def _shell_word(value):
    """The value as a shell word: as it is when it is safe, otherwise single-quoted."""
    if value and all([character in _SHELL_SAFE for character in value.elems()]):
        return value
    return "'" + value.replace("'", "'\\''") + "'"

def pin_script(hub, manifest_path, inputs):
    """The script of `@<hub>//pin`, which runs `bazel-kmp-resolver generate-bazel-manifest` with the inputs of an install.

    The script takes the runfiles path of the resolver binary as its first argument, and passes the
    others to the resolver. It writes the manifest at its path in the workspace of `bazel run`. The
    resolver caches the Maven metadata and artifacts it downloads in the cache home of the user.

    Args:
      hub: the name of the install.
      manifest_path: the path of the manifest in the workspace.
      inputs: the normalized inputs of the install (see normalized_inputs).

    Returns:
      The content of the script.
    """
    options = (
        ["--coordinate=" + coordinate for coordinate in inputs.coordinates] +
        ["--repository=" + repository for repository in inputs.repositories] +
        ["--platform=" + platform for platform in inputs.platforms] +
        ["--substitution=" + substitution for substitution in inputs.substitutions] +
        ["--ignore-published-checksums=" + library for library in inputs.ignored_published_checksums]
    )
    return (
        _PIN_SCRIPT
            .replace("%{hub}", hub)
            .replace("%{manifest_path}", manifest_path)
            .replace("%{manifest_word}", _shell_word(manifest_path))
            .replace("%{options}", " \\\n  ".join([_shell_word(option) for option in options]))
    )

def resolver_asset(os_name, arch, version):
    """The release asset of bazel-kmp-resolver of a host.

    Args:
      os_name: the OS of the host, as repository_ctx.os.name, e.g. "mac os x", "linux" or
        "windows 11".
      arch: the CPU of the host, as repository_ctx.os.arch, e.g. "aarch64", "amd64" or "x86_64".
      version: the release.

    Returns:
      struct(host, file_name, url, executable), the host being a key of KMP_RESOLVER_ASSETS and the
      executable the name to give the binary on the host; None for a host without asset.
    """
    os_name = os_name.lower()
    if os_name.startswith("mac os"):
        os = "macos"
    elif os_name.startswith("linux"):
        os = "linux"
    elif os_name.startswith("windows"):
        os = "windows"
    else:
        return None
    cpu = {"aarch64": "arm64", "amd64": "x64", "arm64": "arm64", "x86_64": "x64"}.get(arch.lower())
    host = "%s-%s" % (os, cpu)
    if host not in KMP_RESOLVER_ASSETS:
        return None
    asset = KMP_RESOLVER_ASSETS[host]
    return struct(
        host = host,
        file_name = asset,
        url = KMP_RESOLVER_URL.format(version = version, asset = asset),
        executable = "bazel-kmp-resolver.exe" if os == "windows" else "bazel-kmp-resolver",
    )

def resolver_download(os_name, arch, release):
    """The download of the resolver binary of a host: the asset of the release, checked against its sha256.

    Args:
      os_name: the OS of the host, as repository_ctx.os.name.
      arch: the CPU of the host, as repository_ctx.os.arch.
      release: the release of the resolver (see resolver_release).

    Returns:
      struct(url, sha256, executable, error): what to download and the name of the binary, or the
      message of why there is nothing to download.
    """
    asset = resolver_asset(os_name, arch, release.version)
    if asset == None:
        return struct(url = None, sha256 = None, executable = None, error = "bazel-kmp-resolver publishes no binary for %s on %s: its releases have one for %s" % (
            os_name,
            arch,
            ", ".join(sorted(KMP_RESOLVER_ASSETS.keys())),
        ))
    sha256 = release.sha256.get(asset.host)
    if not sha256:
        return struct(url = None, sha256 = None, executable = None, error = "bazel-kmp-resolver %s has no pinned checksum for %s: add the sha256 of its asset %s to kmp_maven.resolver(version, sha256)" % (
            release.version,
            asset.host,
            asset.file_name,
        ))
    return struct(url = asset.url, sha256 = sha256, executable = asset.executable, error = None)
