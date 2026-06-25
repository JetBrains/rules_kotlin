# Kotlinc options generator

`WriteKotlincCapabilities.kt` generates the Starlark definitions of the Kotlin compiler
options that `kt_kotlinc_options` / the `KotlincOptions` provider expose. It is run as a
Bazel binary and rewrites checked-in template files; it is **not** part of a normal build.

```
bazelisk run //src/main/kotlin/io/bazel/kotlin/generate:kotlin_release_options
```

> Use **bazelisk** so the fork's pinned Bazel (`.bazelversion`, currently `9.0.0`) is used.
> A different system `bazel` (e.g. 8.1.1) will fail the build on a `rules_java` API mismatch.

---

## Main idea

The set of kotlinc flags changes across Kotlin releases — flags are added, stabilized
(`-Xfoo` → `-foo`), and removed. Hand-maintaining the option list against that moving target
drifts and breaks.

Instead, the options are **derived from JetBrains' official
`kotlin-compiler-arguments-description` artifact** — a structured, machine-readable description
of every kotlinc argument (name, type, default, allowed values, and per-version lifecycle). The
generator filters that set through an explicit policy and emits, **per Kotlin version**, a
Starlark file defining a `GENERATED_KOPTS` dict. `opts.kotlinc.bzl` turns that single dict into
the provider fields, the rule attributes, and the flag→CLI conversion.

`GENERATED_KOPTS` is therefore the single source of truth that simultaneously defines:
1. the `KotlincOptions` provider fields,
2. the settable attributes of the `kt_kotlinc_options` rule, and
3. how each value is rendered into a kotlinc command-line flag.

---

## Data flow

```
kotlin-compiler-arguments-description (Maven artifact, matched to the Kotlin release)
        │  Kotlin DSL: kotlinCompilerArguments, KotlinCompilerArgument, removed*CompilerArguments
        ▼
getAllArguments()         walk DSL tree to the JVM args level, merge parent→child, fold in "removed" args
        ▼
per supported version (2.0 … 2.4):
   shouldGenerate()       version lifecycle  ∩  ALLOWLIST  ∖  SUPPRESSED
   toCapability()         DSL arg → KotlincCapability (type, default, enum values, lifecycle)
   pair detection         mark "-Xfoo" DEPRECATED when stable "-foo" exists in this version
        ▼
asGeneratedOptsBzl()      render GENERATED_KOPTS dict + _map_* helpers + custom options
        ▼
generated_opts_<ver>.bzl.com_github_jetbrains_kotlin.bazel   +   templates.bzl   (checked in)
        │  rules_kotlin_extensions repo extension (version-matched)
        ▼
@com_github_jetbrains_kotlin//:generated_opts.bzl   →   GENERATED_KOPTS
        ▼
opts.kotlinc.bzl:  KotlincOptions provider  +  kt_kotlinc_options rule  +  kotlinc_options_to_flags
```

---

## Components

### 1. Input — the arguments-description artifact
Each `KotlinCompilerArgument` carries `name`, a `valueType`
(`BooleanType` / `StringType` / `StringArrayType` / `IntType`), a default, a value description
(used to extract enum choices), and `releaseVersionsMetadata`
(`introducedVersion`, `stabilizedVersion`, `removedVersion`).

`getAllArguments()` finds the path to the JVM compiler-arguments level (`findPathToLevel`),
merges levels so deeper levels override parents, then folds in *removed* arguments that are not
otherwise present — so an older target version still knows about a flag a later Kotlin removed.

### 2. Policy — `FlagPolicy` (allowlist by default)
The editorial control over what is exposed:

- **`SUPPRESSED`** — flags that must *never* be exposed: rules-managed (`-classpath`, `-d`,
  `-module-name`, `-no-stdlib`), plugin flags (`-Xplugin`, `-P` — use `kt_compiler_plugin`),
  the separate Java pipeline, scripting, internal/debug, etc.
- **`ALLOWLIST`** = `BOOLEAN_FLAGS ∪ ENUM_FLAGS ∪ STRING_FLAGS ∪ STRING_LIST_FLAGS ∪ INT_FLAGS`,
  hand-curated and grouped by Starlark type.
- A flag is emitted **iff** `present-in-version ∧ in ALLOWLIST ∧ ∉ SUPPRESSED` (`shouldGenerate`).
  Allowlist-by-default is the safety property: a brand-new compiler flag is **not** auto-exposed
  until it is deliberately added to the allowlist.
- **Stable/experimental pairing:** `deriveStableCounterpart("-Xfoo") → "-foo"`. If both exist in a
  version, the `-X` form is marked `DEPRECATED: Use -foo instead`.

### 3. Version handling
- `SUPPORTED_VERSIONS` = 2.0 … 2.4; one template per version (only 2.0+).
- `shouldIncludeInVersion` applies the introduced/removed lifecycle.
- `getValidJvmTargets` computes the allowed values for `-jvm-target` / `-Xjdk-release` per Kotlin
  version from `JvmTarget` lifecycle metadata, so newer templates list newer JDK targets.

