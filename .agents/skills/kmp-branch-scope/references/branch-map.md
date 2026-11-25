# Branch map: Kotlin/Native and Kotlin Multiplatform in rules_kotlin

Snapshot: `262e0f73` (2026-11-25). It covers 28 commits, from `09145518` to `262e0f73`, on top of upstream master `239007ef`
("Add Kover code coverage support (#1831)"). Together they touch 252 files: 205 added and 47 upstream files modified.
`scripts/scope.sh` marks with `*` every commit of the range that this map does not list yet. Facts
below are as of the snapshot, and commit messages can be stale. Check a detail against the code before relying on it.

## Purpose

The `kmp` branch of `JetBrains/rules_kotlin` (remote `origin`) branches from master at `239007ef`. At the snapshot that
commit was also the tip of `bazel-contrib/rules_kotlin` master (remote `upstream`). The work goes in this order:

1. **Kotlin/Native first.** Toolchains per exec host and konan target, klib compilation, linking of binaries, tests and
   static Apple frameworks, all in hermetic, path-mapped and reproducible actions.
2. **Kotlin Multiplatform on top.** One module compiled for the JVM, Android and konan targets as K2 fragments, plus
   Maven KMP dependencies, KSP, compile avoidance and the Android and iOS app integration.
3. **Support the two need.** Kotlin release upgrades (Kotlin/Native is pinned apart from the JVM compiler), language
   levels that Kotlin 2.5 accepts, docs, CI and examples.

Nothing of the branch is released: no tag contains `09145518`. `CHANGELOG.md` holds two entries for the whole branch
(`81e7457e`). One covers the Kotlin/Native and KMP support and cites #1682; the other covers the language levels and the
upgrade script.

## Commit ledger (oldest first)

1. `09145518` Kotlin/Native support (prototype): kt_native_library + kt_native_binary
   - Christian Jackson-Gruber's prototype: shell konanc launchers, `KtNativeInfo` and a client-detected konan repository.
   - Its files mostly still exist (`library.bzl`, `binary.bzl`, `providers.bzl`, `toolchains.bzl`, `native.bzl`,
     `native_compiler.bzl`, `examples/native`), but their content was rewritten below. The two launcher scripts are deleted.
2. `31ec8026` Align Kotlin/Native prototype with current repository state
   - sha256 pins and release packaging (`kotlin/internal/native` pkg, `MODULE.release.bazel`).
   - `KOTLIN_NATIVE_VERSION` derived from the JVM release was later superseded by `c3bf80aa`.
3. `e9d49f25` Harden the Kotlin/Native toolchain for Linux and macOS exec hosts
   - `targets.bzl` (`KONAN_TARGETS`, `EXEC_HOSTS`) and the public `//kotlin/native/platforms` package (`<target>` and `is_<target>`).
   - The `kotlin_native.version`/`.targets` tags and per-host repositories exposing DirectoryInfo trees.
   - A fetch-time cross-check against konan.properties, and 7 generated toolchains `<host>_<target>` with `manual` impls.
   - `airplaneMode=true`, CI wiring and the exec bit in the upstream `BazelIntegrationTestBase.kt`.
4. `b5406adc` Replace the Kotlin/Native launchers with an in-process KonanLauncher
   - `KonanLauncher.kt`: a params file, scratch dirs it recreates and deletes, and exit codes 0/1/2.
   - The shared `klib.bzl` action with path mapping (`__EXECROOT__`) and `KtKlibInfo`, replacing `KtNativeInfo`.
   - `module_name` derived from the label, and `KtCompilerPluginInfo.embeddable_classpath` (upstream `providers.bzl`,
     `compiler_plugins.bzl`, `kapt.bzl`).
5. `8acd01fb` Link Kotlin/Native binaries, tests and frameworks in two steps
   - The srcs compile to a private klib, which the link takes with `-Xinclude`.
   - Adds `kt_native_test` (associates as friends, `-generate-test-runner`) and `kt_native_framework` (static, `bundle_id`).
   - Also `link.bzl`, `repro_check.sh`, and qemu for `linux_arm64` on a Linux host.
6. `3e4cadb3` Compile Kotlin Multiplatform source sets for native, JVM and Android
   - K2 fragment flags (`fragments.bzl`), `absoluteFragmentSources` in the upstream `BtapiTaskExecutor.kt`, and `examples/kmp`.
   - Its source-set API (`kt_source_set`, `source_sets`, `common_*`, `<name>_common`, `<name>_<group>`) is gone,
     removed by `3dcd5e18` and `5c535ad3`.
