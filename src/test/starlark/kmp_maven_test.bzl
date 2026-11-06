"""Unit tests for the pure helpers of the kmp_maven extension (kmp_maven_impl.bzl), against a manifest of bazel-kmp-resolver."""

load(
    "@bazel_skylib//lib:unittest.bzl",
    "asserts",
    "unittest",
)

# buildifier: disable=bzl-visibility
load("//kotlin/internal/native:targets.bzl", "KONAN_TARGETS")
load(
    "//src/main/starlark/core/repositories:kmp_maven_impl.bzl",
    "KMP_DEFAULT_REPOSITORIES",
    "KMP_PLATFORMS",
    "KMP_RESOLVER_ASSETS",
    "KMP_RESOLVER_LABEL",
    "KMP_RESOLVER_SHA256",
    "KMP_RESOLVER_VERSION",
    "PLATFORM_ORDER",
    "collect_kmp_maven_config",
    "decode_manifest",
    "hub_contents",
    "install_error",
    "library_target_name",
    "manifest_libraries",
    "manifest_problem",
    "module_build_file",
    "module_repositories",
    "module_repository_name",
    "normalized_inputs",
    "pin_build_file",
    "pin_script",
    "resolver_asset",
    "resolver_download",
    "resolver_release",
    "unpinned_build_file",
    "workspace_path",
)
load(":kmp_maven_manifest.bzl", "COROUTINES_MANIFEST")

_HUB = "kmp_maven"
_COROUTINES = "org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2"
_PIN = "run 'bazel run @kmp_maven//pin'"

# The targets of the libraries of the manifest, and the repositories of their Maven modules.
_COROUTINES_LIB = "org_jetbrains_kotlinx_kotlinx_coroutines_core"
_ATOMICFU_LIB = "org_jetbrains_kotlinx_atomicfu"
_ATOMICFU_LINUX_REPO = "kmp_maven__org_jetbrains_kotlinx_atomicfu_linuxx64_0_26_1"
_COROUTINES_JVM_REPO = "kmp_maven__org_jetbrains_kotlinx_kotlinx_coroutines_core_jvm_1_10_2"
_COROUTINES_LINUX_REPO = "kmp_maven__org_jetbrains_kotlinx_kotlinx_coroutines_core_linuxx64_1_10_2"

# The labels of the generated BUILD files, as canonical as the helpers write them.
_JVM_BZL = str(Label("//kotlin:jvm.bzl"))
_NATIVE_BZL = str(Label("//kotlin:native.bzl"))
_ANDROID_BZL = str(Label("@rules_android//rules:rules.bzl"))
_NATIVE = str(Label("//kotlin/native/platforms:native"))
_ANDROID = str(Label("@platforms//os:android"))

def _native_setting(konan_target):
    return str(Label("//kotlin/native/platforms:native_" + konan_target))

def _manifest():
    return decode_manifest(COROUTINES_MANIFEST)

def _inputs(
        artifacts = [_COROUTINES],
        repositories = KMP_DEFAULT_REPOSITORIES,
        platforms = ["jvm", "android", "linux_x64", "ios_arm64"],
        substitutions = []):
    """The normalized inputs of an install; by default the ones the manifest is pinned for."""
    return normalized_inputs(artifacts, repositories, platforms, substitutions)

def _artifact(file_name):
    return {
        "integrity": "sha256-" + file_name,
        "urls": ["https://repo.example/maven/" + file_name],
    }

def _variant(kind, library_id, variant_id, dependencies = [], exported = [], **fields):
    """A variant of a synthetic manifest: its fields of every type, and the ones of its type."""
    return dict(
        type = kind,
        id = library_id,
        variantId = variant_id,
        dependencies = dependencies,
        exportedDependencies = exported,
        sourceJar = None,
        **fields
    )

def _synthetic_manifest(libraries):
    """A manifest of libraries given as a dict of ID to variants."""
    return {
        "libraries": {library_id: {"id": library_id, "variants": variants} for library_id, variants in libraries.items()},
        "schemaVersion": 2,
    }

def _jvm_variant(library_id, variant_id, file_name, **kwargs):
    return _variant("jvm", library_id, variant_id, jar = _artifact(file_name), **kwargs)

def _install(
        name = _HUB,
        artifacts = [_COROUTINES],
        repositories = KMP_DEFAULT_REPOSITORIES,
        platforms = KMP_PLATFORMS,
        substitutions = [],
        manifest = Label("//:kmp_manifest.json"),
        fetch_sources = False):
    return struct(
        name = name,
        artifacts = artifacts,
        repositories = repositories,
        platforms = platforms,
        substitutions = substitutions,
        manifest = manifest,
        fetch_sources = fetch_sources,
    )

def _module(name, is_root, install = [], resolver = []):
    return struct(name = name, is_root = is_root, tags = struct(install = install, resolver = resolver))

def _platforms_follow_the_manifest_order_test(ctx):
    """The platforms are those of the resolver but wasmjs, the konan targets named as in KONAN_TARGETS."""
    env = unittest.begin(ctx)

    konan_targets = ["ios_arm64", "ios_simulator_arm64", "linux_arm64", "linux_x64", "macos_arm64"]
    asserts.equals(env, konan_targets, sorted(KONAN_TARGETS.keys()))
    asserts.equals(env, konan_targets + ["android", "jvm"], PLATFORM_ORDER)
    asserts.equals(env, ["jvm", "android"] + konan_targets, KMP_PLATFORMS)
    asserts.equals(env, ["https://repo1.maven.org/maven2"], KMP_DEFAULT_REPOSITORIES)

    return unittest.end(env)

