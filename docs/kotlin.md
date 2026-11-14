<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Public Kotlin/JVM rule API.

<a id="kt_javac_options"></a>

## kt_javac_options

<pre>
load("@rules_kotlin//kotlin:jvm.bzl", "kt_javac_options")

kt_javac_options(<a href="#kt_javac_options-name">name</a>, <a href="#kt_javac_options-add_exports">add_exports</a>, <a href="#kt_javac_options-no_proc">no_proc</a>, <a href="#kt_javac_options-release">release</a>, <a href="#kt_javac_options-warn">warn</a>, <a href="#kt_javac_options-x_ep_disable_all_checks">x_ep_disable_all_checks</a>,
                 <a href="#kt_javac_options-x_explicit_api_mode">x_explicit_api_mode</a>, <a href="#kt_javac_options-x_lint">x_lint</a>, <a href="#kt_javac_options-xd_suppress_notes">xd_suppress_notes</a>)
</pre>

Define java compiler options for `kt_jvm_*` rules with java sources.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kt_javac_options-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kt_javac_options-add_exports"></a>add_exports |  Export internal jdk apis   | List of strings | optional |  `[]`  |
| <a id="kt_javac_options-no_proc"></a>no_proc |  Disable java annotation processing (javac -proc:none). The Java half of a target with Kotlin sources is always compiled with -proc:none (Kotlin owns annotation processing there); this option extends that to Java-only kt_jvm_* targets.   | Boolean | optional |  `False`  |
| <a id="kt_javac_options-release"></a>release |  Compile for the specified Java SE release   | String | optional |  `"default"`  |
| <a id="kt_javac_options-warn"></a>warn |  Control warning behaviour.   | String | optional |  `"report"`  |
| <a id="kt_javac_options-x_ep_disable_all_checks"></a>x_ep_disable_all_checks |  See javac -XepDisableAllChecks documentation   | Boolean | optional |  `False`  |
| <a id="kt_javac_options-x_explicit_api_mode"></a>x_explicit_api_mode |  Enable explicit API mode for Kotlin libraries.   | String | optional |  `"off"`  |
| <a id="kt_javac_options-x_lint"></a>x_lint |  See javac -Xlint: documentation   | List of strings | optional |  `[]`  |
| <a id="kt_javac_options-xd_suppress_notes"></a>xd_suppress_notes |  See javac -XDsuppressNotes documentation   | Boolean | optional |  `False`  |


<a id="kt_jvm_binary"></a>

## kt_jvm_binary

<pre>
load("@rules_kotlin//kotlin:jvm.bzl", "kt_jvm_binary")

kt_jvm_binary(<a href="#kt_jvm_binary-name">name</a>, <a href="#kt_jvm_binary-deps">deps</a>, <a href="#kt_jvm_binary-srcs">srcs</a>, <a href="#kt_jvm_binary-data">data</a>, <a href="#kt_jvm_binary-resources">resources</a>, <a href="#kt_jvm_binary-associates">associates</a>, <a href="#kt_jvm_binary-env">env</a>, <a href="#kt_jvm_binary-env_inherit">env_inherit</a>, <a href="#kt_jvm_binary-java_stub_template">java_stub_template</a>,
              <a href="#kt_jvm_binary-javac_opts">javac_opts</a>, <a href="#kt_jvm_binary-jvm_flags">jvm_flags</a>, <a href="#kt_jvm_binary-kotlinc_opts">kotlinc_opts</a>, <a href="#kt_jvm_binary-main_class">main_class</a>, <a href="#kt_jvm_binary-manifest_lines">manifest_lines</a>, <a href="#kt_jvm_binary-module_name">module_name</a>, <a href="#kt_jvm_binary-plugins">plugins</a>,
              <a href="#kt_jvm_binary-resource_jars">resource_jars</a>, <a href="#kt_jvm_binary-resource_strip_prefix">resource_strip_prefix</a>, <a href="#kt_jvm_binary-runtime_deps">runtime_deps</a>)
</pre>

Builds a Java archive ("jar file"), plus a wrapper shell script with the same name as the rule. The wrapper
shell script uses a classpath that includes, among other things, a jar file for each library on which the binary
depends.