7. `e0f1b4c7` Resolve Kotlin Multiplatform Maven dependencies and import klibs
   - `//kotlin/settings:kotlin_platform_type` with `kt_native_transition`, and the `native`/`native_<t>` config_settings.
   - `kt_klib_import`, and the `kmp_maven` extension: a manifest pinned by bazel-kmp-resolver through `@<hub>//pin`.
   - `docs/kmp_dependencies.md`.
   - Its message calls bazel-kmp-resolver 0.4.0 unpublished, but the commit pins it (`KMP_RESOLVER_SHA256` in
     `kmp_maven_impl.bzl`), and `docs/kmp_dependencies.md` says pinning needs nothing set.
8. `40ac648e` Expose the files of a Kotlin/Native framework as the framework_files output group
   - Added for rules_apple's `apple_static_framework_import`.
9. `ad0b64de` Add a Kotlin Multiplatform app example with an Android and an iOS app
   - `examples/kmp_app`: needs Bazel 8 and runs on macOS CI.
10. `523a1fe8` Document the Kotlin/Native and Kotlin Multiplatform rules
    - Stardoc of `native.bzl`/`kmp.bzl` in `docs/kotlin.md`, and `docs/kmp.md`.
    - The rules_android bzl_library visibility patch (`third_party/`, applied through a root-module override for the docs only).
11. `69659154` Report the instrumented files of kt_android_library once, with its source sets
    - A coverage fix in the upstream `kt_android_library_impl.bzl` (conflicting baseline coverage on Bazel 8).
12. `706fca24` Port a Compose Multiplatform app to the KMP rules
    - kmp_maven: `redirect` variants, `extra_dependencies`, and hub variant names `<lib>.<platform>`.
    - `transitive_exports` on `kt_native_framework`, `exports` of any JavaInfo in the upstream `kt_jvm_import`, and
      `KOTLIN_NATIVE_LLVM` per release.
    - Its source sets in `runtime_deps` and the `kt_source_set` JavaInfo are gone.
13. `9b3bb81c` Run KSP as a separate action for the KMP source sets, extend kmp_maven
    - `kt_jvm_ksp_sources`/`kt_native_ksp_sources` (`ksp.bzl`, `ksp_run.sh`, with the declared `generated` outputs validated).
    - kmp_maven `ignore_published_checksums` and `excluded_artifacts`.
14. `3dcd5e18` Replace kt_source_set with fragments derived from per-platform srcs
    - `derive.bzl`, the internal `kt_kmp_fragment`/`KtFragmentInfo`, and `kmp_fragments` on the libraries only.
    - Deleted `examples/kmp/explicit`. Its macro shape was replaced by `5c535ad3`.
15. `6c3ed718` Compile KMP dependents against ABI jars and Kotlin/Native header klibs
    - `experimental_native_header_klibs`, `KtKlibInfo.compile_klib`/`transitive_compile_klibs`, and the tag `kt_native_header_klib_incompatible`.
    - The `CompileAvoidance.md` section and `compile_avoidance_test`.
    - It turned ABI jars on by default for fragment libraries; `69f76b99` gated them behind `experimental_use_abi_jars`.
16. `99b1d312` Automate Kotlin release upgrades
    - `scripts/upgrade_kotlin.sh`, `src/main/kotlin/io/bazel/kotlin/upgrade` and `docs/upgrading_kotlin.md`.
    - `language_level.bzl`: language and API versions default to the compiler release (`toolchains.bzl`, CLI `BUILD.bazel`),
      reading `KOTLINC_VERSION` in `version.bzl` of the compiler repo (`compiler.bzl`).
    - Generated regions in the docs.
17. `b79daca7` Move the examples to language and API version 2.3
    - Upstream `examples/android/bzl`, `examples/dagger`, `examples/deps/bzl`: Kotlin 2.5 drops 2.0 and 2.1.
    - dagger moves to kotlin-metadata-jvm 2.4.21.
18. `69f76b99` Gate KMP JVM and Android ABI jars behind experimental_use_abi_jars
    - Compile avoidance is opt-in on every platform, as for standalone libraries.
19. `42970f63` Add <name>.fragments target printing derived KMP fragment graph
    - `kt_kmp_fragments_graph` and `format_fragments`.