def _inputs_are_normalized_as_the_inputs_hash_test(ctx):
    """Platforms in platform order, coordinates sorted, repositories in order, without duplicates; substitutions sorted, the last one wins."""
    env = unittest.begin(ctx)

    inputs = normalized_inputs(
        ["org.example:b:1", "org.example:a:1", "org.example:b:1"],
        ["https://r2.example", "https://r1.example", "https://r2.example"],
        ["jvm", "linux_x64", "android", "ios_arm64", "jvm"],
        ["org.example:y=org.example:y:2", "org.example:a=org.example:a:3", "org.example:y=org.example:y:4"],
    )
    asserts.equals(env, ["ios_arm64", "linux_x64", "android", "jvm"], inputs.platforms)
    asserts.equals(env, ["org.example:a:1", "org.example:b:1"], inputs.coordinates)
    asserts.equals(env, ["https://r2.example", "https://r1.example"], inputs.repositories)
    asserts.equals(env, ["org.example:a=org.example:a:3", "org.example:y=org.example:y:4"], inputs.substitutions)

    return unittest.end(env)

def _pinned_manifest_has_no_problem_test(ctx):
    """The header of a manifest generated for the inputs of the install matches them."""
    env = unittest.begin(ctx)

    manifest = _manifest()
    asserts.equals(env, 2, manifest["schemaVersion"])
    asserts.equals(env, None, manifest_problem(_HUB, "kmp_manifest.json", manifest, _inputs()))
    asserts.equals(env, None, manifest_problem(_HUB, "kmp_manifest.json", manifest, _inputs(artifacts = [_COROUTINES, _COROUTINES])))

    return unittest.end(env)

def _stale_manifest_names_the_field_test(ctx):
    """A changed coordinate, platform, repository order or substitution makes the manifest stale."""
    env = unittest.begin(ctx)

    manifest = _manifest()
    asserts.equals(
        env,
        ("@kmp_maven: the manifest kmp_manifest.json is stale: its askedCoordinates is " +
         "[\"org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2\"], but kmp_maven.install(name = \"kmp_maven\") " +
         "declares [\"org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.1\"]; run 'bazel run @kmp_maven//pin' and commit it"),
        manifest_problem(_HUB, "kmp_manifest.json", manifest, _inputs(artifacts = ["org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.1"])),
    )

    platforms = manifest_problem(_HUB, "kmp_manifest.json", manifest, _inputs(platforms = ["jvm", "android", "linux_x64", "ios_arm64", "macos_arm64"]))
    asserts.true(env, "is stale: its askedPlatforms is [\"ios_arm64\",\"linux_x64\",\"android\",\"jvm\"]" in platforms, platforms)

    google = "https://dl.google.com/dl/android/maven2"
    two_repositories = dict(manifest, askedRepositories = KMP_DEFAULT_REPOSITORIES + [google])
    asserts.equals(env, None, manifest_problem(_HUB, "kmp_manifest.json", two_repositories, _inputs(repositories = KMP_DEFAULT_REPOSITORIES + [google])))
    reordered = manifest_problem(_HUB, "kmp_manifest.json", two_repositories, _inputs(repositories = [google] + KMP_DEFAULT_REPOSITORIES))
    asserts.true(env, "is stale: its askedRepositories is" in reordered, reordered)

    substitutions = manifest_problem(
        _HUB,
        "kmp_manifest.json",
        manifest,
        _inputs(substitutions = ["org.jetbrains.kotlin:kotlin-stdlib=org.jetbrains.kotlin:kotlin-stdlib:2.4.21"]),
    )
    asserts.true(env, "is stale: its askedSubstitutions is []" in substitutions, substitutions)
    asserts.true(env, substitutions.endswith(_PIN + " and commit it"), substitutions)

    return unittest.end(env)

def _unusable_manifest_tells_to_pin_test(ctx):
    """An empty, missing, non-JSON or schema version 1 manifest asks to pin it."""
    env = unittest.begin(ctx)

    asserts.equals(env, None, decode_manifest(""))
    asserts.equals(env, None, decode_manifest(" \n"))
    asserts.equals(env, False, decode_manifest("{\"schemaVersion\": "))
    asserts.equals(
        env,
        ("@kmp_maven: the manifest third_party/kmp_manifest.json is empty or missing; run 'bazel run @kmp_maven//pin' " +
         "to resolve 1 artifacts for ios_arm64, linux_x64, android, jvm, then commit it"),
        manifest_problem(_HUB, "third_party/kmp_manifest.json", None, _inputs()),
    )
    not_json = manifest_problem(_HUB, "kmp_manifest.json", decode_manifest("not json"), _inputs())
    asserts.true(env, "the manifest kmp_manifest.json is not a JSON object" in not_json, not_json)
    asserts.equals(
        env,
        "@kmp_maven: the manifest kmp_manifest.json has schemaVersion 1; rules_kotlin reads version 2: run 'bazel run @kmp_maven//pin' and commit it",
        manifest_problem(_HUB, "kmp_manifest.json", dict(_manifest(), schemaVersion = 1), _inputs()),
    )

    return unittest.end(env)

