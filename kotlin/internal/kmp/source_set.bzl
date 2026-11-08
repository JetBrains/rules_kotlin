"""kt_source_set: a Kotlin Multiplatform source set, which the rules of each platform compile as a fragment.

A source set is the Bazel form of a source set of the Kotlin Gradle plugin: Kotlin sources, the
libraries they use and the source sets they refine (Gradle's `dependsOn`). It compiles nothing by
itself. A Kotlin/Native, JVM or Android rule lists it in its `source_sets` and compiles its sources,
and those of the source sets it refines, transitively, in one compilation with its own `srcs`, as the
K2 fragments of a multiplatform module (see fragments.bzl): the `expect` declarations of the common
code and the `actual` ones of the platform are in one module, as Kotlin requires.

A source set also provides a JavaInfo of no classes of its own that exports the JavaInfo of its deps,
for the aspects reaching it through the `runtime_deps` of a JVM or Android rule (see fragments.bzl)
that forward nothing from a target without JavaInfo: the mobile-install of rules_android
(mobile_install/adapters/default.bzl) dexes the `runtime_output_jars` of the targets with JavaInfo
it reaches and ignores the others, deps and all.
"""

load("@rules_java//java:defs.bzl", "JavaInfo")
load("//kotlin/internal/utils:utils.bzl", "utils")

KtSourceSetInfo = provider(
    doc = "A Kotlin Multiplatform source set: a fragment of the compilations of the rules listing it in their `source_sets`.",
    fields = {
        "depends_on": "tuple of KtSourceSetInfo: the source sets this one refines, Gradle's `dependsOn`.",
        "deps": """list of Target: the libraries the sources use. They are resolved in the configuration of each
        rule compiling the source set: a JVM or Android rule needs them to provide JavaInfo, a Kotlin/Native one
        KtKlibInfo.""",
        "label": "Label: the label of the source set.",
        "name": """string: the name of the fragment, derived from the label as module names are: `<package>-<name>`,
        with `/` replaced by `_`, or `<name>` in the root package.""",
        "srcs": "list of File: the Kotlin sources of the fragment.",
        "transitive_source_sets": """depset of KtSourceSetInfo, in postorder: the source sets this one refines,
        transitively, and this one, each after the source sets it refines. Their own transitive_source_sets is
        None.""",
    },
)

def _kt_source_set_impl(ctx):
    name = utils.derive_module_name(ctx)
    if "," in name:
        fail("%s: the fragment name '%s' of the source set contains ',', which separates the fragments of " % (ctx.label, name) +
             "-Xfragments; rename the target")

    # A tuple: a fragment is an element of the depsets of the source sets refining it, which must not
    # be mutable.
    depends_on = tuple([source_set[KtSourceSetInfo] for source_set in ctx.attr.depends_on])
    fragment = KtSourceSetInfo(
        depends_on = depends_on,
        deps = ctx.attr.deps,
        label = ctx.label,
        name = name,
        srcs = ctx.files.srcs,
        transitive_source_sets = None,
    )
    return [
        DefaultInfo(files = depset(ctx.files.srcs)),
        # The rules compiling the source set instrument its sources.
        coverage_common.instrumented_files_info(
            ctx,
            source_attributes = ["srcs"],
            dependency_attributes = ["depends_on"],
            extensions = ["kt"],
        ),
        # Below a Kotlin/Native rule the deps are klibs: nothing to export.
        JavaInfo(
            output_jar = ctx.file._empty_jar,
            compile_jar = ctx.file._empty_jar,
            exports = [dep[JavaInfo] for dep in ctx.attr.deps if JavaInfo in dep],
        ),
        KtSourceSetInfo(
            depends_on = depends_on,
            deps = ctx.attr.deps,
            label = ctx.label,
            name = name,
            srcs = ctx.files.srcs,
            transitive_source_sets = depset(
                [fragment],
                transitive = [parent.transitive_source_sets for parent in depends_on],
                order = "postorder",
            ),
        ),
    ]

kt_source_set = rule(
    doc = """A Kotlin Multiplatform source set: Kotlin sources, the libraries they use and the source sets they refine.

    Experimental. A source set compiles nothing by itself. The Kotlin/Native, JVM and Android rules
    compile the source sets of their `source_sets` attribute, and those they refine, transitively,
    together with their own `srcs`, as the fragments of one multiplatform compilation
    (`-Xmulti-platform -Xfragments`), the way the Kotlin Gradle plugin compiles a platform: the
    `expect` declarations of a common source set and the `actual` ones in the `srcs` of the rule of a
    platform are in one module. Expect/actual classes are Beta in Kotlin; the rules pass
    `-Xexpect-actual-classes`, which acknowledges it.

    The deps are resolved in the configuration of each rule compiling the source set, so they must
    provide what that rule needs: JavaInfo for a JVM or Android rule, a klib of the konan target for a
    Kotlin/Native one. A dep that differs per platform is an `alias` that selects its klib on
    `@rules_kotlin//kotlin/native/platforms:native_<konan target>`, which the Kotlin/Native rules
    match, its Android library on `@platforms//os:android` and its JVM library by default.

    A source set is no library: the JVM and Android rules reject it in `deps` or `exports`. It
    provides a JavaInfo of no classes of its own that exports the JavaInfo of its deps, for the
    aspects of the consumers of a rule that lists it in `runtime_deps` (see there).""",
    implementation = _kt_source_set_impl,
    attrs = {
        "depends_on": attr.label_list(
            doc = """The source sets this one refines, as Gradle's `dependsOn`: e.g. the source set of the Apple
            targets refines the common one.""",
            providers = [KtSourceSetInfo],
        ),
        "deps": attr.label_list(
            doc = """The libraries the sources use. Every rule compiling the source set compiles against them: they
            are JVM libraries for a JVM or Android rule, klibs for a Kotlin/Native one.""",
        ),
        "srcs": attr.label_list(
            doc = "Kotlin sources.",
            allow_files = [".kt"],
        ),
        "_empty_jar": attr.label(
            doc = "The jar of the JavaInfo of the source set, which has no classes of its own.",
            allow_single_file = True,
            cfg = "target",
            default = Label("//third_party:empty.jar"),
        ),
    },
    provides = [JavaInfo, KtSourceSetInfo],
)