### 4. Capability model + Starlark emission
- **`KotlincCapability`** — normalized model: `flag`, `doc`, `default`, `StarlarkType`
  (`Bool`/`Str`/`StrList`/`Int`), `enumeratedValues`, lifecycle, `deprecatedInFavorOf`.
- **`toCapability()`** maps a DSL argument into it; **`parseEnumeratedValues()`** mines enum choices
  from the description (`{a|b|c}` braces or `-Xfoo=bar` patterns).
- **`starlarkAttrName()`** — naming convention: `-Xcontext-receivers → x_context_receivers`,
  `-java-parameters → java_parameters`.
- **`buildOptStruct()`** emits one option struct:
  - **bool** → `value_to_flag = {True: ["-flag"]}`
  - **string / list / int** → `map_value_to_flag = _map_string_flag("-flag")` (renders `flag=value`);
    enum strings also emit a `values = [...]` list for analysis-time validation.
- **`asGeneratedOptsBzl()`** assembles the file: the `DO NOT EDIT` header, the `_map_*` helper
  functions, then `GENERATED_KOPTS = { …generated entries…, …custom options… }`.
- **Custom options** (`include_stdlibs`, `warn`, `x_warning_level`) are appended by hand because they
  are not 1:1 kotlinc flags — they are abstractions (`include_stdlibs` → `-no-stdlib`/`-no-reflect`;
  `warn` → `-Werror`/`-nowarn`; `x_warning_level` → dict → repeated `-Xwarning-level=k:v`).
- **`BzlDoc` + `bzlQuote()`** — a small Starlark pretty-printer (indentation, structs/dicts/lists,
  triple-quoting for multiline docs).

### 5. Output and downstream consumption
- Per version: `generated_opts_<ver>.bzl.com_github_jetbrains_kotlin.bazel`, plus `templates.bzl`
  listing them (`GENERATED_OPTS_TEMPLATES`). The `--out` dir is normally
  `$BUILD_WORKSPACE_DIRECTORY/src/main/starlark/core/repositories/kotlin` (env-expanded in `main`).
- The `rules_kotlin_extensions` repo extension materializes the version-matched template as
  `@com_github_jetbrains_kotlin//:generated_opts.bzl`.
- `opts.kotlinc.bzl` closes the loop:
  ```python
  _KOPTS = GENERATED_KOPTS
  KotlincOptions = provider(fields = {name: o.args["doc"] for name, o in _KOPTS.items()})
  kt_kotlinc_options = rule(..., attrs = {n: o.type(**o.args) for n, o in _KOPTS.items()})
  def kotlinc_options_to_flags(opts): return convert.javac_options_to_flags(_KOPTS, opts)
  ```
  `convert._to_flags` dispatches per entry: derived/repeated mapper → `value_to_flag` dict lookup
  (bool/enum) → else `map_value_to_flag(value)`.

---

## How to add or change an exposed flag

1. Move/add the flag into the right bucket in `FlagPolicy` — add to one of `BOOLEAN_FLAGS` /
   `ENUM_FLAGS` / `STRING_FLAGS` / `STRING_LIST_FLAGS` / `INT_FLAGS`, and ensure it is **not** in
   `SUPPRESSED`. (To hide a flag, do the opposite.)
2. Regenerate: `bazelisk run //src/main/kotlin/io/bazel/kotlin/generate:kotlin_release_options`.
3. Review the diff in `generated_opts_2.0..2.4.bzl.com_github_jetbrains_kotlin.bazel`.

The metadata (type, default, doc, allowed values) comes from the artifact automatically — no
per-flag wiring is needed.

---

## Bootstrap caveat

The generator binary is itself a `kt_jvm_library` / `kt_jvm_binary`, so it is **built using the very
options it generates** — a bootstrap dependency on the current `GENERATED_KOPTS`. Code that reads
option fields during the compile action (e.g. `_init_builder_args` in
`kotlin/internal/utils/utils.bzl`) must therefore read newly-added fields **defensively**:

```python
# absent field (older templates, mid-transition) → fall back to the toolchain value
api_version = (getattr(kotlinc_options, "api_version", None) if kotlinc_options else None) or toolchain.api_version
```

Direct attribute access (`kotlinc_options.api_version`) would make the generator impossible to
build until the field it is about to add already exists in the templates.

---

## Key files

| File | Role |
|------|------|
| `src/main/kotlin/io/bazel/kotlin/generate/WriteKotlincCapabilities.kt` | The generator (this dir) |
| `src/main/kotlin/io/bazel/kotlin/generate/BUILD.bazel` | `kotlin_release_options` target + artifact deps |
| `src/main/starlark/core/repositories/kotlin/generated_opts_<ver>.bzl.com_github_jetbrains_kotlin.bazel` | Generated templates (`GENERATED_KOPTS`) |
| `src/main/starlark/core/repositories/kotlin/templates.bzl` | Generated list of templates |
| `src/main/starlark/core/options/opts.kotlinc.bzl` | Builds provider + rule + `kotlinc_options_to_flags` from `GENERATED_KOPTS` |
| `src/main/starlark/core/options/convert.bzl` | `value_to_flag` / `map_value_to_flag` dispatch |