def _names_test(ctx):
    """Target names are the group:artifact sanitized, repository names the hub and the Maven module."""
    env = unittest.begin(ctx)

    asserts.equals(env, _COROUTINES_LIB, library_target_name("org.jetbrains.kotlinx:kotlinx-coroutines-core"))
    asserts.equals(env, "io_ktor_ktor_client_curl", library_target_name("io.ktor:ktor-client-curl"))
    asserts.equals(env, _ATOMICFU_LINUX_REPO, module_repository_name(_HUB, "org.jetbrains.kotlinx:atomicfu-linuxx64:0.26.1"))
    asserts.equals(env, "kmp_maven__org_jetbrains_kotlin_kotlin_stdlib_2_1_0", module_repository_name(_HUB, "org.jetbrains.kotlin:kotlin-stdlib:2.1.0"))
    asserts.equals(env, "kmp_manifest.json", workspace_path(Label("//:kmp_manifest.json")))
    asserts.equals(env, "third_party/kmp/manifest.json", workspace_path(Label("//third_party/kmp:manifest.json")))

    return unittest.end(env)

def _libraries_merge_versions_and_skip_wasm_test(ctx):
    """The versions of a group:artifact are one library; wasm_js variants are left out."""
    env = unittest.begin(ctx)

    libraries = manifest_libraries(_manifest())
    asserts.equals(env, None, libraries.error)
    asserts.equals(
        env,
        ["org_jetbrains_annotations", "org_jetbrains_kotlin_kotlin_stdlib", _ATOMICFU_LIB, _COROUTINES_LIB],
        sorted(libraries.libraries.keys()),
    )
    coroutines = libraries.libraries[_COROUTINES_LIB]
    asserts.equals(env, "org.jetbrains.kotlinx:kotlinx-coroutines-core", coroutines.group_artifact)
    asserts.equals(env, ["ios_arm64", "linux_x64", "android", "jvm"], list(coroutines.variants.keys()))

    merged = manifest_libraries(_synthetic_manifest({
        "org.example:lib:1": [_jvm_variant("org.example:lib:1", "org.example:lib-jvm:1", "lib-jvm-1.jar")],
        "org.example:lib:2": [_variant("klib", "org.example:lib:2", "org.example:lib-linuxx64:2", platform = "linux_x64", klibs = [
            {"artifact": _artifact("lib-linuxx64-2.klib"), "role": "main"},
        ])],
    }))
    asserts.equals(env, None, merged.error)
    asserts.equals(env, ["org.example:lib:1", "org.example:lib:2"], merged.libraries["org_example_lib"].ids)
    asserts.equals(env, ["linux_x64", "jvm"], list(merged.libraries["org_example_lib"].variants.keys()))

    return unittest.end(env)

def _libraries_naming_the_same_target_fail_test(ctx):
    """Two group:artifacts sanitized to one name, or two versions with a variant of one platform, are an error."""
    env = unittest.begin(ctx)

    same_name = manifest_libraries(_synthetic_manifest({
        "org.example:a.b:1": [_jvm_variant("org.example:a.b:1", "org.example:a.b:1", "a.b-1.jar")],
        "org.example:a_b:1": [_jvm_variant("org.example:a_b:1", "org.example:a_b:1", "a_b-1.jar")],
    }))
    asserts.equals(env, "libraries org.example:a.b:1 and org.example:a_b:1 both name the target org_example_a_b", same_name.error)

    same_platform = manifest_libraries(_synthetic_manifest({
        "org.example:lib:1": [_jvm_variant("org.example:lib:1", "org.example:lib:1", "lib-1.jar")],
        "org.example:lib:2": [_jvm_variant("org.example:lib:2", "org.example:lib:2", "lib-2.jar")],
    }))
    asserts.equals(env, "libraries org.example:lib:1 and org.example:lib:2 both have a variant for jvm", same_platform.error)

    # A JVM library named like the jvm import of another one.
    collision = hub_contents(_HUB, "kmp_manifest.json", _synthetic_manifest({
        "org.example:lib-jvm:1": [_jvm_variant("org.example:lib-jvm:1", "org.example:lib-jvm:1", "lib-jvm-1.jar")],
        "org.example:lib:1": [_jvm_variant("org.example:lib:1", "org.example:lib-jvm:1", "lib-jvm-1.jar")],
    }), False)
    asserts.equals(env, None, collision.build_file)
    asserts.equals(
        env,
        ("kmp_maven.install(name = \"kmp_maven\"): the manifest kmp_manifest.json has libraries org.example:lib and " +
         "org.example:lib-jvm that both name the target org_example_lib_jvm"),
        collision.error,
    )

    return unittest.end(env)

