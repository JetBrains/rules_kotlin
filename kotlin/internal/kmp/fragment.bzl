"""kt_kmp_fragment: sources that some platforms of a kt_multiplatform_library share, a K2 fragment of their compilations.

kt_multiplatform_library declares one, `<name>_fragment_<fragment name>`, per set of two or more of
its platforms that list the same sources (see derive.bzl). A fragment compiles nothing by itself and
has no deps: kt_jvm_library, kt_android_library and kt_native_library list in `kmp_fragments` the
fragments their srcs refine, and compile the sources of those fragments, and of the fragments they
refine, transitively, with their srcs, against their own deps (see fragments.bzl).

Internal: kt_multiplatform_library is its only user.
"""

load(":derive.bzl", "fragment_name")

KtFragmentInfo = provider(
    doc = "A K2 fragment of a kt_multiplatform_library: the sources that exactly the same platforms list.",
    fields = {
        "name": "string: the name of the fragment, its platforms sorted and joined with `-`, e.g. `android-jvm`.",
        "platforms": "tuple of string: the platforms listing the sources, sorted.",
        "refines": "tuple of string: the names of the fragments directly above this one, whose platforms include its own.",
        "srcs": "list of File: the Kotlin sources of the fragment.",
        "transitive_fragments": """depset of KtFragmentInfo, in postorder: the fragments this one refines,
        transitively, and this one, each after the fragments it refines. Their own transitive_fragments is None.""",
    },
)

def _kt_kmp_fragment_impl(ctx):
    platforms = tuple(sorted(ctx.attr.platforms))
    if len(platforms) < 2 or len({platform: True for platform in platforms}) != len(platforms):
        fail("%s: a fragment is shared by two or more distinct platforms, not %s" % (ctx.label, list(platforms)))
    name = fragment_name(platforms)
    refined = [fragment[KtFragmentInfo] for fragment in ctx.attr.refines]
    for fragment in refined:
        if len(fragment.platforms) <= len(platforms) or [platform for platform in platforms if platform not in fragment.platforms]:
            fail("%s: the fragment '%s' cannot refine '%s', which is not shared by more platforms, including its own" %
                 (ctx.label, name, fragment.name))

    # Tuples: a fragment is an element of the depsets of the fragments refining it, which must not be
    # mutable.
    refines = tuple([fragment.name for fragment in refined])
    own = KtFragmentInfo(
        name = name,
        platforms = platforms,
        refines = refines,
        srcs = ctx.files.srcs,
        transitive_fragments = None,
    )
    return [
        DefaultInfo(files = depset(ctx.files.srcs)),
        # The libraries compiling the fragment instrument its sources.
        coverage_common.instrumented_files_info(
            ctx,
            source_attributes = ["srcs"],
            dependency_attributes = ["refines"],
            extensions = ["kt"],
        ),
        KtFragmentInfo(
            name = name,
            platforms = platforms,
            refines = refines,
            srcs = ctx.files.srcs,
            transitive_fragments = depset(
                [own],
                transitive = [fragment.transitive_fragments for fragment in refined],
                order = "postorder",
            ),
        ),
    ]

kt_kmp_fragment = rule(
    doc = """Sources that some platforms of a kt_multiplatform_library share: a K2 fragment of their compilations.

    Internal: kt_multiplatform_library declares one per set of two or more platforms listing the same
    sources. It compiles nothing by itself: the libraries of those platforms list it, or a fragment
    refining it, in `kmp_fragments`.""",
    implementation = _kt_kmp_fragment_impl,
    attrs = {
        "platforms": attr.string_list(
            doc = "The platforms listing the sources, `jvm`, `android` and konan targets: two or more. They name the fragment.",
            mandatory = True,
        ),
        "refines": attr.label_list(
            doc = """The fragments directly above this one: those of the smallest sets of more platforms that include
            these ones.""",
            providers = [KtFragmentInfo],
        ),
        "srcs": attr.label_list(
            doc = "Kotlin sources.",
            allow_files = [".kt"],
        ),
    },
    provides = [KtFragmentInfo],
)