20. `1e3c123d` `kt_multiplatform_library` now takes the lists it prepends to every platform as `srcs`, `deps`, ...
    - Adds the `srcs`, `deps`, `exports` and `plugins` of the macro, which every platform gets
      (`multiplatform_common_test.bzl`). `5c535ad3` makes them the `common` lists of the hierarchy.
    - The commit it fixed up is already folded into it, so no `common_*` macro parameter exists in the history. Still, its
      subject and body describe a rename from them, and its "Left out" about folding is stale.
21. `5c535ad3` Declare kt_multiplatform_library along the default KMP hierarchy
    - `platforms`, `<attr>_<qualifier>` lists, `hierarchy.bzl` (`DEFAULT_HIERARCHY`) and `declaration.bzl` (`parse_declaration`).
    - Fragments are named by owner (`common`, `jvm-native`, `apple`, ...), and `KtFragmentInfo.rank`. `262e0f73` replaced
      the fragments of shared labels with aliases.
22. `c3bf80aa` Compile Kotlin/Native klibs through the Build Tools API
    - `experimental_native_build_tools_api` (on by default) and `BtapiKlibCompiler.kt`.
    - `KOTLIN_NATIVE_VERSION = "2.5.20-dev-5696"` is a literal (the JVM compiler stays 2.4.21), with `KOTLIN_NATIVE_BTAPI`,
      `btapi_sha256` and `upgrade_kotlin.sh upgrade-native`.
23. `074283b0` Build and run a Kotlin/Native program with each of its build settings in an integration test
    - `//src/test/integration:native_compilation_modes_test`.
24. `39f8e07c` Build the tools of a Kotlin/Native target for the JVM and fail analysis on inputs konanc and KSP cannot take
    - `kotlin_platform_type` gets `scope = "target"`, and `kt_jvm_tool_transition` goes on the upstream `kt_compiler_plugin`,
      `kt_plugin_cfg` and `kt_ksp_plugin`.
    - Analysis errors for KSP option separators, a source-less binary or framework, and framework names starting with a digit.
25. `212eac0a` Adjust the Kotlin/Native and KMP API after exercising it in scenarios
    - `data` on the native binary and test, and `kt_native_test` links for any staged target.
    - The alias selects on `//kotlin/native/platforms:native`.
    - Removed `KtKlibInfo.cc_info`/`platform`/`module_name` and `kt_klib_import.module_name`, plus the diagnostics for
      never-released macro shapes. Has the "Kept" list (below).
26. `c6263b2b` Trim the comments of the Kotlin/Native and Multiplatform rules that restate code or docs
    - Comments now only give reasons. Docs, Args and Returns stay.
27. `81e7457e` Bring the Kotlin/Native and Kotlin Multiplatform docs in line with the rules and examples
    - Docs match the code, and the CHANGELOG is collapsed to two net entries.