def _module_repositories_group_the_files_of_a_module_test(ctx):
    """A repository per Maven module: the klibs of a variant together, a module shared by android and jvm."""
    env = unittest.begin(ctx)

    manifest = _manifest()
    repositories = module_repositories(_HUB, manifest, False)
    asserts.equals(
        env,
        [
            "kmp_maven__org_jetbrains_annotations_23_0_0",
            "kmp_maven__org_jetbrains_kotlin_kotlin_stdlib_2_1_0",
            "kmp_maven__org_jetbrains_kotlinx_atomicfu_iosarm64_0_26_1",
            _ATOMICFU_LINUX_REPO,
            "kmp_maven__org_jetbrains_kotlinx_kotlinx_coroutines_core_iosarm64_1_10_2",
            _COROUTINES_JVM_REPO,
            _COROUTINES_LINUX_REPO,
        ],
        repositories.keys(),
    )
    asserts.equals(
        env,
        ["atomicfu-linuxx64-0.26.1-cinterop-interop.klib", "atomicfu-linuxx64-0.26.1.klib"],
        sorted(repositories[_ATOMICFU_LINUX_REPO].keys()),
    )
    asserts.equals(env, ["kotlinx-coroutines-core-jvm-1.10.2.jar"], repositories[_COROUTINES_JVM_REPO].keys())

    jar = manifest["libraries"][_COROUTINES]["variants"][-1]["jar"]
    downloaded = repositories[_COROUTINES_JVM_REPO]["kotlinx-coroutines-core-jvm-1.10.2.jar"]
    asserts.equals(env, jar["integrity"], downloaded.integrity)
    asserts.equals(env, jar["urls"], downloaded.urls)

    with_sources = module_repositories(_HUB, manifest, True)
    asserts.equals(
        env,
        ["kotlinx-coroutines-core-jvm-1.10.2-sources.jar", "kotlinx-coroutines-core-jvm-1.10.2.jar"],
        sorted(with_sources[_COROUTINES_JVM_REPO].keys()),
    )
    asserts.true(env, "atomicfu-linuxx64-0.26.1-sources.jar" in with_sources[_ATOMICFU_LINUX_REPO])

    build_file = module_build_file(repositories[_ATOMICFU_LINUX_REPO].keys())
    asserts.true(
        env,
        "[\"atomicfu-linuxx64-0.26.1-cinterop-interop.klib\", \"atomicfu-linuxx64-0.26.1.klib\"]" in build_file,
        build_file,
    )

    return unittest.end(env)

def _assert_contains(env, build_file, snippets):
    for snippet in snippets:
        asserts.true(env, snippet in build_file, "%s\n--- is not in ---\n%s" % (snippet, build_file))

def _hub_imports_the_variants_test(ctx):
    """The klib imports, with the cinterop ones in the deps of the main one, and the JVM and Android imports."""
    env = unittest.begin(ctx)

    build_file = hub_contents(_HUB, "kmp_manifest.json", _manifest(), False).build_file
    _assert_contains(env, build_file, [
        "load(%s, \"kt_jvm_import\")\nload(%s, \"kt_klib_import\")\n" % (repr(_JVM_BZL), repr(_NATIVE_BZL)),
        "package(default_visibility = [\"//visibility:public\"])",
        """# org.jetbrains.kotlinx:atomicfu:0.26.1
kt_klib_import(
    name = "org_jetbrains_kotlinx_atomicfu_ios_arm64_cinterop_0",
""",
        """kt_klib_import(
    name = "org_jetbrains_kotlinx_atomicfu_linux_x64_cinterop_0",
    klib = "@kmp_maven__org_jetbrains_kotlinx_atomicfu_linuxx64_0_26_1//:atomicfu-linuxx64-0.26.1-cinterop-interop.klib",
    konan_target = "linux_x64",
)

kt_klib_import(
    name = "org_jetbrains_kotlinx_atomicfu_linux_x64",
    klib = "@kmp_maven__org_jetbrains_kotlinx_atomicfu_linuxx64_0_26_1//:atomicfu-linuxx64-0.26.1.klib",
    konan_target = "linux_x64",
    deps = [":org_jetbrains_kotlinx_atomicfu_linux_x64_cinterop_0"],
)
""",
        """kt_klib_import(
    name = "org_jetbrains_kotlinx_kotlinx_coroutines_core_linux_x64",
    klib = "@kmp_maven__org_jetbrains_kotlinx_kotlinx_coroutines_core_linuxx64_1_10_2//:kotlinx-coroutines-core-linuxx64-1.10.2.klib",
    konan_target = "linux_x64",
    exports = [":org_jetbrains_kotlinx_atomicfu_linux_x64"],
)
""",
        """kt_jvm_import(
    name = "org_jetbrains_kotlinx_kotlinx_coroutines_core_android",
    jars = ["@kmp_maven__org_jetbrains_kotlinx_kotlinx_coroutines_core_jvm_1_10_2//:kotlinx-coroutines-core-jvm-1.10.2.jar"],
    exports = [
        ":org_jetbrains_annotations_android",
        ":org_jetbrains_kotlin_kotlin_stdlib_android",
    ],
    deps = [
        ":org_jetbrains_annotations_android",
        ":org_jetbrains_kotlin_kotlin_stdlib_android",
    ],
)
""",
        """kt_jvm_import(
    name = "org_jetbrains_kotlinx_kotlinx_coroutines_core_jvm",
    jars = ["@kmp_maven__org_jetbrains_kotlinx_kotlinx_coroutines_core_jvm_1_10_2//:kotlinx-coroutines-core-jvm-1.10.2.jar"],
""",
        """kt_jvm_import(
    name = "org_jetbrains_annotations_jvm",
    jars = ["@kmp_maven__org_jetbrains_annotations_23_0_0//:annotations-23.0.0.jar"],
)
""",
        # kotlin-stdlib has no klib variant: the native imports do not depend on it.
        """kt_jvm_import(
    name = "org_jetbrains_kotlin_kotlin_stdlib_jvm",
    jars = ["@kmp_maven__org_jetbrains_kotlin_kotlin_stdlib_2_1_0//:kotlin-stdlib-2.1.0.jar"],
    exports = [":org_jetbrains_annotations_jvm"],
    deps = [":org_jetbrains_annotations_jvm"],
)
""",
    ])
    for absent in ["aar_import", "srcjar", "wasm", "stdlib_linux_x64", "stdlib_ios_arm64"]:
        asserts.false(env, absent in build_file, absent)

    return unittest.end(env)