**Note:** This rule does not have all of the features found in [`java_binary`](https://docs.bazel.build/versions/master/be/java.html#java_binary).
It is appropriate for building workspace utilities. `java_binary` should be preferred for release artefacts.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kt_jvm_binary-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kt_jvm_binary-deps"></a>deps |  A list of dependencies of this rule.See general comments about `deps` at [Attributes common to all build rules](https://docs.bazel.build/versions/master/be/common-definitions.html#common-attributes).   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_binary-srcs"></a>srcs |  The list of source files that are processed to create the target, this can contain both Java and Kotlin files. Java analysis occurs first so Kotlin classes may depend on Java classes in the same compilation unit.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_binary-data"></a>data |  The list of files needed by this rule at runtime. See general comments about `data` at [Attributes common to all build rules](https://docs.bazel.build/versions/master/be/common-definitions.html#common-attributes).   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_binary-resources"></a>resources |  A list of files that should be include in a Java jar.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_binary-associates"></a>associates |  Kotlin deps who should be considered part of the same module/compilation-unit for the purposes of "internal" access. Such deps must all share the same module space and so a target cannot associate to two deps from two different modules.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_binary-env"></a>env |  Environment variables to set when this binary is executed with `bazel run`. Subject to $(location) and "Make variable" substitution.   | <a href="https://bazel.build/rules/lib/core/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="kt_jvm_binary-env_inherit"></a>env_inherit |  Names of environment variables to inherit from the shell when executed with `bazel run`.   | List of strings | optional |  `[]`  |
| <a id="kt_jvm_binary-java_stub_template"></a>java_stub_template |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `"@rules_kotlin//third_party:java_stub_template.txt"`  |
| <a id="kt_jvm_binary-javac_opts"></a>javac_opts |  Javac options to be used when compiling this target. These opts if provided will be used instead of the ones provided to the toolchain.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kt_jvm_binary-jvm_flags"></a>jvm_flags |  A list of flags to embed in the wrapper script generated for running this binary. Note: does not yet support make variable substitution.   | List of strings | optional |  `[]`  |
| <a id="kt_jvm_binary-kotlinc_opts"></a>kotlinc_opts |  Kotlinc options to be used when compiling this target. These opts if provided will be used instead of the ones provided to the toolchain.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kt_jvm_binary-main_class"></a>main_class |  Name of class with main() method to use as entry point.   | String | required |  |
| <a id="kt_jvm_binary-manifest_lines"></a>manifest_lines |  Lines to add to the main section of the manifest of the output jar, each in the form `Name: value`. They follow the `Target-Label` and `Injecting-Rule-Kind` attributes the rules write. A line that repeats them, `Manifest-Version` or `Created-By` is rejected. As in the `deploy_manifest_lines` attribute of `java_binary`, `Multi-Release`, `Add-Exports` and `Add-Opens` lines are not copied as they are: singlejar merges them and writes them in its normalized form, and `Multi-Release` takes `true` or `false`. A target without `srcs` and `resources` (and, for a library, `kmp_fragments`) has no jar of its own and rejects the attribute.   | List of strings | optional |  `[]`  |
| <a id="kt_jvm_binary-module_name"></a>module_name |  The name of the module, if not provided the module name is derived from the label. --e.g., `//some/package/path:label_name` is translated to `some_package_path-label_name`.   | String | optional |  `""`  |
| <a id="kt_jvm_binary-plugins"></a>plugins |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_binary-resource_jars"></a>resource_jars |  Set of archives containing Java resources. If specified, the contents of these jars are merged into the output jar.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_binary-resource_strip_prefix"></a>resource_strip_prefix |  The path prefix to strip from Java resources. Should be a label pointing to a directory. Files residing under common prefix such as `src/main/resources` or `src/test/resources` or `kotlin` will have stripping applied by convention if this is not specified.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kt_jvm_binary-runtime_deps"></a>runtime_deps |  Libraries to make available to the final binary or test at runtime only. Like ordinary deps, these will appear on the runtime classpath, but unlike them, not on the compile-time classpath.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="kt_jvm_import"></a>

## kt_jvm_import

<pre>
load("@rules_kotlin//kotlin:jvm.bzl", "kt_jvm_import")

kt_jvm_import(<a href="#kt_jvm_import-name">name</a>, <a href="#kt_jvm_import-deps">deps</a>, <a href="#kt_jvm_import-exported_compiler_plugins">exported_compiler_plugins</a>, <a href="#kt_jvm_import-exports">exports</a>, <a href="#kt_jvm_import-jar">jar</a>, <a href="#kt_jvm_import-jars">jars</a>, <a href="#kt_jvm_import-neverlink">neverlink</a>, <a href="#kt_jvm_import-runtime_deps">runtime_deps</a>,
              <a href="#kt_jvm_import-srcjar">srcjar</a>)
</pre>

Import Kotlin jars.

## examples

```bzl
# Old style usage -- reference file groups, do not used this.
kt_jvm_import(
    name = "kodein",
    jars = [
        "@com_github_salomonbrys_kodein_kodein//jar:file",
        "@com_github_salomonbrys_kodein_kodein_core//jar:file"
    ]
)

# This style will pull in the transitive runtime dependencies of the targets as well.
kt_jvm_import(
    name = "kodein",
    jars = [
        "@com_github_salomonbrys_kodein_kodein//jar",
        "@com_github_salomonbrys_kodein_kodein_core//jar"
    ]
)

# Import a single kotlin jar.
kt_jvm_import(
    name = "kotlin-stdlib",
    jars = ["lib/kotlin-stdlib.jar"],
    srcjar = "lib/kotlin-stdlib-sources.jar"
)
```

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kt_jvm_import-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kt_jvm_import-deps"></a>deps |  Compile and runtime dependencies   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_import-exported_compiler_plugins"></a>exported_compiler_plugins |  Exported compiler plugins.<br><br>Compiler plugins listed here will be treated as if they were added in the plugins attribute of any targets that directly depend on this target. Like java_plugins' exported_plugins, this is not transitive   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_import-exports"></a>exports |  Exported libraries.<br><br>Deps listed here will be made available to other rules, as if the parents explicitly depended on these deps. This is not true for regular (non-exported) deps. Any JVM library qualifies, as for `kt_jvm_library`: a `java_import` or an `aar_import` as well as a Kotlin target.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_import-jar"></a>jar |  The jar listed here is equivalent to an export attribute.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kt_jvm_import-jars"></a>jars |  The jars listed here are equavalent to an export attribute. The label should be either to a single class jar, or one or more filegroup labels.  The filegroups, when resolved, must contain  only one jar containing classes, and (optionally) one peer file containing sources, named `<jarname>-sources.jar`.<br><br>DEPRECATED - please use `jar` and `srcjar` attributes.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_import-neverlink"></a>neverlink |  If true only use this library for compilation and not at runtime.   | Boolean | optional |  `False`  |
| <a id="kt_jvm_import-runtime_deps"></a>runtime_deps |  Additional runtime deps.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_import-srcjar"></a>srcjar |  The sources for the class jar.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `"@rules_kotlin//third_party:empty.jar"`  |


<a id="kt_jvm_library"></a>

## kt_jvm_library

<pre>
load("@rules_kotlin//kotlin:jvm.bzl", "kt_jvm_library")

kt_jvm_library(<a href="#kt_jvm_library-name">name</a>, <a href="#kt_jvm_library-deps">deps</a>, <a href="#kt_jvm_library-srcs">srcs</a>, <a href="#kt_jvm_library-data">data</a>, <a href="#kt_jvm_library-resources">resources</a>, <a href="#kt_jvm_library-associates">associates</a>, <a href="#kt_jvm_library-exported_compiler_plugins">exported_compiler_plugins</a>, <a href="#kt_jvm_library-exports">exports</a>,
               <a href="#kt_jvm_library-java_stub_template">java_stub_template</a>, <a href="#kt_jvm_library-javac_opts">javac_opts</a>, <a href="#kt_jvm_library-kmp_fragments">kmp_fragments</a>, <a href="#kt_jvm_library-kotlinc_opts">kotlinc_opts</a>, <a href="#kt_jvm_library-manifest_lines">manifest_lines</a>,
               <a href="#kt_jvm_library-module_name">module_name</a>, <a href="#kt_jvm_library-neverlink">neverlink</a>, <a href="#kt_jvm_library-plugins">plugins</a>, <a href="#kt_jvm_library-resource_jars">resource_jars</a>, <a href="#kt_jvm_library-resource_strip_prefix">resource_strip_prefix</a>, <a href="#kt_jvm_library-runtime_deps">runtime_deps</a>)
</pre>

This rule compiles and links Kotlin and Java sources into a .jar file.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kt_jvm_library-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kt_jvm_library-deps"></a>deps |  A list of dependencies of this rule.See general comments about `deps` at [Attributes common to all build rules](https://docs.bazel.build/versions/master/be/common-definitions.html#common-attributes).   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_library-srcs"></a>srcs |  The list of source files that are processed to create the target, this can contain both Java and Kotlin files. Java analysis occurs first so Kotlin classes may depend on Java classes in the same compilation unit.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_library-data"></a>data |  The list of files needed by this rule at runtime. See general comments about `data` at [Attributes common to all build rules](https://docs.bazel.build/versions/master/be/common-definitions.html#common-attributes).   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_library-resources"></a>resources |  A list of files that should be include in a Java jar.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_library-associates"></a>associates |  Kotlin deps who should be considered part of the same module/compilation-unit for the purposes of "internal" access. Such deps must all share the same module space and so a target cannot associate to two deps from two different modules.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_library-exported_compiler_plugins"></a>exported_compiler_plugins |  Exported compiler plugins.<br><br>Compiler plugins listed here will be treated as if they were added in the plugins attribute of any targets that directly depend on this target. Like `java_plugin`s exported_plugins, this is not transitive   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_library-exports"></a>exports |  Exported libraries.<br><br>Deps listed here will be made available to other rules, as if the parents explicitly depended on these deps. This is not true for regular (non-exported) deps.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_library-java_stub_template"></a>java_stub_template |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `"@rules_kotlin//third_party:java_stub_template.txt"`  |
| <a id="kt_jvm_library-javac_opts"></a>javac_opts |  Javac options to be used when compiling this target. These opts if provided will be used instead of the ones provided to the toolchain.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kt_jvm_library-kmp_fragments"></a>kmp_fragments |  The K2 fragments of a `kt_multiplatform_library` that the srcs refine: the sources the library shares with other platforms. `kt_multiplatform_library` sets it from the sources each platform lists; it is not set by hand. The Kotlin sources of the fragments, and of the fragments they refine, compile with the srcs in one compilation (`-Xmulti-platform`), against the deps of the target, so the `actual` declarations of the srcs implement the `expect` ones of the fragments; the srcs are the leaf fragment, `jvm` or `android`. A target with fragments cannot have .srcjar sources, kapt or KSP, whose sources would belong to no fragment. Expect/actual classes are Beta in Kotlin: the rule passes `-Xexpect-actual-classes`, which acknowledges it.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_library-kotlinc_opts"></a>kotlinc_opts |  Kotlinc options to be used when compiling this target. These opts if provided will be used instead of the ones provided to the toolchain.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kt_jvm_library-manifest_lines"></a>manifest_lines |  Lines to add to the main section of the manifest of the output jar, each in the form `Name: value`. They follow the `Target-Label` and `Injecting-Rule-Kind` attributes the rules write. A line that repeats them, `Manifest-Version` or `Created-By` is rejected. As in the `deploy_manifest_lines` attribute of `java_binary`, `Multi-Release`, `Add-Exports` and `Add-Opens` lines are not copied as they are: singlejar merges them and writes them in its normalized form, and `Multi-Release` takes `true` or `false`. A target without `srcs` and `resources` (and, for a library, `kmp_fragments`) has no jar of its own and rejects the attribute.   | List of strings | optional |  `[]`  |
| <a id="kt_jvm_library-module_name"></a>module_name |  The name of the module, if not provided the module name is derived from the label. --e.g., `//some/package/path:label_name` is translated to `some_package_path-label_name`.   | String | optional |  `""`  |
| <a id="kt_jvm_library-neverlink"></a>neverlink |  If true only use this library for compilation and not at runtime.   | Boolean | optional |  `False`  |
| <a id="kt_jvm_library-plugins"></a>plugins |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_library-resource_jars"></a>resource_jars |  Set of archives containing Java resources. If specified, the contents of these jars are merged into the output jar.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_library-resource_strip_prefix"></a>resource_strip_prefix |  The path prefix to strip from Java resources. Should be a label pointing to a directory. Files residing under common prefix such as `src/main/resources` or `src/test/resources` or `kotlin` will have stripping applied by convention if this is not specified.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kt_jvm_library-runtime_deps"></a>runtime_deps |  Libraries to make available to the final binary or test at runtime only. Like ordinary deps, these will appear on the runtime classpath, but unlike them, not on the compile-time classpath.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="kt_jvm_test"></a>

## kt_jvm_test

<pre>
load("@rules_kotlin//kotlin:jvm.bzl", "kt_jvm_test")

kt_jvm_test(<a href="#kt_jvm_test-name">name</a>, <a href="#kt_jvm_test-deps">deps</a>, <a href="#kt_jvm_test-srcs">srcs</a>, <a href="#kt_jvm_test-data">data</a>, <a href="#kt_jvm_test-resources">resources</a>, <a href="#kt_jvm_test-associates">associates</a>, <a href="#kt_jvm_test-env">env</a>, <a href="#kt_jvm_test-env_inherit">env_inherit</a>, <a href="#kt_jvm_test-java_stub_template">java_stub_template</a>,
            <a href="#kt_jvm_test-javac_opts">javac_opts</a>, <a href="#kt_jvm_test-jvm_flags">jvm_flags</a>, <a href="#kt_jvm_test-kotlinc_opts">kotlinc_opts</a>, <a href="#kt_jvm_test-main_class">main_class</a>, <a href="#kt_jvm_test-manifest_lines">manifest_lines</a>, <a href="#kt_jvm_test-module_name">module_name</a>, <a href="#kt_jvm_test-plugins">plugins</a>,
            <a href="#kt_jvm_test-resource_jars">resource_jars</a>, <a href="#kt_jvm_test-resource_strip_prefix">resource_strip_prefix</a>, <a href="#kt_jvm_test-runtime_deps">runtime_deps</a>, <a href="#kt_jvm_test-test_class">test_class</a>)
</pre>

Setup a simple kotlin_test.

**Notes:**
* The kotlin test library is not added implicitly, it is available with the label
`@rules_kotlin//kotlin/compiler:kotlin-test`.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kt_jvm_test-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kt_jvm_test-deps"></a>deps |  A list of dependencies of this rule.See general comments about `deps` at [Attributes common to all build rules](https://docs.bazel.build/versions/master/be/common-definitions.html#common-attributes).   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_test-srcs"></a>srcs |  The list of source files that are processed to create the target, this can contain both Java and Kotlin files. Java analysis occurs first so Kotlin classes may depend on Java classes in the same compilation unit.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_test-data"></a>data |  The list of files needed by this rule at runtime. See general comments about `data` at [Attributes common to all build rules](https://docs.bazel.build/versions/master/be/common-definitions.html#common-attributes).   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_test-resources"></a>resources |  A list of files that should be include in a Java jar.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_test-associates"></a>associates |  Kotlin deps who should be considered part of the same module/compilation-unit for the purposes of "internal" access. Such deps must all share the same module space and so a target cannot associate to two deps from two different modules.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_test-env"></a>env |  Specifies additional environment variables to set when the target is executed by bazel test. Subject to $(location) and "Make variable" substitution.   | <a href="https://bazel.build/rules/lib/core/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="kt_jvm_test-env_inherit"></a>env_inherit |  Environment variables to inherit from the external environment.   | List of strings | optional |  `[]`  |
| <a id="kt_jvm_test-java_stub_template"></a>java_stub_template |  -   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `"@rules_kotlin//third_party:java_stub_template.txt"`  |
| <a id="kt_jvm_test-javac_opts"></a>javac_opts |  Javac options to be used when compiling this target. These opts if provided will be used instead of the ones provided to the toolchain.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kt_jvm_test-jvm_flags"></a>jvm_flags |  A list of flags to embed in the wrapper script generated for running this binary. Note: does not yet support make variable substitution.   | List of strings | optional |  `[]`  |
| <a id="kt_jvm_test-kotlinc_opts"></a>kotlinc_opts |  Kotlinc options to be used when compiling this target. These opts if provided will be used instead of the ones provided to the toolchain.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kt_jvm_test-main_class"></a>main_class |  -   | String | optional |  `"com.google.testing.junit.runner.BazelTestRunner"`  |
| <a id="kt_jvm_test-manifest_lines"></a>manifest_lines |  Lines to add to the main section of the manifest of the output jar, each in the form `Name: value`. They follow the `Target-Label` and `Injecting-Rule-Kind` attributes the rules write. A line that repeats them, `Manifest-Version` or `Created-By` is rejected. As in the `deploy_manifest_lines` attribute of `java_binary`, `Multi-Release`, `Add-Exports` and `Add-Opens` lines are not copied as they are: singlejar merges them and writes them in its normalized form, and `Multi-Release` takes `true` or `false`. A target without `srcs` and `resources` (and, for a library, `kmp_fragments`) has no jar of its own and rejects the attribute.   | List of strings | optional |  `[]`  |
| <a id="kt_jvm_test-module_name"></a>module_name |  The name of the module, if not provided the module name is derived from the label. --e.g., `//some/package/path:label_name` is translated to `some_package_path-label_name`.   | String | optional |  `""`  |
| <a id="kt_jvm_test-plugins"></a>plugins |  -   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_test-resource_jars"></a>resource_jars |  Set of archives containing Java resources. If specified, the contents of these jars are merged into the output jar.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_test-resource_strip_prefix"></a>resource_strip_prefix |  The path prefix to strip from Java resources. Should be a label pointing to a directory. Files residing under common prefix such as `src/main/resources` or `src/test/resources` or `kotlin` will have stripping applied by convention if this is not specified.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kt_jvm_test-runtime_deps"></a>runtime_deps |  Libraries to make available to the final binary or test at runtime only. Like ordinary deps, these will appear on the runtime classpath, but unlike them, not on the compile-time classpath.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_test-test_class"></a>test_class |  The Java class to be loaded by the test runner.   | String | optional |  `""`  |


<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Public ktlint rules.

<a id="ktlint_config"></a>

## ktlint_config

<pre>
load("@rules_kotlin//kotlin:lint.bzl", "ktlint_config")

ktlint_config(<a href="#ktlint_config-name">name</a>, <a href="#ktlint_config-android_rules_enabled">android_rules_enabled</a>, <a href="#ktlint_config-editorconfig">editorconfig</a>, <a href="#ktlint_config-experimental_rules_enabled">experimental_rules_enabled</a>)
</pre>

Used to configure ktlint.

`ktlint` can be configured to use a `.editorconfig`, as documented at
https://github.com/pinterest/ktlint/#editorconfig

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="ktlint_config-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="ktlint_config-android_rules_enabled"></a>android_rules_enabled |  Turn on Android Kotlin Style Guide compatibility   | Boolean | optional |  `False`  |
| <a id="ktlint_config-editorconfig"></a>editorconfig |  Editor config file to use   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="ktlint_config-experimental_rules_enabled"></a>experimental_rules_enabled |  Turn on experimental rules (ktlint-ruleset-experimental)   | Boolean | optional |  `False`  |


<a id="ktlint_fix"></a>

## ktlint_fix

<pre>
load("@rules_kotlin//kotlin:lint.bzl", "ktlint_fix")

ktlint_fix(<a href="#ktlint_fix-name">name</a>, <a href="#ktlint_fix-srcs">srcs</a>, <a href="#ktlint_fix-config">config</a>)
</pre>

Lint Kotlin files and automatically fix them as needed

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="ktlint_fix-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="ktlint_fix-srcs"></a>srcs |  Source files to review and fix   | <a href="https://bazel.build/concepts/labels">List of labels</a> | required |  |
| <a id="ktlint_fix-config"></a>config |  ktlint_config to use   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |


<a id="ktlint_test"></a>

## ktlint_test

<pre>
load("@rules_kotlin//kotlin:lint.bzl", "ktlint_test")

ktlint_test(<a href="#ktlint_test-name">name</a>, <a href="#ktlint_test-srcs">srcs</a>, <a href="#ktlint_test-config">config</a>)
</pre>

Lint Kotlin files, and fail if the linter raises errors.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="ktlint_test-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="ktlint_test-srcs"></a>srcs |  Source files to lint   | <a href="https://bazel.build/concepts/labels">List of labels</a> | required |  |
| <a id="ktlint_test-config"></a>config |  ktlint_config to use   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |


<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Core Kotlin rule and providers.

<a id="kt_btapi_runtime"></a>

## kt_btapi_runtime

<pre>
load("@rules_kotlin//kotlin:core.bzl", "kt_btapi_runtime")

kt_btapi_runtime(<a href="#kt_btapi_runtime-name">name</a>, <a href="#kt_btapi_runtime-base">base</a>, <a href="#kt_btapi_runtime-build_tools_impl">build_tools_impl</a>, <a href="#kt_btapi_runtime-compiler">compiler</a>, <a href="#kt_btapi_runtime-jdeps_gen">jdeps_gen</a>, <a href="#kt_btapi_runtime-jvm_abi_gen">jvm_abi_gen</a>, <a href="#kt_btapi_runtime-kapt">kapt</a>, <a href="#kt_btapi_runtime-libraries">libraries</a>)
</pre>

The Build Tools API compilation runtime: the jars the worker loads into the Build Tools
API classloader, and the internal compiler plugins it passes to the compiler. Every jar is the
embeddable compiler dialect (the Maven-published form of the compiler and its plugins), because
the Build Tools implementation is published in that dialect only.

An artifact that is not set is inherited from `base`, so a runtime that replaces one artifact
states only that artifact. The default runtime, `//kotlin/compiler:btapi_runtime`, takes every
artifact from the configured Kotlin release.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kt_btapi_runtime-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kt_btapi_runtime-base"></a>base |  The runtime that provides every artifact this target does not set.   | <a href="https://bazel.build/concepts/labels">Label</a> | optional |  `None`  |
| <a id="kt_btapi_runtime-build_tools_impl"></a>build_tools_impl |  The Build Tools implementation.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_btapi_runtime-compiler"></a>compiler |  The compiler, embeddable dialect.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_btapi_runtime-jdeps_gen"></a>jdeps_gen |  The jdeps-gen compiler plugin, embeddable dialect.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_btapi_runtime-jvm_abi_gen"></a>jvm_abi_gen |  The jvm-abi-gen compiler plugin, embeddable dialect.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_btapi_runtime-kapt"></a>kapt |  The kapt compiler plugin, embeddable dialect.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_btapi_runtime-libraries"></a>libraries |  The libraries the implementation and the compiler need.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="kt_compiler_plugin"></a>

## kt_compiler_plugin

<pre>
load("@rules_kotlin//kotlin:core.bzl", "kt_compiler_plugin")

kt_compiler_plugin(<a href="#kt_compiler_plugin-name">name</a>, <a href="#kt_compiler_plugin-deps">deps</a>, <a href="#kt_compiler_plugin-data">data</a>, <a href="#kt_compiler_plugin-compile_phase">compile_phase</a>, <a href="#kt_compiler_plugin-id">id</a>, <a href="#kt_compiler_plugin-options">options</a>, <a href="#kt_compiler_plugin-stubs_phase">stubs_phase</a>,
                   <a href="#kt_compiler_plugin-target_embedded_compiler">target_embedded_compiler</a>)
</pre>

Define a plugin for the Kotlin compiler to run. The plugin can then be referenced in the `plugins` attribute
of the `kt_jvm_*` rules.

An example can be found under `//examples/plugin`:

```bzl
kt_compiler_plugin(
    name = "open_for_testing_plugin",
    id = "org.jetbrains.kotlin.allopen",
    options = {
        "annotation": ["plugin.OpenForTesting"],
    },
    deps = [
        "//kotlin/compiler:allopen-compiler-plugin",
    ],
)

kt_jvm_library(
    name = "open_for_testing",
    srcs = ["OpenForTesting.kt"],
)

kt_jvm_library(
    name = "user",
    srcs = ["User.kt"],
    plugins = [":open_for_testing_plugin"],
    deps = [
        ":open_for_testing",
    ],
)
```

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kt_compiler_plugin-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kt_compiler_plugin-deps"></a>deps |  The list of libraries to be added to the compiler's plugin classpath. The plugin classpath is the transitive runtime classpath of these libraries. A neverlink library therefore contributes nothing to it, and neither does a library reachable only through a neverlink library.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_compiler_plugin-data"></a>data |  The files the plugin reads at compile time. An option value names one of them as `$(location <file>)`. The files and the runfiles of each listed target are inputs of the compilation.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_compiler_plugin-compile_phase"></a>compile_phase |  Runs the compiler plugin during kotlin compilation. Known examples: `allopen`, `sam_with_reciever`   | Boolean | optional |  `True`  |
| <a id="kt_compiler_plugin-id"></a>id |  The ID of the plugin   | String | required |  |
| <a id="kt_compiler_plugin-options"></a>options |  Dictionary of options to be passed to the plugin. Each option key can have multiple values. Supports the following template values:<br><br>- `{generatedClasses}`: directory for generated class output - `{temp}`: temporary directory, discarded between invocations - `{generatedSources}`:  directory for generated source output - `{classpath}` : replaced with a list of jars separated by the filesystem appropriate separator.   | <a href="https://bazel.build/rules/lib/core/dict">Dictionary: String -> List of strings</a> | optional |  `{}`  |
| <a id="kt_compiler_plugin-stubs_phase"></a>stubs_phase |  Runs the compiler plugin in kapt stub generation.   | Boolean | optional |  `True`  |
| <a id="kt_compiler_plugin-target_embedded_compiler"></a>target_embedded_compiler |  Plugin was compiled against the embeddable kotlin compiler. The plugin classpath is reshaded when this dialect differs from the dialect of the compiler that the toolchain runs. The aspect declares the reshaded copies for the libraries that deps, runtime_deps, exports or associates reach. A jar without a copy stays as it is.   | Boolean | optional |  `False`  |


<a id="kt_javac_options"></a>

## kt_javac_options

<pre>
load("@rules_kotlin//kotlin:core.bzl", "kt_javac_options")

kt_javac_options(<a href="#kt_javac_options-name">name</a>, <a href="#kt_javac_options-add_exports">add_exports</a>, <a href="#kt_javac_options-no_proc">no_proc</a>, <a href="#kt_javac_options-release">release</a>, <a href="#kt_javac_options-warn">warn</a>, <a href="#kt_javac_options-x_ep_disable_all_checks">x_ep_disable_all_checks</a>,
                 <a href="#kt_javac_options-x_explicit_api_mode">x_explicit_api_mode</a>, <a href="#kt_javac_options-x_lint">x_lint</a>, <a href="#kt_javac_options-xd_suppress_notes">xd_suppress_notes</a>)
</pre>

Define java compiler options for `kt_jvm_*` rules with java sources.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kt_javac_options-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kt_javac_options-add_exports"></a>add_exports |  Export internal jdk apis   | List of strings | optional |  `[]`  |
| <a id="kt_javac_options-no_proc"></a>no_proc |  Disable java annotation processing (javac -proc:none). The Java half of a target with Kotlin sources is always compiled with -proc:none (Kotlin owns annotation processing there); this option extends that to Java-only kt_jvm_* targets.   | Boolean | optional |  `False`  |
| <a id="kt_javac_options-release"></a>release |  Compile for the specified Java SE release   | String | optional |  `"default"`  |
| <a id="kt_javac_options-warn"></a>warn |  Control warning behaviour.   | String | optional |  `"report"`  |
| <a id="kt_javac_options-x_ep_disable_all_checks"></a>x_ep_disable_all_checks |  See javac -XepDisableAllChecks documentation   | Boolean | optional |  `False`  |
| <a id="kt_javac_options-x_explicit_api_mode"></a>x_explicit_api_mode |  Enable explicit API mode for Kotlin libraries.   | String | optional |  `"off"`  |
| <a id="kt_javac_options-x_lint"></a>x_lint |  See javac -Xlint: documentation   | List of strings | optional |  `[]`  |
| <a id="kt_javac_options-xd_suppress_notes"></a>xd_suppress_notes |  See javac -XDsuppressNotes documentation   | Boolean | optional |  `False`  |


<a id="kt_kotlinc_options"></a>

## kt_kotlinc_options

<pre>
load("@rules_kotlin//kotlin:core.bzl", "kt_kotlinc_options")

kt_kotlinc_options(<a href="#kt_kotlinc_options-name">name</a>, <a href="#kt_kotlinc_options-api_version">api_version</a>, <a href="#kt_kotlinc_options-include_stdlibs">include_stdlibs</a>, <a href="#kt_kotlinc_options-java_parameters">java_parameters</a>, <a href="#kt_kotlinc_options-jvm_default">jvm_default</a>, <a href="#kt_kotlinc_options-jvm_target">jvm_target</a>,
                   <a href="#kt_kotlinc_options-language_version">language_version</a>, <a href="#kt_kotlinc_options-progressive">progressive</a>, <a href="#kt_kotlinc_options-warn">warn</a>, <a href="#kt_kotlinc_options-x_allow_kotlin_package">x_allow_kotlin_package</a>,
                   <a href="#kt_kotlinc_options-x_allow_unstable_dependencies">x_allow_unstable_dependencies</a>, <a href="#kt_kotlinc_options-x_annotation_default_target">x_annotation_default_target</a>, <a href="#kt_kotlinc_options-x_assertions">x_assertions</a>,
                   <a href="#kt_kotlinc_options-x_backend_threads">x_backend_threads</a>, <a href="#kt_kotlinc_options-x_compiler_plugin_order">x_compiler_plugin_order</a>,
                   <a href="#kt_kotlinc_options-x_consistent_data_class_copy_visibility">x_consistent_data_class_copy_visibility</a>, <a href="#kt_kotlinc_options-x_context_parameters">x_context_parameters</a>, <a href="#kt_kotlinc_options-x_context_receivers">x_context_receivers</a>,
                   <a href="#kt_kotlinc_options-x_emit_jvm_type_annotations">x_emit_jvm_type_annotations</a>, <a href="#kt_kotlinc_options-x_enable_incremental_compilation">x_enable_incremental_compilation</a>, <a href="#kt_kotlinc_options-x_explicit_api_mode">x_explicit_api_mode</a>,
                   <a href="#kt_kotlinc_options-x_inline_classes">x_inline_classes</a>, <a href="#kt_kotlinc_options-x_jdk_release">x_jdk_release</a>, <a href="#kt_kotlinc_options-x_jspecify_annotations">x_jspecify_annotations</a>, <a href="#kt_kotlinc_options-x_jsr_305">x_jsr_305</a>, <a href="#kt_kotlinc_options-x_jvm_default">x_jvm_default</a>,
                   <a href="#kt_kotlinc_options-x_lambdas">x_lambdas</a>, <a href="#kt_kotlinc_options-x_multi_platform">x_multi_platform</a>, <a href="#kt_kotlinc_options-x_no_call_assertions">x_no_call_assertions</a>, <a href="#kt_kotlinc_options-x_no_optimize">x_no_optimize</a>,
                   <a href="#kt_kotlinc_options-x_no_param_assertions">x_no_param_assertions</a>, <a href="#kt_kotlinc_options-x_no_receiver_assertions">x_no_receiver_assertions</a>, <a href="#kt_kotlinc_options-x_no_source_debug_extension">x_no_source_debug_extension</a>,
                   <a href="#kt_kotlinc_options-x_nullability_annotations">x_nullability_annotations</a>, <a href="#kt_kotlinc_options-x_optin">x_optin</a>, <a href="#kt_kotlinc_options-x_render_internal_diagnostic_names">x_render_internal_diagnostic_names</a>,
                   <a href="#kt_kotlinc_options-x_report_all_warnings">x_report_all_warnings</a>, <a href="#kt_kotlinc_options-x_report_perf">x_report_perf</a>, <a href="#kt_kotlinc_options-x_sam_conversions">x_sam_conversions</a>, <a href="#kt_kotlinc_options-x_skip_prerelease_check">x_skip_prerelease_check</a>,
                   <a href="#kt_kotlinc_options-x_suppress_version_warnings">x_suppress_version_warnings</a>, <a href="#kt_kotlinc_options-x_suppress_warning">x_suppress_warning</a>,
                   <a href="#kt_kotlinc_options-x_type_enhancement_improvements_strict_mode">x_type_enhancement_improvements_strict_mode</a>, <a href="#kt_kotlinc_options-x_use_fir_lt">x_use_fir_lt</a>, <a href="#kt_kotlinc_options-x_warning_level">x_warning_level</a>,
                   <a href="#kt_kotlinc_options-x_when_guards">x_when_guards</a>, <a href="#kt_kotlinc_options-x_xlanguage">x_xlanguage</a>)
</pre>

Define kotlin compiler options.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kt_kotlinc_options-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kt_kotlinc_options-api_version"></a>api_version |  Allow using declarations from only the specified version of bundled libraries. Overrides the toolchain's api_version when set.   | String | optional |  `""`  |
| <a id="kt_kotlinc_options-include_stdlibs"></a>include_stdlibs |  Don't automatically include the Kotlin standard libraries into the classpath (stdlib and reflect).   | String | optional |  `"all"`  |
| <a id="kt_kotlinc_options-java_parameters"></a>java_parameters |  Generate metadata for Java 1.8+ reflection on method parameters.   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-jvm_default"></a>jvm_default |  Specifies how to generate JVM default methods for interface declarations with bodies. This is the stable replacement for x_jvm_default (-Xjvm-default). Available from Kotlin 2.2. Options: - 'off': Don't pass the flag (uses compiler default, which is 'enable' in Kotlin 2.2+). - 'enable': Generate default methods and DefaultImpls for compatibility. - 'no-compatibility': Generate default methods without DefaultImpls classes. - 'disable': Do not generate JVM default methods (was the default up to Kotlin 2.1).   | String | optional |  `"off"`  |
| <a id="kt_kotlinc_options-jvm_target"></a>jvm_target |  The target version of the generated JVM bytecode   | String | optional |  `""`  |
| <a id="kt_kotlinc_options-language_version"></a>language_version |  Provide source compatibility with the specified version of Kotlin (2.0 or newer). Overrides the toolchain's language_version when set.   | String | optional |  `""`  |
| <a id="kt_kotlinc_options-progressive"></a>progressive |  Enable progressive compiler mode. In this mode, deprecations and bug fixes for unstable code take effect immediately instead of going through a graceful migration cycle.   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-warn"></a>warn |  Control warning behaviour.   | String | optional |  `"report"`  |
| <a id="kt_kotlinc_options-x_allow_kotlin_package"></a>x_allow_kotlin_package |  Allow compiling code in the 'kotlin' package, and allow not requiring 'kotlin.stdlib' in 'module-info'.   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_allow_unstable_dependencies"></a>x_allow_unstable_dependencies |  Do not report errors on classes in dependencies that were compiled by an unstable version of the Kotlin compiler.   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_annotation_default_target"></a>x_annotation_default_target |  Change the default annotation targets for constructor properties: -Xannotation-default-target=first-only: use the first of the following allowed targets: '@param:', '@property:', '@field:'; -Xannotation-default-target=first-only-warn: same as first-only, and raise warnings when both '@param:' and either '@property:' or '@field:' are allowed; -Xannotation-default-target=param-property: use '@param:' target if applicable, and also use the first of either '@property:' or '@field:'; default: 'first-only-warn' in language version 2.2+, 'first-only' in version 2.1 and before.   | String | optional |  `"off"`  |
| <a id="kt_kotlinc_options-x_assertions"></a>x_assertions |  Configures how assertions are handled. The 'jvm' option enables assertions in JVM code.   | String | optional |  `""`  |
| <a id="kt_kotlinc_options-x_backend_threads"></a>x_backend_threads |  When using the IR backend, run lowerings by file in N parallel threads. 0 means use a thread per processor core. Default value is 1.   | Integer | optional |  `1`  |
| <a id="kt_kotlinc_options-x_compiler_plugin_order"></a>x_compiler_plugin_order |  Execution order constraints for compiler plugins. Each constraint has the form `<pluginId1>><pluginId2>`: the first plugin runs before the second.   | List of strings | optional |  `[]`  |
| <a id="kt_kotlinc_options-x_consistent_data_class_copy_visibility"></a>x_consistent_data_class_copy_visibility |  The effect of this compiler flag is the same as applying @ConsistentCopyVisibility annotation to all data classes in the module. See https://youtrack.jetbrains.com/issue/KT-11914   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_context_parameters"></a>x_context_parameters |  Enable experimental context parameters (Kotlin 2.2+).   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_context_receivers"></a>x_context_receivers |  Enable experimental context receivers.   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_emit_jvm_type_annotations"></a>x_emit_jvm_type_annotations |  Basic support for type annotations in JVM bytecode.   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_enable_incremental_compilation"></a>x_enable_incremental_compilation |  Enable incremental compilation   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_explicit_api_mode"></a>x_explicit_api_mode |  Enable explicit API mode for Kotlin libraries.   | String | optional |  `"off"`  |
| <a id="kt_kotlinc_options-x_inline_classes"></a>x_inline_classes |  Enable experimental inline classes   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_jdk_release"></a>x_jdk_release |  Compile against the specified JDK API version, similarly to javac's '-release'. This requires JDK 9 or newer. The supported versions depend on the JDK used; for JDK 25+, the supported versions are 1.8 and 9-25. This also sets the value of '-jvm-target' to be equal to the selected JDK version.   | String | optional |  `""`  |
| <a id="kt_kotlinc_options-x_jspecify_annotations"></a>x_jspecify_annotations |  Controls how JSpecify annotations are treated. Options are 'default', 'ignore', 'warn', and 'strict'.   | String | optional |  `""`  |
| <a id="kt_kotlinc_options-x_jsr_305"></a>x_jsr_305 |  Specifies how to handle JSR-305 annotations in Kotlin code. Options are 'default', 'ignore', 'warn', and 'strict'.   | String | optional |  `""`  |
| <a id="kt_kotlinc_options-x_jvm_default"></a>x_jvm_default |  DEPRECATED: Use jvm_default instead for Kotlin 2.2+. Specifies that a JVM default method should be generated for non-abstract Kotlin interface member. Migration to jvm_default: - x_jvm_default=all -> jvm_default=no-compatibility - x_jvm_default=all-compatibility -> jvm_default=enable - x_jvm_default=disable -> jvm_default=disable   | String | optional |  `"off"`  |
| <a id="kt_kotlinc_options-x_lambdas"></a>x_lambdas |  Change codegen behavior of lambdas. Defaults to "class" (anonymous inner classes), which differs from Kotlin 2.x/Gradle default of "indy" (invokedynamic). Set to "indy" for Gradle-compatible bytecode.   | String | optional |  `"class"`  |
| <a id="kt_kotlinc_options-x_multi_platform"></a>x_multi_platform |  Enable experimental language support for multi-platform projects   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_no_call_assertions"></a>x_no_call_assertions |  Don't generate not-null assertions for arguments of platform types   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_no_optimize"></a>x_no_optimize |  Disable optimizations   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_no_param_assertions"></a>x_no_param_assertions |  Don't generate not-null assertions on parameters of methods accessible from Java   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_no_receiver_assertions"></a>x_no_receiver_assertions |  Don't generate not-null assertion for extension receiver arguments of platform types   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_no_source_debug_extension"></a>x_no_source_debug_extension |  Do not generate @kotlin.jvm.internal.SourceDebugExtension annotation on a class with the copy of SMAP   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_nullability_annotations"></a>x_nullability_annotations |  Configure how Kotlin treats nullability annotations on Java types, per annotation class. Map the fully-qualified annotation class name (prefixed with '@') to a mode: 'ignore', 'warn', or 'strict'. Ex: {'@jakarta.annotation.Nullable': 'strict', '@jakarta.annotation.Nonnull': 'strict'}. Use x_jsr305 for javax.annotation (JSR-305) and x_jspecify_annotations for org.jspecify.   | <a href="https://bazel.build/rules/lib/core/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="kt_kotlinc_options-x_optin"></a>x_optin |  Define APIs to opt-in to.   | List of strings | optional |  `[]`  |
| <a id="kt_kotlinc_options-x_render_internal_diagnostic_names"></a>x_render_internal_diagnostic_names |  Render the internal names of warnings and errors.   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_report_all_warnings"></a>x_report_all_warnings |  Report all warnings even if errors are found.   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_report_perf"></a>x_report_perf |  Report detailed performance statistics   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_sam_conversions"></a>x_sam_conversions |  Change codegen behavior of SAM/functional interfaces. Defaults to "indy" (invokedynamic via LambdaMetafactory), matching Kotlin compiler's own default since 1.5. Set to "class" for legacy anonymous-class codegen.   | String | optional |  `"indy"`  |
| <a id="kt_kotlinc_options-x_skip_prerelease_check"></a>x_skip_prerelease_check |  Suppress errors thrown when using pre-release classes.   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_suppress_version_warnings"></a>x_suppress_version_warnings |  Suppress warnings about outdated, inconsistent, or experimental language or API versions.   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_suppress_warning"></a>x_suppress_warning |  Suppress specific warnings globally   | List of strings | optional |  `[]`  |
| <a id="kt_kotlinc_options-x_type_enhancement_improvements_strict_mode"></a>x_type_enhancement_improvements_strict_mode |  Enables strict mode for type enhancement improvements, enforcing stricter type checking and enhancements.   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_use_fir_lt"></a>x_use_fir_lt |  Compile using LightTree parser with Front-end IR. Warning: this feature is far from being production-ready   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_warning_level"></a>x_warning_level |  Suppress specific warnings globally. Ex: 'OPTION': '(error\|warning\|disabled)'   | <a href="https://bazel.build/rules/lib/core/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="kt_kotlinc_options-x_when_guards"></a>x_when_guards |  Enable experimental language support for when guards.   | Boolean | optional |  `False`  |
| <a id="kt_kotlinc_options-x_xlanguage"></a>x_xlanguage |  Enable or disable the specified language feature. Not intended for production use; prefer language_version or the dedicated feature flags.   | List of strings | optional |  `[]`  |


<a id="kt_ksp_plugin"></a>

## kt_ksp_plugin

<pre>
load("@rules_kotlin//kotlin:core.bzl", "kt_ksp_plugin")

kt_ksp_plugin(<a href="#kt_ksp_plugin-name">name</a>, <a href="#kt_ksp_plugin-deps">deps</a>, <a href="#kt_ksp_plugin-generates_java">generates_java</a>, <a href="#kt_ksp_plugin-options">options</a>, <a href="#kt_ksp_plugin-processor_class">processor_class</a>, <a href="#kt_ksp_plugin-target_embedded_compiler">target_embedded_compiler</a>)
</pre>

Define a KSP plugin for the Kotlin compiler to run. The plugin can then be referenced in the `plugins` attribute
of the `kt_jvm_*` and `kt_android_*` rules.

An example can be found under `//examples/ksp`:

```bzl
kt_ksp_plugin(
    name = "moshi-kotlin-codegen",
    processor_class = "com.squareup.moshi.kotlin.codegen.ksp.JsonClassSymbolProcessorProvider",
    deps = [
        "@maven//:com_squareup_moshi_moshi",
        "@maven//:com_squareup_moshi_moshi_kotlin",
        "@maven//:com_squareup_moshi_moshi_kotlin_codegen",
    ],
)

kt_jvm_library(
    name = "lib",
    srcs = glob(["*.kt"]),
    plugins = ["//:moshi-kotlin-codegen"],
)
```

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kt_ksp_plugin-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kt_ksp_plugin-deps"></a>deps |  The list of libraries to be added to the compiler's plugin classpath. The plugin classpath is the transitive runtime classpath of these libraries. A neverlink library therefore contributes nothing to it, and neither does a library reachable only through a neverlink library.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_ksp_plugin-generates_java"></a>generates_java |  Runs Java compilation action for plugin generating Java output.   | Boolean | optional |  `False`  |
| <a id="kt_ksp_plugin-options"></a>options |  Processor options passed to the KSP processor via SymbolProcessorEnvironment.options. Each entry is a key-value pair available to the processor at processing time.   | <a href="https://bazel.build/rules/lib/core/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="kt_ksp_plugin-processor_class"></a>processor_class |  The fully qualified class name that the Java compiler uses as an entry point to the annotation processor.   | String | required |  |
| <a id="kt_ksp_plugin-target_embedded_compiler"></a>target_embedded_compiler |  Plugin was compiled against the embeddable kotlin compiler. The rule reshades the plugin classpath into the CLI-distribution dialect, which it assumes runs the plugin. The aspect declares the reshaded copies for the libraries that deps, runtime_deps, exports or associates reach. A jar without a copy stays as it is.   | Boolean | optional |  `False`  |


<a id="kt_plugin_cfg"></a>

## kt_plugin_cfg

<pre>
load("@rules_kotlin//kotlin:core.bzl", "kt_plugin_cfg")

kt_plugin_cfg(<a href="#kt_plugin_cfg-name">name</a>, <a href="#kt_plugin_cfg-deps">deps</a>, <a href="#kt_plugin_cfg-data">data</a>, <a href="#kt_plugin_cfg-options">options</a>, <a href="#kt_plugin_cfg-plugin">plugin</a>)
</pre>

Configurations for kt_compiler_plugin, ksp_plugin, and java_plugin.

This allows setting options and dependencies independently from the initial plugin definition.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kt_plugin_cfg-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kt_plugin_cfg-deps"></a>deps |  Dependencies for this configuration.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_plugin_cfg-data"></a>data |  The files the plugin reads at compile time. An option value names one of them as `$(location <file>)`. The files and the runfiles of each listed target are inputs of the compilation.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_plugin_cfg-options"></a>options |  A dictionary of flag to values to be used as plugin configuration options.   | <a href="https://bazel.build/rules/lib/core/dict">Dictionary: String -> List of strings</a> | optional |  `{}`  |
| <a id="kt_plugin_cfg-plugin"></a>plugin |  The plugin to associate with this configuration   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |


<a id="BtapiRuntimeInfo"></a>

## BtapiRuntimeInfo

<pre>
load("@rules_kotlin//kotlin:core.bzl", "BtapiRuntimeInfo")

BtapiRuntimeInfo(<a href="#BtapiRuntimeInfo-build_tools_impl">build_tools_impl</a>, <a href="#BtapiRuntimeInfo-compiler">compiler</a>, <a href="#BtapiRuntimeInfo-jdeps_gen">jdeps_gen</a>, <a href="#BtapiRuntimeInfo-jvm_abi_gen">jvm_abi_gen</a>, <a href="#BtapiRuntimeInfo-kapt">kapt</a>, <a href="#BtapiRuntimeInfo-libraries">libraries</a>)
</pre>

The complete Build Tools API compilation runtime: the classloader group and the internal
compiler plugins. Every jar is the embeddable compiler dialect.

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="BtapiRuntimeInfo-build_tools_impl"></a>build_tools_impl |  list of File: the Build Tools implementation.    |
| <a id="BtapiRuntimeInfo-compiler"></a>compiler |  list of File: the compiler, embeddable dialect.    |
| <a id="BtapiRuntimeInfo-jdeps_gen"></a>jdeps_gen |  list of File: the jdeps-gen compiler plugin, embeddable dialect.    |
| <a id="BtapiRuntimeInfo-jvm_abi_gen"></a>jvm_abi_gen |  list of File: the jvm-abi-gen compiler plugin, embeddable dialect.    |
| <a id="BtapiRuntimeInfo-kapt"></a>kapt |  list of File: the kapt compiler plugin, embeddable dialect.    |
| <a id="BtapiRuntimeInfo-libraries"></a>libraries |  list of File: the libraries the implementation and the compiler need.    |


<a id="define_kt_toolchain"></a>

## define_kt_toolchain

<pre>
load("@rules_kotlin//kotlin:core.bzl", "define_kt_toolchain")

define_kt_toolchain(<a href="#define_kt_toolchain-name">name</a>, <a href="#define_kt_toolchain-language_version">language_version</a>, <a href="#define_kt_toolchain-api_version">api_version</a>, <a href="#define_kt_toolchain-jvm_target">jvm_target</a>, <a href="#define_kt_toolchain-experimental_use_abi_jars">experimental_use_abi_jars</a>,
                    <a href="#define_kt_toolchain-experimental_treat_internal_as_private_in_abi_jars">experimental_treat_internal_as_private_in_abi_jars</a>,
                    <a href="#define_kt_toolchain-experimental_remove_private_classes_in_abi_jars">experimental_remove_private_classes_in_abi_jars</a>,
                    <a href="#define_kt_toolchain-experimental_remove_debug_info_in_abi_jars">experimental_remove_debug_info_in_abi_jars</a>,
                    <a href="#define_kt_toolchain-experimental_preserve_declaration_order">experimental_preserve_declaration_order</a>,
                    <a href="#define_kt_toolchain-experimental_remove_data_class_copy_if_constructor_is_private">experimental_remove_data_class_copy_if_constructor_is_private</a>,
                    <a href="#define_kt_toolchain-experimental_strict_kotlin_deps">experimental_strict_kotlin_deps</a>, <a href="#define_kt_toolchain-experimental_report_unused_deps">experimental_report_unused_deps</a>,
                    <a href="#define_kt_toolchain-experimental_reduce_classpath_mode">experimental_reduce_classpath_mode</a>, <a href="#define_kt_toolchain-experimental_multiplex_workers">experimental_multiplex_workers</a>,
                    <a href="#define_kt_toolchain-experimental_multiplex_sandboxing">experimental_multiplex_sandboxing</a>, <a href="#define_kt_toolchain-supports_path_mapping">supports_path_mapping</a>,
                    <a href="#define_kt_toolchain-experimental_build_tools_api">experimental_build_tools_api</a>, <a href="#define_kt_toolchain-btapi_runtime">btapi_runtime</a>, <a href="#define_kt_toolchain-experimental_kover_enabled">experimental_kover_enabled</a>,
                    <a href="#define_kt_toolchain-experimental_kover_agent">experimental_kover_agent</a>, <a href="#define_kt_toolchain-experimental_kover_exclude">experimental_kover_exclude</a>,
                    <a href="#define_kt_toolchain-experimental_kover_exclude_annotation">experimental_kover_exclude_annotation</a>, <a href="#define_kt_toolchain-experimental_kover_exclude_inherited_from">experimental_kover_exclude_inherited_from</a>,
                    <a href="#define_kt_toolchain-javac_options">javac_options</a>, <a href="#define_kt_toolchain-kotlinc_options">kotlinc_options</a>, <a href="#define_kt_toolchain-jvm_stdlibs">jvm_stdlibs</a>, <a href="#define_kt_toolchain-jvm_runtime">jvm_runtime</a>, <a href="#define_kt_toolchain-jacocorunner">jacocorunner</a>,
                    <a href="#define_kt_toolchain-exec_compatible_with">exec_compatible_with</a>, <a href="#define_kt_toolchain-target_compatible_with">target_compatible_with</a>, <a href="#define_kt_toolchain-target_settings">target_settings</a>)
</pre>

Define the Kotlin toolchain.

The legacy invocation runs the compiler of the bundled CLI distribution. When the Build Tools
API compilation is enabled, through `experimental_build_tools_api`, through `btapi_runtime`,
or through the build setting `//kotlin/settings:experimental_build_tools_api`, the toolchain
runs a Build Tools API runtime: the Build Tools implementation, the embeddable compiler, the
libraries they need, and the internal compiler plugins in the embeddable dialect.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="define_kt_toolchain-name"></a>name |  the toolchain name.   |  none |
| <a id="define_kt_toolchain-language_version"></a>language_version |  <p align="center"> - </p>   |  `None` |
| <a id="define_kt_toolchain-api_version"></a>api_version |  <p align="center"> - </p>   |  `None` |
| <a id="define_kt_toolchain-jvm_target"></a>jvm_target |  <p align="center"> - </p>   |  `None` |
| <a id="define_kt_toolchain-experimental_use_abi_jars"></a>experimental_use_abi_jars |  <p align="center"> - </p>   |  `False` |
| <a id="define_kt_toolchain-experimental_treat_internal_as_private_in_abi_jars"></a>experimental_treat_internal_as_private_in_abi_jars |  <p align="center"> - </p>   |  `False` |
| <a id="define_kt_toolchain-experimental_remove_private_classes_in_abi_jars"></a>experimental_remove_private_classes_in_abi_jars |  <p align="center"> - </p>   |  `False` |
| <a id="define_kt_toolchain-experimental_remove_debug_info_in_abi_jars"></a>experimental_remove_debug_info_in_abi_jars |  <p align="center"> - </p>   |  `False` |
| <a id="define_kt_toolchain-experimental_preserve_declaration_order"></a>experimental_preserve_declaration_order |  <p align="center"> - </p>   |  `False` |
| <a id="define_kt_toolchain-experimental_remove_data_class_copy_if_constructor_is_private"></a>experimental_remove_data_class_copy_if_constructor_is_private |  <p align="center"> - </p>   |  `False` |
| <a id="define_kt_toolchain-experimental_strict_kotlin_deps"></a>experimental_strict_kotlin_deps |  <p align="center"> - </p>   |  `None` |
| <a id="define_kt_toolchain-experimental_report_unused_deps"></a>experimental_report_unused_deps |  <p align="center"> - </p>   |  `None` |
| <a id="define_kt_toolchain-experimental_reduce_classpath_mode"></a>experimental_reduce_classpath_mode |  <p align="center"> - </p>   |  `None` |
| <a id="define_kt_toolchain-experimental_multiplex_workers"></a>experimental_multiplex_workers |  <p align="center"> - </p>   |  `None` |
| <a id="define_kt_toolchain-experimental_multiplex_sandboxing"></a>experimental_multiplex_sandboxing |  <p align="center"> - </p>   |  `None` |
| <a id="define_kt_toolchain-supports_path_mapping"></a>supports_path_mapping |  <p align="center"> - </p>   |  `None` |
| <a id="define_kt_toolchain-experimental_build_tools_api"></a>experimental_build_tools_api |  `True` enables the Build Tools API compilation for the toolchain. Unset, it is `True` when `btapi_runtime` is set and `False` otherwise. `False` keeps the legacy invocation until the build setting turns the Build Tools API on; a `btapi_runtime` then applies to that build only.   |  `None` |
| <a id="define_kt_toolchain-btapi_runtime"></a>btapi_runtime |  a `kt_btapi_runtime` that replaces the default Build Tools API runtime, `//kotlin/compiler:btapi_runtime`, the runtime of the current Kotlin release. The runtime of another release is `@<name>//:runtime` of a repository the module extension tag `btapi_impl_version` declares. A runtime built on either with `base` replaces single artifacts. A runtime is an explicit choice of the Build Tools API compilation, see `experimental_build_tools_api`.   |  `None` |
| <a id="define_kt_toolchain-experimental_kover_enabled"></a>experimental_kover_enabled |  <p align="center"> - </p>   |  `False` |
| <a id="define_kt_toolchain-experimental_kover_agent"></a>experimental_kover_agent |  <p align="center"> - </p>   |  `None` |
| <a id="define_kt_toolchain-experimental_kover_exclude"></a>experimental_kover_exclude |  <p align="center"> - </p>   |  `None` |
| <a id="define_kt_toolchain-experimental_kover_exclude_annotation"></a>experimental_kover_exclude_annotation |  <p align="center"> - </p>   |  `None` |
| <a id="define_kt_toolchain-experimental_kover_exclude_inherited_from"></a>experimental_kover_exclude_inherited_from |  <p align="center"> - </p>   |  `None` |
| <a id="define_kt_toolchain-javac_options"></a>javac_options |  <p align="center"> - </p>   |  `Label("@rules_kotlin//kotlin/internal:default_javac_options")` |
| <a id="define_kt_toolchain-kotlinc_options"></a>kotlinc_options |  <p align="center"> - </p>   |  `Label("@rules_kotlin//kotlin/internal:default_kotlinc_options")` |
| <a id="define_kt_toolchain-jvm_stdlibs"></a>jvm_stdlibs |  <p align="center"> - </p>   |  `None` |
| <a id="define_kt_toolchain-jvm_runtime"></a>jvm_runtime |  <p align="center"> - </p>   |  `None` |
| <a id="define_kt_toolchain-jacocorunner"></a>jacocorunner |  <p align="center"> - </p>   |  `None` |
| <a id="define_kt_toolchain-exec_compatible_with"></a>exec_compatible_with |  <p align="center"> - </p>   |  `None` |
| <a id="define_kt_toolchain-target_compatible_with"></a>target_compatible_with |  <p align="center"> - </p>   |  `None` |
| <a id="define_kt_toolchain-target_settings"></a>target_settings |  <p align="center"> - </p>   |  `None` |


<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Public API for Kotlin/Native rules.

Experimental:
- kt_native_library: compile .kt -> .klib for the resolved konan target.
- kt_native_binary: link .kt sources + klib deps into a native executable (`bazel run`).
- kt_native_test: link .kt tests + klib deps into a test runner (`bazel test`) for the exec host.
- kt_native_framework: link .kt sources + klib deps into a static Apple framework. Its output
  group `framework_files` holds the files of the framework, which rules_apple's
  apple_static_framework_import imports.
- kt_klib_import: a prebuilt .klib of a konan target (e.g. from Maven) as a klib dep.
- KtKlibInfo: the provider of a klib.

The konan target is selected by Bazel toolchain resolution (the build's --platforms),
not a rule attribute; a kt_klib_import names the one of its klib. The rules build with
the Kotlin platform type native (//kotlin/settings:kotlin_platform_type), so a dep that
selects on @rules_kotlin//kotlin/native/platforms:native_<konan target> is their klib.
See examples/native and examples/kmp_app for usage, and docs/kmp.md for the guide.

<a id="kt_klib_import"></a>

## kt_klib_import

<pre>
load("@rules_kotlin//kotlin:native.bzl", "kt_klib_import")

kt_klib_import(<a href="#kt_klib_import-name">name</a>, <a href="#kt_klib_import-deps">deps</a>, <a href="#kt_klib_import-exports">exports</a>, <a href="#kt_klib_import-klib">klib</a>, <a href="#kt_klib_import-konan_target">konan_target</a>, <a href="#kt_klib_import-module_name">module_name</a>)
</pre>

Imports a prebuilt klib of a konan target, which the Kotlin/Native rules compile against and link like the klib of a kt_native_library.

Experimental. The klib is for one konan target, e.g. the klib of the `linuxx64` variant of a Kotlin
Multiplatform library on Maven for `linux_x64`; its deps and exports are klibs of the same target.
A consumer of another konan target fails. The cinterop klibs of a library are imports of their own,
deps of the import of its main klib, so they follow it wherever it is compiled against or linked.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kt_klib_import-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kt_klib_import-deps"></a>deps |  The klibs the klib depends on, e.g. its cinterop klibs: its consumers compile against them and link them with it. They are for the same konan target.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_klib_import-exports"></a>exports |  Klibs the klib depends on and re-exports: its consumers compile against them as if they listed them in their own deps. They are for the same konan target.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_klib_import-klib"></a>klib |  The .klib file.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="kt_klib_import-konan_target"></a>konan_target |  The konan target of the klib, e.g. `linux_x64`.   | String | required |  |
| <a id="kt_klib_import-module_name"></a>module_name |  The module name of the klib, for information: konanc reads the unique_name of a klib from its manifest. By default it is derived from the label, as for the other rules.   | String | optional |  `""`  |


<a id="kt_native_binary"></a>

## kt_native_binary

<pre>
load("@rules_kotlin//kotlin:native.bzl", "kt_native_binary")

kt_native_binary(<a href="#kt_native_binary-name">name</a>, <a href="#kt_native_binary-deps">deps</a>, <a href="#kt_native_binary-srcs">srcs</a>, <a href="#kt_native_binary-link_opts">link_opts</a>, <a href="#kt_native_binary-module_name">module_name</a>, <a href="#kt_native_binary-opts">opts</a>, <a href="#kt_native_binary-plugins">plugins</a>)
</pre>

Links a Kotlin/Native executable, `<name>.kexe`, for the konan target of the build's platform.

Experimental. The entry point, `main`, is in the srcs or in a dep. The link dependencies of the target
must be staged: see kotlin_native.targets(...).

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kt_native_binary-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kt_native_binary-deps"></a>deps |  The klibs to link, e.g. kt_native_library targets, which the srcs compile against. They are for the same konan target.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_native_binary-srcs"></a>srcs |  Kotlin sources.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_native_binary-link_opts"></a>link_opts |  More konanc options of the link, e.g. `-opt`. They follow the options of the rule.   | List of strings | optional |  `[]`  |
| <a id="kt_native_binary-module_name"></a>module_name |  The Kotlin module name of the srcs, the unique_name of the klib they compile into. By default it is derived from the label, as for the JVM rules.   | String | optional |  `""`  |
| <a id="kt_native_binary-opts"></a>opts |  More konanc options of the compilation of the srcs, e.g. `-opt-in=kotlin.ExperimentalStdlibApi`.   | List of strings | optional |  `[]`  |
| <a id="kt_native_binary-plugins"></a>plugins |  Kotlin compiler plugins (kt_compiler_plugin) to run during the compilation of the srcs. The Kotlin/Native compiler loads them in the embeddable compiler dialect.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="kt_native_framework"></a>

## kt_native_framework

<pre>
load("@rules_kotlin//kotlin:native.bzl", "kt_native_framework")

kt_native_framework(<a href="#kt_native_framework-name">name</a>, <a href="#kt_native_framework-deps">deps</a>, <a href="#kt_native_framework-srcs">srcs</a>, <a href="#kt_native_framework-bundle_id">bundle_id</a>, <a href="#kt_native_framework-exports">exports</a>, <a href="#kt_native_framework-link_opts">link_opts</a>, <a href="#kt_native_framework-module_name">module_name</a>, <a href="#kt_native_framework-opts">opts</a>, <a href="#kt_native_framework-plugins">plugins</a>,
                    <a href="#kt_native_framework-transitive_exports">transitive_exports</a>)
</pre>

Links a static framework, `<name>.framework`, for the Apple konan target of the build's platform.

Experimental. The framework is a directory, named after the target like the prefix of its Objective-C names.
The link dependencies of the target must be staged: see kotlin_native.targets(...).

The output group `framework_files` holds the files of the framework, copied out of the directory into
`_kt_native/<name>.framework/` when a build requests them: the static library `<name>`, the umbrella header
`Headers/<name>.h`, the module map `Modules/module.modulemap` and `Info.plist`. rules_apple imports a framework
from its files, so an iOS app links the framework through a filegroup of the group, and the framework follows the
platform of the app (`--ios_multi_cpus`):

```bzl
kt_native_framework(
    name = "Shared",
    bundle_id = "org.example.Shared",
    exports = ["//shared"],
)

filegroup(
    name = "Shared_files",
    srcs = [":Shared"],
    output_group = "framework_files",
)

apple_static_framework_import(
    name = "Shared_import",
    framework_imports = [":Shared_files"],
    # What the Kotlin/Native runtime links with.
    sdk_dylibs = ["c++", "objc"],
    sdk_frameworks = ["Foundation", "UIKit"],
)
```

A swift_library then depends on `:Shared_import` and imports the module `Shared`. See examples/kmp_app.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kt_native_framework-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kt_native_framework-deps"></a>deps |  The klibs to link, e.g. kt_native_library targets, which the srcs compile against. They are for the same konan target.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_native_framework-srcs"></a>srcs |  Kotlin sources.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_native_framework-bundle_id"></a>bundle_id |  The CFBundleIdentifier of the framework; by default the compiler derives one from the sources.   | String | optional |  `""`  |
| <a id="kt_native_framework-exports"></a>exports |  Klibs whose API the framework exports in its header, with their own exports (see transitive_exports). They are deps of the framework too.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_native_framework-link_opts"></a>link_opts |  More konanc options of the link, e.g. `-opt`. They follow the options of the rule.   | List of strings | optional |  `[]`  |
| <a id="kt_native_framework-module_name"></a>module_name |  The Kotlin module name of the srcs, the unique_name of the klib they compile into. By default it is derived from the label, as for the JVM rules.   | String | optional |  `""`  |
| <a id="kt_native_framework-opts"></a>opts |  More konanc options of the compilation of the srcs, e.g. `-opt-in=kotlin.ExperimentalStdlibApi`.   | List of strings | optional |  `[]`  |
| <a id="kt_native_framework-plugins"></a>plugins |  Kotlin compiler plugins (kt_compiler_plugin) to run during the compilation of the srcs. The Kotlin/Native compiler loads them in the embeddable compiler dialect.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_native_framework-transitive_exports"></a>transitive_exports |  Whether the header also declares the API of the exports of the `exports`, transitively (the default), or of the listed klibs alone, as a framework of the Kotlin Gradle plugin exports only the libraries its `export()` names (its `transitiveExport` is off by default): a module whose `api` dependencies are large libraries, like Compose, keeps them out of its Objective-C header this way. Either way the link gets the whole closure.   | Boolean | optional |  `True`  |


<a id="kt_native_library"></a>

## kt_native_library

<pre>
load("@rules_kotlin//kotlin:native.bzl", "kt_native_library")

kt_native_library(<a href="#kt_native_library-name">name</a>, <a href="#kt_native_library-deps">deps</a>, <a href="#kt_native_library-srcs">srcs</a>, <a href="#kt_native_library-exports">exports</a>, <a href="#kt_native_library-kmp_fragments">kmp_fragments</a>, <a href="#kt_native_library-module_name">module_name</a>, <a href="#kt_native_library-opts">opts</a>, <a href="#kt_native_library-plugins">plugins</a>)
</pre>

Compiles Kotlin sources into a Kotlin/Native klib, for the konan target of the build's platform.

Experimental. Build for a konan target with `--platforms`, e.g.
`--platforms=@rules_kotlin//kotlin/native/platforms:linux_x64`; the host platform builds for the
host's target.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kt_native_library-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kt_native_library-deps"></a>deps |  The klibs the sources compile against, e.g. kt_native_library targets. They are for the same konan target.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_native_library-srcs"></a>srcs |  Kotlin sources.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_native_library-exports"></a>exports |  Klibs the sources compile against that the library also re-exports: its dependents compile against them as if they listed them in their own deps.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_native_library-kmp_fragments"></a>kmp_fragments |  The K2 fragments of a `kt_multiplatform_library` that the srcs refine: the sources the library shares with other platforms. `kt_multiplatform_library` sets it from the sources each platform lists; it is not set by hand. The Kotlin sources of the fragments, and of the fragments they refine, compile with the srcs in one compilation (`-Xmulti-platform`), against the deps, so the `actual` declarations of the srcs implement the `expect` ones of the fragments; the srcs are the leaf fragment, named after the konan target. Expect/actual classes are Beta in Kotlin: the rule passes `-Xexpect-actual-classes`, which acknowledges it.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_native_library-module_name"></a>module_name |  The Kotlin module name, which is the unique_name of the klib. By default it is derived from the label, as for the JVM rules.   | String | optional |  `""`  |
| <a id="kt_native_library-opts"></a>opts |  More konanc options, e.g. `-opt-in=kotlin.ExperimentalStdlibApi`. They follow the options of the rule.   | List of strings | optional |  `[]`  |
| <a id="kt_native_library-plugins"></a>plugins |  Kotlin compiler plugins (kt_compiler_plugin) to run during the compilation. The Kotlin/Native compiler loads them in the embeddable compiler dialect.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="kt_native_test"></a>

## kt_native_test

<pre>
load("@rules_kotlin//kotlin:native.bzl", "kt_native_test")

kt_native_test(<a href="#kt_native_test-name">name</a>, <a href="#kt_native_test-deps">deps</a>, <a href="#kt_native_test-srcs">srcs</a>, <a href="#kt_native_test-associates">associates</a>, <a href="#kt_native_test-link_opts">link_opts</a>, <a href="#kt_native_test-module_name">module_name</a>, <a href="#kt_native_test-opts">opts</a>, <a href="#kt_native_test-plugins">plugins</a>)
</pre>

Links the tests of the srcs into a Kotlin/Native test runner, `<name>.kexe`, which `bazel test` runs.

Experimental. The tests use kotlin.test, e.g. `@kotlin.test.Test`. The test is for the konan target of the
exec host, whose link dependencies must be staged: see kotlin_native.targets(...).

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kt_native_test-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kt_native_test-deps"></a>deps |  The klibs to link, e.g. kt_native_library targets, which the srcs compile against. They are for the same konan target.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_native_test-srcs"></a>srcs |  Kotlin sources with the tests.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_native_test-associates"></a>associates |  kt_native_library targets whose internal declarations the srcs see. They are deps of the test too.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_native_test-link_opts"></a>link_opts |  More konanc options of the link, e.g. `-opt`. They follow the options of the rule.   | List of strings | optional |  `[]`  |
| <a id="kt_native_test-module_name"></a>module_name |  The Kotlin module name of the srcs, the unique_name of the klib they compile into. By default it is derived from the label, as for the JVM rules.   | String | optional |  `""`  |
| <a id="kt_native_test-opts"></a>opts |  More konanc options of the compilation of the srcs, e.g. `-opt-in=kotlin.ExperimentalStdlibApi`.   | List of strings | optional |  `[]`  |
| <a id="kt_native_test-plugins"></a>plugins |  Kotlin compiler plugins (kt_compiler_plugin) to run during the compilation of the srcs. The Kotlin/Native compiler loads them in the embeddable compiler dialect.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="KtKlibInfo"></a>

## KtKlibInfo

<pre>
load("@rules_kotlin//kotlin:native.bzl", "KtKlibInfo")

KtKlibInfo(<a href="#KtKlibInfo-cc_info">cc_info</a>, <a href="#KtKlibInfo-exported_klibs">exported_klibs</a>, <a href="#KtKlibInfo-klib">klib</a>, <a href="#KtKlibInfo-konan_target">konan_target</a>, <a href="#KtKlibInfo-module_name">module_name</a>, <a href="#KtKlibInfo-platform">platform</a>, <a href="#KtKlibInfo-transitive_klibs">transitive_klibs</a>)
</pre>

A Kotlin library compiled to a .klib.

The Kotlin/Native rules produce and consume klibs for a konan target. `platform` leaves room for
the klibs of other Kotlin platforms (JS, Wasm), which share the format.

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="KtKlibInfo-cc_info"></a>cc_info |  (CcInfo or None) The C libraries the klib binds, which a binary linking it needs; None until cinterop is supported.    |
| <a id="KtKlibInfo-exported_klibs"></a>exported_klibs |  (depset[File]) The klibs this target re-exports to its dependents: its exports and theirs.    |
| <a id="KtKlibInfo-klib"></a>klib |  (File) The .klib this target produces.    |
| <a id="KtKlibInfo-konan_target"></a>konan_target |  (str or None) The konan target the klib is compiled for, e.g. linux_x64; None for a klib of another platform.    |
| <a id="KtKlibInfo-module_name"></a>module_name |  (str) The module name, the unique_name of the klib manifest.    |
| <a id="KtKlibInfo-platform"></a>platform |  (str) The Kotlin platform of the klib: 'native' (later also 'js', 'wasm_js' or 'wasm_wasi').    |
| <a id="KtKlibInfo-transitive_klibs"></a>transitive_klibs |  (depset[File]) The klib and every klib compiling against it needs: its deps and exports, transitively.    |


<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Public API for Kotlin Multiplatform.

Experimental:
- kt_multiplatform_library: a multiplatform library whose platforms each list every source they
  compile: a library per platform, compiling the sources it shares with other platforms as K2
  fragments, so `expect` declarations and their `actual` ones are in one module, and an alias
  selecting the library of its consumer: the native one for a Kotlin/Native rule
  (`@rules_kotlin//kotlin/native/platforms:native_<konan target>`), the Android one for an Android
  platform and the JVM one otherwise.
- kt_jvm_ksp_sources, kt_native_ksp_sources: KSP2 over the sources of a platform, as a separate
  action whose generated Kotlin files the library of the platform compiles.

kt_multiplatform_library declares a kt_android_library when it has an `android` platform, so this
file loads the Android rules. See examples/kmp and examples/kmp_app for usage, and docs/kmp.md
for the guide.

<a id="kt_jvm_ksp_sources"></a>

## kt_jvm_ksp_sources

<pre>
load("@rules_kotlin//kotlin:kmp.bzl", "kt_jvm_ksp_sources")

kt_jvm_ksp_sources(<a href="#kt_jvm_ksp_sources-name">name</a>, <a href="#kt_jvm_ksp_sources-deps">deps</a>, <a href="#kt_jvm_ksp_sources-srcs">srcs</a>, <a href="#kt_jvm_ksp_sources-android">android</a>, <a href="#kt_jvm_ksp_sources-api_version">api_version</a>, <a href="#kt_jvm_ksp_sources-common_srcs">common_srcs</a>, <a href="#kt_jvm_ksp_sources-generated">generated</a>, <a href="#kt_jvm_ksp_sources-jvm_target">jvm_target</a>,
                   <a href="#kt_jvm_ksp_sources-language_version">language_version</a>, <a href="#kt_jvm_ksp_sources-module_name">module_name</a>, <a href="#kt_jvm_ksp_sources-processor_options">processor_options</a>, <a href="#kt_jvm_ksp_sources-processors">processors</a>)
</pre>

Runs KSP2 (`KSPJvmMain`) over the sources of a JVM or Android platform and declares the Kotlin files it generates.

Experimental. See the documentation of kotlin/internal/kmp/ksp.bzl. Compiling the generated files: list the
target in the `srcs` of the `jvm` or `android` platform of the kt_multiplatform_library, and of no other
platform, so they are the leaf fragment of that platform.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kt_jvm_ksp_sources-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kt_jvm_ksp_sources-deps"></a>deps |  The libraries of the platform the sources compile against, e.g. the JVM variant of the KMP libraries: their compile jars are the libraries of KSP.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_ksp_sources-srcs"></a>srcs |  The Kotlin sources KSP processes: every source the platform compiles, those it shares and its own.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | required |  |
| <a id="kt_jvm_ksp_sources-android"></a>android |  Whether the sources use the Android APIs: the Android SDK jar is a library of KSP (needs the Android SDK toolchain of rules_android).   | Boolean | optional |  `False`  |
| <a id="kt_jvm_ksp_sources-api_version"></a>api_version |  The `-api-version` of KSP; by default the one of the Kotlin toolchain.   | String | optional |  `""`  |
| <a id="kt_jvm_ksp_sources-common_srcs"></a>common_srcs |  The Kotlin sources the platform shares with other platforms, a subset of `srcs`. KSP processes them after the sources of the platform alone, as the KSP Gradle plugin orders the source sets of a platform compilation: a type with an `expect` declaration in the common sources and an `actual` one in the platform sources resolves to the actual, with its constructors and members, as it does in the compilation of the platform.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_jvm_ksp_sources-generated"></a>generated |  The Kotlin files the processors generate, relative to the output root of KSP: the directory of the package and the file name, e.g. `com/example/InjectAppComponent.kt`. The files are outputs of the target, under a directory of its name, to list in the `srcs` of the platform library. The action fails on a file the processors write that is not listed, and on one listed that they do not write.   | List of strings | required |  |
| <a id="kt_jvm_ksp_sources-jvm_target"></a>jvm_target |  The `-jvm-target` of KSP; by default the one of the Kotlin toolchain.   | String | optional |  `""`  |
| <a id="kt_jvm_ksp_sources-language_version"></a>language_version |  The `-language-version` of KSP; by default the one of the Kotlin toolchain.   | String | optional |  `""`  |
| <a id="kt_jvm_ksp_sources-module_name"></a>module_name |  The module name KSP is given; by default the name of the target.   | String | optional |  `""`  |
| <a id="kt_jvm_ksp_sources-processor_options"></a>processor_options |  More KSP options, as `ksp.arg` of Gradle, on top of those of the `processors`.   | <a href="https://bazel.build/rules/lib/core/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="kt_jvm_ksp_sources-processors"></a>processors |  The KSP processors, as kt_ksp_plugin targets: their runtime classpath is the one KSP loads them from, and their options are passed on.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="kt_native_ksp_sources"></a>

## kt_native_ksp_sources

<pre>
load("@rules_kotlin//kotlin:kmp.bzl", "kt_native_ksp_sources")

kt_native_ksp_sources(<a href="#kt_native_ksp_sources-name">name</a>, <a href="#kt_native_ksp_sources-deps">deps</a>, <a href="#kt_native_ksp_sources-srcs">srcs</a>, <a href="#kt_native_ksp_sources-api_version">api_version</a>, <a href="#kt_native_ksp_sources-common_srcs">common_srcs</a>, <a href="#kt_native_ksp_sources-generated">generated</a>, <a href="#kt_native_ksp_sources-language_version">language_version</a>,
                      <a href="#kt_native_ksp_sources-module_name">module_name</a>, <a href="#kt_native_ksp_sources-processor_options">processor_options</a>, <a href="#kt_native_ksp_sources-processors">processors</a>)
</pre>

Runs KSP2 (`KSPNativeMain`) over the sources of a konan target and declares the Kotlin files it generates.

Experimental. See the documentation of kotlin/internal/kmp/ksp.bzl. The target is for the konan target of the
build's platform, like kt_native_library: its `deps` are klibs of that target, which KSP resolves symbols
against, with the standard library and platform libraries of the distribution. List it in the `srcs` of the
kt_native_library of the platform (or of a group of a kt_multiplatform_library).

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="kt_native_ksp_sources-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="kt_native_ksp_sources-deps"></a>deps |  The klibs of the konan target the sources compile against: their transitive klibs are the libraries of KSP.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_native_ksp_sources-srcs"></a>srcs |  The Kotlin sources KSP processes: every source the platform compiles, those it shares and its own.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | required |  |
| <a id="kt_native_ksp_sources-api_version"></a>api_version |  The `-api-version` of KSP; by default the one of the Kotlin toolchain.   | String | optional |  `""`  |
| <a id="kt_native_ksp_sources-common_srcs"></a>common_srcs |  The Kotlin sources the platform shares with other platforms, a subset of `srcs`. KSP processes them after the sources of the platform alone, as the KSP Gradle plugin orders the source sets of a platform compilation: a type with an `expect` declaration in the common sources and an `actual` one in the platform sources resolves to the actual, with its constructors and members, as it does in the compilation of the platform.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |
| <a id="kt_native_ksp_sources-generated"></a>generated |  The Kotlin files the processors generate, relative to the output root of KSP: the directory of the package and the file name, e.g. `com/example/InjectAppComponent.kt`. The files are outputs of the target, under a directory of its name, to list in the `srcs` of the platform library. The action fails on a file the processors write that is not listed, and on one listed that they do not write.   | List of strings | required |  |
| <a id="kt_native_ksp_sources-language_version"></a>language_version |  The `-language-version` of KSP; by default the one of the Kotlin toolchain.   | String | optional |  `""`  |
| <a id="kt_native_ksp_sources-module_name"></a>module_name |  The module name KSP is given; by default the name of the target.   | String | optional |  `""`  |
| <a id="kt_native_ksp_sources-processor_options"></a>processor_options |  More KSP options, as `ksp.arg` of Gradle, on top of those of the `processors`.   | <a href="https://bazel.build/rules/lib/core/dict">Dictionary: String -> String</a> | optional |  `{}`  |
| <a id="kt_native_ksp_sources-processors"></a>processors |  The KSP processors, as kt_ksp_plugin targets: their runtime classpath is the one KSP loads them from, and their options are passed on.   | <a href="https://bazel.build/concepts/labels">List of labels</a> | optional |  `[]`  |


<a id="kt_multiplatform_library"></a>

## kt_multiplatform_library

<pre>
load("@rules_kotlin//kotlin:kmp.bzl", "kt_multiplatform_library")

kt_multiplatform_library(<a href="#kt_multiplatform_library-name">name</a>, <a href="#kt_multiplatform_library-jvm">jvm</a>, <a href="#kt_multiplatform_library-android">android</a>, <a href="#kt_multiplatform_library-native">native</a>, <a href="#kt_multiplatform_library-visibility">visibility</a>, <a href="#kt_multiplatform_library-tags">tags</a>, <a href="#kt_multiplatform_library-testonly">testonly</a>, <a href="#kt_multiplatform_library-kwargs">**kwargs</a>)
</pre>

Declares a Kotlin Multiplatform library: a library per platform, the fragments they share and an alias.

Experimental. Each platform lists every source it compiles. The sources that exactly the same
platforms list are a K2 fragment of the compilations of those platforms, named after them, and
the sources of a single platform are its leaf fragment, so the `expect` declarations of shared
sources and the `actual` ones of a platform are in one module (see derive.bzl). A fragment has
no deps: each platform compiles it against its own deps. Sources are shared by label: a platform
lists a label once, and a file must be listed by the same label everywhere.


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="kt_multiplatform_library-name"></a>name |  the name of the alias, and the prefix of the names of the other targets.   |  none |
| <a id="kt_multiplatform_library-jvm"></a>jvm |  the attributes of the kt_jvm_library `<name>_jvm`, e.g. `dict(srcs = COMMON + JVM, deps = [...])`, or None for no JVM library. Its `srcs`, a list of labels, are every source the JVM compiles.   |  `None` |
| <a id="kt_multiplatform_library-android"></a>android |  the attributes of the kt_android_library `<name>_android`, e.g. `srcs`, `deps` and `manifest`, or None for no Android library. Its `srcs`, a list of labels, are every source Android compiles.   |  `None` |
| <a id="kt_multiplatform_library-native"></a>native |  the groups of konan targets, `{"<group>": dict(srcs = [...], deps = [...], targets = [...])}`. A group stands for each of its targets: its `srcs`, a list of labels, are every source they compile, and its other attributes, e.g. `deps` and `opts`, are attributes of `<name>_native` for them.   |  `{}` |
| <a id="kt_multiplatform_library-visibility"></a>visibility |  the visibility of the targets; the fragments are private.   |  `None` |
| <a id="kt_multiplatform_library-tags"></a>tags |  the tags of the targets.   |  `[]` |
| <a id="kt_multiplatform_library-testonly"></a>testonly |  whether the targets are testonly.   |  `False` |
| <a id="kt_multiplatform_library-kwargs"></a>kwargs |  more attributes common to every rule, e.g. `features`, of every target.   |  none |