28. `262e0f73` Declare the fragments of a multiplatform library per group and alias, refined by their platforms
    - `qualifiers.bzl`: `resolve_qualifiers` (the targeted nodes and the aliases, `above`, `of_platform`) and `direct`.
    - The order of the Kotlin Toolchain (Amper's `FragmentSeed.compareTo`): the hierarchy first, then a strict subset of
      platforms. An alias of the platforms of a node or of another alias fails.
    - `hierarchy.bzl` exports `name_error`.
    - `parse_declaration(aliases = ...)`, `<attr>_<alias>` lists, and `platform_list` over `qualifiers.of_platform`, which
      keeps a label once when an alias and a group that overlap both list it.
    - `kt_multiplatform_library(aliases = {...})`. `derive_fragments(qualifier_srcs, qualifiers)` makes one fragment per
      group or alias with sources, and `refines` come from `qualifiers.above`.
    - A source in two lists, neither above the other, fails with the list or the alias to move it to.
    - `derive.bzl` moved to the `:multiplatform` `bzl_library`, and `fragment.bzl` has its own default name.
    - `examples/kmp` declares `non_android` as an alias. It is the first step of porting Kotlin Toolchain features.

## Current public surface

- `//kotlin:native.bzl`: `kt_native_library`, `kt_native_binary`, `kt_native_test`, `kt_native_framework`, `kt_klib_import`,
  `KtKlibInfo`.
- `//kotlin:kmp.bzl` (excluded from the release `kotlin` filegroup, as it loads the Android rules): `kt_multiplatform_library`,
  `kt_jvm_ksp_sources`, `kt_native_ksp_sources`.
- Module extensions:
  - `@rules_kotlin//src/main/starlark/core/repositories:native.bzl` `kotlin_native`, with the root-only tags
    `version(version, sha256, btapi_sha256)` and `targets(targets)`.
  - `...:kmp_maven.bzl` `kmp_maven`, with `install(...)` and `resolver(version, sha256)`.
- `kt_multiplatform_library` declares `<name>` (an alias), and `<name>_jvm`, `<name>_android` and `<name>_native` (each
  when `platforms` lists the platform). It also declares the private `<name>_fragment_<f>`, `<name>_srcs` and
  `<name>.fragments`. Its `aliases` name sets of listed platforms outside the hierarchy, which take `srcs`, `deps`,
  `exports` and `plugins` like a group.
- `kmp_fragments`: an attribute of `kt_jvm_library`, `kt_android_library` and `kt_native_library` that the macro sets.
- Platforms: `//kotlin/native/platforms:<konan target>`, plus the config_settings `is_<t>`, `native` and `native_<t>`.
- Build settings in `//kotlin/settings`:
  - `kotlin_platform_type` (`jvm`|`native`, scope `target`)
  - `experimental_native_header_klibs` (off)
  - `experimental_native_build_tools_api` (on)
- Tags: `kt_native_header_klib_incompatible`, and the existing `kt_abi_plugin_incompatible`.
- Exec hosts are `linux-x86_64` and `macos-aarch64`. Konan targets: `linux_x64` and `linux_arm64` on both hosts;
  `macos_arm64`, `ios_arm64` and `ios_simulator_arm64` on macOS only. `ios_x64` is in the hierarchy but rejected in `platforms`.
- Versions:
  - JVM Kotlin `2.4.21` (`versions.bzl`, upstream).
  - Kotlin/Native `2.5.20-dev-5696` (`native_compiler.bzl`), with `2.4.21` selectable through `kotlin_native.version`.
  - bazel-kmp-resolver `0.4.0`, pinned with per-host checksums in `kmp_maven_impl.bzl`.
- Docs:
  - `docs/kmp.md`: the user guide, including a "From Gradle to Bazel" table, Limitations and "Build settings and tags".
  - `docs/kmp_dependencies.md` and `docs/upgrading_kotlin.md`.
  - `docs/kotlin.md`, generated by `bazel run //docs:write_docs` and checked by `//docs:write_docs_test`.
  - The `<!-- BEGIN generated by scripts/upgrade_kotlin.sh ... -->` regions belong to the upgrade tool.

## Where the branch-owned code lives

| Area | Files |
|---|---|
| Native rules | `kotlin/internal/native/`: `library.bzl`, `binary.bzl`, `test.bzl`, `framework.bzl`, `import.bzl`, `link.bzl`, `klib.bzl` (compile and link actions), `providers.bzl`, `toolchains.bzl`, `targets.bzl`, `transition.bzl` |
| KMP | `kotlin/internal/kmp/`: `multiplatform.bzl` (macro), `declaration.bzl`, `hierarchy.bzl`, `qualifiers.bzl`, `derive.bzl`, `fragment.bzl`, `fragments.bzl`, `ksp.bzl`, `ksp_run.sh` |
| Public entry points | `kotlin/native.bzl`, `kotlin/kmp.bzl`, `kotlin/native/platforms/` |
| Repositories | `src/main/starlark/core/repositories/`: `native.bzl` (extension), `native_compiler.bzl` (pins, bundle, cross-check), `kmp_maven.bzl`, `kmp_maven_impl.bzl`, `language_level.bzl` |
| Launcher | `src/main/kotlin/io/bazel/kotlin/native/`: `KonanLauncher.kt`, `BtapiKlibCompiler.kt` |
| Upgrade tool | `src/main/kotlin/io/bazel/kotlin/upgrade/`, `scripts/upgrade_kotlin.sh` |
| Tests | `src/test/starlark/internal/{native,kmp}/`, `src/test/starlark/internal/jvm/{kmp_fragments_test,toolchain_language_level_test}.bzl`, `src/test/starlark/{native_repositories_test,native_konan_properties,kmp_maven_test,kmp_maven_manifest}.bzl`, `src/test/starlark/rules/import_exports_tests.bzl`, `src/test/kotlin/io/bazel/kotlin/{native,upgrade}/`, `src/test/kotlin/io/bazel/kotlin/builder/tasks/AbsoluteFragmentSourcesTest.kt`, `src/test/integration/{CompileAvoidanceTest,NativeCompilationModesTest}.kt` |
| Examples | `examples/native`, `examples/kmp`, `examples/kmp_app` |
| Other | `docs/kmp.md`, `docs/kmp_dependencies.md`, `docs/upgrading_kotlin.md`, `third_party/rules_android_bzl_library_visibility.patch` |

## Upstream files the branch modifies, and why

Keep every hunk in these files traceable to one of these reasons. `scope.sh files` lists the commits of each file.

- **JVM and Android rules**: `kotlin/internal/jvm/`
  - `attrs.bzl`: `kmp_fragments`.
  - `compile.bzl`: fragment flags through `--kotlin_passthrough_flags`, and srcjar/kapt/KSP rejected with fragments.
  - `kt_jvm_library.bzl`: a library of fragments only still makes a jar.
  - `kt_android_library_impl.bzl`: fragments and the coverage fix.
  - `kt_jvm_import.bzl`: `exports` of any JavaInfo.
  - `compiler_plugins.bzl`: `embeddable_classpath`, `kt_jvm_tool_transition`.
  - `kotlin/compiler/kapt.bzl`: an empty `embeddable_classpath`.
  - `BUILD`: bzl_library deps.
- **Providers and worker**:
  - `src/main/starlark/core/plugin/providers.bzl`: `KtCompilerPluginInfo.embeddable_classpath`.
  - `src/main/kotlin/io/bazel/kotlin/builder/tasks/jvm/btapi/BtapiTaskExecutor.kt`: `absoluteFragmentSources`.
- **Language levels and upgrades**:
  - `kotlin/internal/toolchains.bzl` and `src/main/starlark/core/compile/cli/BUILD.bazel`: language and API versions follow
    the compiler release.
  - `src/main/starlark/core/repositories/compiler.bzl`: `version.bzl` with `KOTLINC_VERSION`.
  - `KotlinAbstractTestBuilder.java`, `KotlinJvmTestBuilder.java`: 2.0 becomes 2.2.
  - Root `BUILD`: the ktlint fix target of the upgrade tool.
  - `examples/{android/bzl,dagger,deps/bzl}`: language level 2.3.
- **Settings**: `kotlin/settings/BUILD.bazel` and `BUILD.release.bazel` declare the three settings.
- **Packaging**:
  - `kotlin/BUILD`, `kotlin/BUILD.release.bazel` (keeps `kmp.bzl` out of the release filegroup).
  - `kotlin/internal/BUILD` and `BUILD.release.bazel`.
  - `src/main/kotlin/BUILD` and `BUILD.release.bazel`: the launcher (a `java_binary` in the release).
  - `src/main/starlark/core/repositories/BUILD`.
  - `MODULE.bazel` and `MODULE.release.bazel`: the `kotlin_native` extension and its repositories, the 7 native
    toolchains and apple_support. The release also adds rules_shell, which the root module already had.
  - `MODULE.bazel` alone also uses `kotlin_native_build_tools_api`, the API jar the launcher bundles. It also has the
    rules_android `single_version_override` with its patch, for the docs.
- **CI and tests**:
  - `.bazelci/tests.yml`: no native on Windows, plus a macOS native task.
  - `.bazelrc`: `--deleted_packages` of the example packages.
  - `src/main/kotlin/io/bazel/kotlin/test/BazelIntegrationTestBase.kt`: keeps the exec bit.
  - `src/test/integration/BUILD.bazel`, `src/test/starlark/**/BUILD.bazel`, `src/test/kotlin/.../tasks/BUILD.bazel`,
    `src/test/starlark/rules/plugin_dialect_tests.bzl`.
- **Docs**:
  - `README.md`, `examples/README.md`, `CHANGELOG.md`: summaries that link to `docs/kmp.md`.
  - `CompileAvoidance.md`: the KMP section.
  - `docs/BUILD.bazel`: stardoc.
  - `docs/kotlin.md`: generated.

## Superseded designs: do not reintroduce

- The shell konanc launchers, `bin/konanc`/`run_konan`, and client OS/CPU detection. Use `KonanLauncher` and per-exec-host
  repositories instead.
- `KtNativeInfo`, plus the `KtKlibInfo` fields `cc_info`, `platform` and `module_name`, and `kt_klib_import.module_name`.
- `kt_source_set`, `KtSourceSetInfo`, `source_sets`, `depends_on`, `common_srcs`/`common_deps` and other `common_*` macro
  arguments, `<name>_common`, `<name>_<group>`, source sets in `runtime_deps`, and the `kt_source_set` JavaInfo.
- Per-platform lists inside `jvm`/`android` dicts and native group dicts (`targets = [...]`). Use `platforms` and
  `<attr>_<qualifier>` instead.
- Hub variant names `<lib>_<platform>`. They are now `<lib>.<platform>`.
- ABI jars on by default for fragment libraries. They are gated by `experimental_use_abi_jars` like every library.
- The analysis failure of a `kt_native_test` for a target other than the exec host's. Also the alias of
  `kt_multiplatform_library` selecting its native library on `native_<t>` of each listed target. It now selects on
  `//kotlin/native/platforms:native`.
- `KOTLIN_NATIVE_VERSION` derived from the JVM compiler release.
- Fragments formed by listing one source label in several lists, named after those lists (`jvm-native`), with
  `fragment_name` and the `owners` of a derived fragment. Declare an alias instead (`262e0f73`).
- The fallback for Bazel without `native.package_relative_label`, and diagnostics or migration tables for macro shapes that
  were never released.

## Decisions kept on purpose (212eac0a and earlier)

- No entry-point attribute: use `link_opts = ["-e", "pkg.main"]`. `opts`/`link_opts` are konanc options, so a linker
  argument goes through `-linker-option`.
- `transitive_exports = True` stays the default for frameworks (Bazel `exports` are transitive).
- No analysis check for duplicate klib `unique_name` values: konanc reports both files.
- KSP actions keep the default shell env, the declared `generated` outputs and `-Xmx2g`. Only the KSP release the rules
  pin is supported.
- `select()` is rejected in the lists of the macro. Konan target names are snake_case (`ios_arm64`).
- Aliases list platforms only, never groups, and an alias of the platforms of a group, a platform or another alias is an
  error where the Kotlin Toolchain warns. A dep may be in two lists that are not above each other; a source may not
  (`262e0f73`).
- `examples/native` is a user-facing sample: matrix and flag tests go to `src/test/integration`, not into the example.

## Open ends at the snapshot

- The messages of `1e3c123d` (a folded rename) and `e0f1b4c7` (the resolver) are stale. Reword them only when the user
  asks.
- Kotlin/Native is pinned to the dev build `2.5.20-dev-5696`, for its Build Tools API. `scripts/upgrade_kotlin.sh
  upgrade-native` moves it.
- Linux exec hosts were validated in CI and Docker only. Windows has no Kotlin/Native exec host.
- No example compiles Kotlin/Native with a compiler plugin through the Build Tools API.
- On Bazel 7 and 8, the launcher and KSP tool jars of native targets build in a second exec configuration.
- `bazel run //:buildifier.check` already exited 1 at `074283b0`, with 22 warnings in 16 files, none in the files of the
  latest commits. Check the files you change instead.
- Header klib limits: sealed hierarchies, inline functions. No multiplatform test macro.
- Left for later steps of the Kotlin Toolchain port (`.junie/plans/kotlin-toolchain-features-porting.md`): `opts` and
  `resources` per qualifier, dropping a fragment that only one other refines, `.java` in a fragment of the JVM and
  Android, and deps per fragment.

## How the branch validates a change

- `bazel test //src/... //docs/...` runs the analysis and unit tests, `KonanLauncherTest`, the upgrade tests,
  `compile_avoidance_test` and `native_compilation_modes_test`.
- `bazel run //docs:write_docs` runs after any rule or attr doc change.
- `bazel test //examples:native //examples:kmp //examples:kmp_app` runs the nested Bazel tests against the release archive.
  Inside an example, `bazel test //...` runs with the network off and path mapping on.
- Manual checks: `examples/native/repro_check.sh` (byte-identical outputs across checkout paths) and
  `examples/native/e2e_linux_docker.sh`.
- buildifier `-mode=check -lint=warn` runs on the changed `.bzl`/`BUILD` files, and ktlint on the changed Kotlin.
- The results go under `Evidence:` of the one commit that delivers the change (`delivery.md`); `scope.sh delivery` shows
  the parts of its message.