def _hub_aliases_select_the_variant_of_the_consumer_test(ctx):
    """The alias of a library selects its klib for the Kotlin/Native rules, its android variant on Android, its jvm one otherwise."""
    env = unittest.begin(ctx)

    build_file = hub_contents(_HUB, "kmp_manifest.json", _manifest(), False).build_file
    resolved = "kmp_maven.install(name = \\\"kmp_maven\\\") resolved it for"
    _assert_contains(env, build_file, [
        """alias(
    name = "org_jetbrains_kotlinx_kotlinx_coroutines_core_native",
    actual = select(
        {
            "%s": ":org_jetbrains_kotlinx_kotlinx_coroutines_core_ios_arm64",
            "%s": ":org_jetbrains_kotlinx_kotlinx_coroutines_core_linux_x64",
        },
        no_match_error = "org.jetbrains.kotlinx:kotlinx-coroutines-core has no klib for the konan target of this Kotlin/Native target: %s ios_arm64, linux_x64, android, jvm. Add the target to the platforms of the install and run 'bazel run @kmp_maven//pin', if the library publishes it.",
    ),
)""" % (_native_setting("ios_arm64"), _native_setting("linux_x64"), resolved),
        """alias(
    name = "org_jetbrains_kotlinx_kotlinx_coroutines_core",
    actual = select(
        {
            "%s": ":org_jetbrains_kotlinx_kotlinx_coroutines_core_native",
            "%s": ":org_jetbrains_kotlinx_kotlinx_coroutines_core_android",
            "//conditions:default": ":org_jetbrains_kotlinx_kotlinx_coroutines_core_jvm",
        },
    ),
)""" % (_NATIVE, _ANDROID),
        # A library without jvm variant fails for the other consumers.
        """alias(
    name = "org_jetbrains_kotlinx_atomicfu",
    actual = select(
        {
            "%s": ":org_jetbrains_kotlinx_atomicfu_native",
        },
        no_match_error = "org.jetbrains.kotlinx:atomicfu has no variant for this target: %s ios_arm64, linux_x64. A Kotlin/Native target takes its klib, an Android target its android variant, any other target its jvm variant.",
    ),
)""" % (_NATIVE, resolved),
        # A library without klib variant has no native branch.
        """alias(
    name = "org_jetbrains_annotations",
    actual = select(
        {
            "%s": ":org_jetbrains_annotations_android",
            "//conditions:default": ":org_jetbrains_annotations_jvm",
        },
    ),
)""" % _ANDROID,
    ])

    # A JVM library has a plain alias.
    jvm_only = hub_contents(_HUB, "kmp_manifest.json", _synthetic_manifest({
        "org.jetbrains:annotations:23.0.0": [_jvm_variant("org.jetbrains:annotations:23.0.0", "org.jetbrains:annotations:23.0.0", "annotations-23.0.0.jar")],
    }), False).build_file
    _assert_contains(env, jvm_only, [
        """alias(
    name = "org_jetbrains_annotations",
    actual = ":org_jetbrains_annotations_jvm",
)""",
    ])
    asserts.false(env, "kt_klib_import" in jvm_only, jvm_only)

    return unittest.end(env)

def _hub_imports_sources_and_aars_test(ctx):
    """With fetch_sources, the sources jars are the srcjar of the JVM and Android imports; an aar is an aar_import."""
    env = unittest.begin(ctx)

    with_sources = hub_contents(_HUB, "kmp_manifest.json", _manifest(), True).build_file
    _assert_contains(env, with_sources, [
        """    jars = ["@kmp_maven__org_jetbrains_kotlinx_kotlinx_coroutines_core_jvm_1_10_2//:kotlinx-coroutines-core-jvm-1.10.2.jar"],
    srcjar = "@kmp_maven__org_jetbrains_kotlinx_kotlinx_coroutines_core_jvm_1_10_2//:kotlinx-coroutines-core-jvm-1.10.2-sources.jar",
""",
    ])
    asserts.false(env, "klib-sources" in with_sources or "0.26.1-sources.jar" in with_sources, with_sources)

    stdlib = "org.jetbrains.kotlin:kotlin-stdlib:2.1.0"
    aar = hub_contents(_HUB, "kmp_manifest.json", _synthetic_manifest({
        "org.example:widget:1.0": [
            _variant(
                "android",
                "org.example:widget:1.0",
                "org.example:widget-android:1.0",
                dependencies = ["org.jetbrains.kotlin:kotlin-stdlib"],
                artifact = _artifact("widget-android-1.0.aar"),
                packaging = "aar",
            ),
        ],
        stdlib: [_variant("android", stdlib, stdlib, artifact = _artifact("kotlin-stdlib-2.1.0.jar"), packaging = "jar")],
    }), False).build_file
    _assert_contains(env, aar, [
        "load(%s, \"aar_import\")\nload(%s, \"kt_jvm_import\")\n" % (repr(_ANDROID_BZL), repr(_JVM_BZL)),
        """aar_import(
    name = "org_example_widget_android",
    aar = "@kmp_maven__org_example_widget_android_1_0//:widget-android-1.0.aar",
    deps = [":org_jetbrains_kotlin_kotlin_stdlib_android"],
)""",
        # A library with only an android variant fails for the other consumers.
        """    actual = select(
        {
            "%s": ":org_example_widget_android",
        },
        no_match_error = "org.example:widget has no variant for this target:""" % _ANDROID,
    ])
    asserts.false(env, "kt_klib_import" in aar, aar)

    return unittest.end(env)

def _unpinned_hub_fails_with_the_problem_test(ctx):
    """The BUILD file of an unpinned hub fails with the message of the manifest problem."""
    env = unittest.begin(ctx)

    problem = manifest_problem(_HUB, "kmp_manifest.json", None, _inputs())
    build_file = unpinned_build_file(_HUB, problem)
    asserts.true(env, "\nfail(%s)\n" % repr(problem) in build_file, build_file)
    asserts.true(env, "@kmp_maven//pin" in build_file, build_file)

    return unittest.end(env)

def _pin_runs_the_resolver_with_the_inputs_test(ctx):
    """@<hub>//pin runs generate-bazel-manifest with one option per input, into the workspace."""
    env = unittest.begin(ctx)

    build_file = pin_build_file(_HUB, KMP_RESOLVER_LABEL)
    _assert_contains(env, build_file, [
        "load(%s, \"sh_binary\")" % repr(str(Label("@rules_shell//shell:sh_binary.bzl"))),
        "    name = \"pin\",\n    srcs = [\"pin.sh\"],\n",
        "    args = [\"$(rlocationpath @bazel_kmp_resolver//:bazel-kmp-resolver)\"],\n",
        "    data = [\"@bazel_kmp_resolver//:bazel-kmp-resolver\"],\n",
        "    deps = [%s],\n" % repr(str(Label("@bazel_tools//tools/bash/runfiles"))),
    ])

    inputs = _inputs(substitutions = ["org.jetbrains.kotlin:kotlin-stdlib=org.jetbrains.kotlin:kotlin-stdlib:2.1.21"])
    script = pin_script(_HUB, "kmp_manifest.json", inputs)
    asserts.true(env, script.startswith("#!/usr/bin/env bash\n"), script)
    _assert_contains(env, script, [
        "source \"${RUNFILES_DIR:-/dev/null}/$f\"",
        "if [[ -z \"${BUILD_WORKSPACE_DIRECTORY:-}\" ]]; then",
        "resolver=\"$(rlocation \"$1\")\"\nshift\n",
        "manifest=\"$BUILD_WORKSPACE_DIRECTORY\"/kmp_manifest.json\n",
        "cache_dir=\"${XDG_CACHE_HOME:-$HOME/.cache}/rules_kotlin/bazel-kmp-resolver\"\n",
        """"$resolver" generate-bazel-manifest \\
  --output-manifest-file="$manifest" \\
  --cache-dir="$cache_dir" \\
  --coordinate=org.jetbrains.kotlinx:kotlinx-coroutines-core:1.10.2 \\
  --repository=https://repo1.maven.org/maven2 \\
  --platform=ios_arm64 \\
  --platform=linux_x64 \\
  --platform=android \\
  --platform=jvm \\
  --substitution=org.jetbrains.kotlin:kotlin-stdlib=org.jetbrains.kotlin:kotlin-stdlib:2.1.21 \\
  "$@"
""",
        "echo \"Wrote $manifest for kmp_maven.install(name = \\\"kmp_maven\\\"): commit it.\"",
    ])

    # Words with spaces or shell characters are quoted.
    quoted = pin_script(_HUB, "third party/kmp manifest.json", _inputs(repositories = ["https://maven.example/repo?a=1&b=2"]))
    _assert_contains(env, quoted, [
        "manifest=\"$BUILD_WORKSPACE_DIRECTORY\"/'third party/kmp manifest.json'\n",
        "  '--repository=https://maven.example/repo?a=1&b=2' \\\n",
    ])

    return unittest.end(env)

def _resolver_is_the_release_asset_of_the_host_test(ctx):
    """The asset of the host of the pinned release, checked against its sha256, otherwise why there is none."""
    env = unittest.begin(ctx)

    asserts.equals(env, struct(version = KMP_RESOLVER_VERSION, sha256 = KMP_RESOLVER_SHA256), resolver_release())
    asserts.equals(env, struct(version = "0.5.0", sha256 = {"linux-x64": "abc"}), resolver_release("0.5.0", {"linux-x64": "abc"}))

    # A tag of the pinned version keeps the checksums rules_kotlin pins for the hosts it omits.
    asserts.equals(env, dict(KMP_RESOLVER_SHA256, **{"linux-x64": "abc"}), resolver_release(KMP_RESOLVER_VERSION, {"linux-x64": "abc"}).sha256)

    # rules_kotlin pins the sha256 of every asset of its release, as the release page publishes them.
    asserts.equals(env, sorted(KMP_RESOLVER_ASSETS.keys()), sorted(KMP_RESOLVER_SHA256.keys()))
    for host, sha256 in KMP_RESOLVER_SHA256.items():
        asserts.true(env, len(sha256) == 64 and all([character in "0123456789abcdef" for character in sha256.elems()]), host + ": " + sha256)
    for os_name, arch, host, sha256 in [
        ("linux", "aarch64", "linux-arm64", "46fa847253b380e8787cbb0d2093529e63b294bfbab3d21862c6ab3d7a993790"),
        ("linux", "amd64", "linux-x64", "133e362e7827a0c60f100e45cd4a955fb877e552e38e81cbb8992fdc0f5a4b4a"),
        ("Mac OS X", "aarch64", "macos-arm64", "022a2f5d3049ccc1134faf52f0eff0faf7cb2258664ead386dcb0513ae46a5d8"),
        ("mac os x", "x86_64", "macos-x64", "de51cd44afae07ce8a907ae3eb099d36bbf5d13b9e00ec7f32ad110d6a994b68"),
        ("windows 11", "amd64", "windows-x64", "b4ce8b8f8f5f399a1e23f1be29f3457505f28d16b4e56d39c67d10a02ceba0b5"),
    ]:
        pinned = resolver_download(os_name, arch, resolver_release())
        asserts.equals(env, None, pinned.error)
        asserts.equals(env, "https://github.com/avan1235/bazel-kmp-resolver/releases/download/0.4.0/" + KMP_RESOLVER_ASSETS[host], pinned.url)
        asserts.equals(env, sha256, pinned.sha256, host)

    mac = resolver_asset("Mac OS X", "aarch64", "0.4.0")
    asserts.equals(env, "macos-arm64", mac.host)
    asserts.equals(env, "https://github.com/avan1235/bazel-kmp-resolver/releases/download/0.4.0/bazel-kmp-resolver-macos-arm64", mac.url)
    asserts.equals(env, "bazel-kmp-resolver", mac.executable)
    windows = resolver_asset("windows 11", "amd64", "0.4.0")
    asserts.equals(env, "bazel-kmp-resolver-windows-x64.exe", windows.file_name)
    asserts.equals(env, "bazel-kmp-resolver.exe", windows.executable)
    asserts.equals(env, "linux-x64", resolver_asset("linux", "x86_64", "0.4.0").host)
    asserts.equals(env, None, resolver_asset("freebsd", "amd64", "0.4.0"))
    asserts.equals(env, None, resolver_asset("linux", "ppc64le", "0.4.0"))

    # Another release downloads with the checksums of its tag.
    download = resolver_download("linux", "amd64", resolver_release("0.5.0", {"linux-x64": "abc"}))
    asserts.equals(env, None, download.error)
    asserts.equals(env, "https://github.com/avan1235/bazel-kmp-resolver/releases/download/0.5.0/bazel-kmp-resolver-linux-x64", download.url)
    asserts.equals(env, "abc", download.sha256)

    # Without the checksum of the host, the only remedy is the tag, which pins it.
    unpinned = resolver_download("mac os x", "aarch64", resolver_release("0.5.0", {"linux-x64": "abc"}))
    asserts.equals(env, None, unpinned.url)
    asserts.equals(
        env,
        "bazel-kmp-resolver 0.5.0 has no pinned checksum for macos-arm64: add the sha256 of its asset " +
        "bazel-kmp-resolver-macos-arm64 to kmp_maven.resolver(version, sha256)",
        unpinned.error,
    )

    # A host without asset names the hosts with one.
    unsupported = resolver_download("linux", "ppc64le", resolver_release())
    asserts.equals(env, None, unsupported.url)
    asserts.equals(
        env,
        "bazel-kmp-resolver publishes no binary for linux on ppc64le: its releases have one for " +
        "linux-arm64, linux-x64, macos-arm64, macos-x64, windows-x64",
        unsupported.error,
    )
    asserts.equals(env, None, resolver_download("freebsd", "amd64", resolver_release()).url)
    asserts.true(env, resolver_download("freebsd", "amd64", resolver_release()).error.startswith("bazel-kmp-resolver publishes no binary for freebsd on amd64: "))

    return unittest.end(env)

def _install_attributes_are_validated_test(ctx):
    """Malformed coordinates and substitutions, unsupported platforms and manifests of other modules are errors."""
    env = unittest.begin(ctx)

    def error(**kwargs):
        tag = _install(**kwargs)
        return install_error(tag.name, tag.artifacts, tag.repositories, tag.platforms, tag.substitutions, tag.manifest)

    asserts.equals(env, None, error())
    asserts.equals(env, None, error(substitutions = ["org.example:a=org.example:b:1"], manifest = Label("//third_party:kmp_manifest.json")))
    prefix = "kmp_maven.install(name = \"kmp_maven\"): "
    asserts.equals(env, prefix + "platform 'wasmjs' is not supported yet: rules_kotlin has no Kotlin/Wasm rules", error(platforms = ["jvm", "wasmjs"]))
    asserts.equals(
        env,
        prefix + "platform 'linux_x86' is not supported; use jvm, android or a konan target: ios_arm64, ios_simulator_arm64, linux_arm64, linux_x64, macos_arm64",
        error(platforms = ["linux_x86"]),
    )
    asserts.equals(
        env,
        prefix + "artifact 'org.jetbrains.kotlinx:kotlinx-coroutines-core' is not group:artifact:version",
        error(artifacts = ["org.jetbrains.kotlinx:kotlinx-coroutines-core"]),
    )
    asserts.equals(env, prefix + "artifact 'a::1' is not group:artifact:version", error(artifacts = ["a::1"]))
    asserts.equals(env, prefix + "it declares no artifacts", error(artifacts = []))
    asserts.equals(env, prefix + "it declares no platforms", error(platforms = []))
    asserts.equals(
        env,
        prefix + "substitution 'org.example:a:1=org.example:b:1' is not group:artifact=group:artifact:version",
        error(substitutions = ["org.example:a:1=org.example:b:1"]),
    )
    other_module = error(manifest = Label("@rules_android//rules:rules.bzl"))
    asserts.true(env, other_module.startswith(prefix + "the manifest @@rules_android"), other_module)
    asserts.true(env, other_module.endswith("is not a file of the root module, whose workspace the pin target writes it into"), other_module)
    asserts.true(env, "use another one" in error(name = "bazel_kmp_resolver"))

    return unittest.end(env)

def _config_reads_the_root_tags_test(ctx):
    """The installs of the root module, normalized, and its resolver release; the pinned release by default."""
    env = unittest.begin(ctx)

    default = collect_kmp_maven_config([_module("root", True), _module("dependency", False)])
    asserts.equals(env, [], default.installs)
    asserts.equals(env, resolver_release(), default.resolver)

    config = collect_kmp_maven_config([
        _module(
            "root",
            True,
            install = [
                _install(platforms = ["jvm", "linux_x64", "jvm"]),
                _install(name = "tools", manifest = Label("//tools:kmp_manifest.json"), fetch_sources = True),
            ],
            resolver = [struct(version = "0.5.0", sha256 = {"macos-arm64": "abc"})],
        ),
        _module("dependency", False),
    ])
    asserts.equals(env, ["kmp_maven", "tools"], [install.name for install in config.installs])
    first = config.installs[0]
    asserts.equals(env, ["linux_x64", "jvm"], first.inputs.platforms)
    asserts.equals(env, [_COROUTINES], first.inputs.coordinates)
    asserts.equals(env, "kmp_manifest.json", first.manifest_path)
    asserts.equals(env, Label("//:kmp_manifest.json"), first.manifest)
    asserts.false(env, first.fetch_sources)
    asserts.equals(env, "tools/kmp_manifest.json", config.installs[1].manifest_path)
    asserts.equals(env, PLATFORM_ORDER, config.installs[1].inputs.platforms)
    asserts.true(env, config.installs[1].fetch_sources)
    asserts.equals(env, struct(version = "0.5.0", sha256 = {"macos-arm64": "abc"}), config.resolver)

    return unittest.end(env)

platforms_follow_the_manifest_order_test = unittest.make(_platforms_follow_the_manifest_order_test)
inputs_are_normalized_as_the_inputs_hash_test = unittest.make(_inputs_are_normalized_as_the_inputs_hash_test)
pinned_manifest_has_no_problem_test = unittest.make(_pinned_manifest_has_no_problem_test)
stale_manifest_names_the_field_test = unittest.make(_stale_manifest_names_the_field_test)
unusable_manifest_tells_to_pin_test = unittest.make(_unusable_manifest_tells_to_pin_test)
names_test = unittest.make(_names_test)
libraries_merge_versions_and_skip_wasm_test = unittest.make(_libraries_merge_versions_and_skip_wasm_test)
libraries_naming_the_same_target_fail_test = unittest.make(_libraries_naming_the_same_target_fail_test)
module_repositories_group_the_files_of_a_module_test = unittest.make(_module_repositories_group_the_files_of_a_module_test)
hub_imports_the_variants_test = unittest.make(_hub_imports_the_variants_test)
hub_aliases_select_the_variant_of_the_consumer_test = unittest.make(_hub_aliases_select_the_variant_of_the_consumer_test)
hub_imports_sources_and_aars_test = unittest.make(_hub_imports_sources_and_aars_test)
unpinned_hub_fails_with_the_problem_test = unittest.make(_unpinned_hub_fails_with_the_problem_test)
pin_runs_the_resolver_with_the_inputs_test = unittest.make(_pin_runs_the_resolver_with_the_inputs_test)
resolver_is_the_release_asset_of_the_host_test = unittest.make(_resolver_is_the_release_asset_of_the_host_test)
install_attributes_are_validated_test = unittest.make(_install_attributes_are_validated_test)
config_reads_the_root_tags_test = unittest.make(_config_reads_the_root_tags_test)

def kmp_maven_test_suite(name):
    unittest.suite(
        name,
        platforms_follow_the_manifest_order_test,
        inputs_are_normalized_as_the_inputs_hash_test,
        pinned_manifest_has_no_problem_test,
        stale_manifest_names_the_field_test,
        unusable_manifest_tells_to_pin_test,
        names_test,
        libraries_merge_versions_and_skip_wasm_test,
        libraries_naming_the_same_target_fail_test,
        module_repositories_group_the_files_of_a_module_test,
        hub_imports_the_variants_test,
        hub_aliases_select_the_variant_of_the_consumer_test,
        hub_imports_sources_and_aars_test,
        unpinned_hub_fails_with_the_problem_test,
        pin_runs_the_resolver_with_the_inputs_test,
        resolver_is_the_release_asset_of_the_host_test,
        install_attributes_are_validated_test,
        config_reads_the_root_tags_test,
    )
