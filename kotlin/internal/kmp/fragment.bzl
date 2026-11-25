"""kt_kmp_fragment and kt_kmp_fragments_graph: K2 fragment targets of a kt_multiplatform_library.

kt_multiplatform_library declares one kt_kmp_fragment per fragment it derives (see derive.bzl), and
one kt_kmp_fragments_graph, `<name>.fragments`, printing the derived fragment graph. A fragment
compiles nothing by itself and has no deps: the libraries listing it in `kmp_fragments` compile its
sources with their srcs, against their own deps (see fragments.bzl).

Internal: kt_multiplatform_library is their only user.
"""

KtFragmentInfo = provider(
    doc = "A K2 fragment of a kt_multiplatform_library: the sources of a group of its hierarchy, or of one of its aliases.",
    fields = {
        "name": "string: the name of the fragment, e.g. `common`, `ios` or `non_android`.",
        "platforms": "tuple of string: the platforms compiling the sources, sorted.",
        "rank": """int: 0 for a fragment that refines nothing, and otherwise one more than the highest rank of the
        fragments it refines, so that a fragment comes after those it refines among fragments of as many platforms.""",
        "refines": "tuple of string: the names of the fragments directly above this one, whose platforms include its own.",
        "srcs": "list of File: the Kotlin sources of the fragment.",
        "transitive_fragments": """depset of KtFragmentInfo, in postorder: the fragments this one refines,
        transitively, and this one, each after the fragments it refines. Their own transitive_fragments is None.""",
    },
)

KtFragmentsGraphInfo = provider(
    doc = "The formatted K2 fragment refinement graph of a kt_multiplatform_library.",
    fields = {
        "graph": "string: the formatted fragment graph.",
    },
)

def _default_name(platforms):
    """The name of a fragment that is given none: its platforms, sorted and joined with `-`, e.g. `ios_arm64-jvm`."""
    return "-".join(sorted(platforms))

def _kt_kmp_fragment_impl(ctx):
    platforms = tuple(sorted(ctx.attr.platforms))
    if not platforms or len({platform: True for platform in platforms}) != len(platforms):
        fail("%s: a fragment is compiled by one or more distinct platforms, not %s" % (ctx.label, list(platforms)))
    name = ctx.attr.fragment_name or _default_name(platforms)
    refined = [fragment[KtFragmentInfo] for fragment in ctx.attr.refines]
    for fragment in refined:
        missing = [platform for platform in platforms if platform not in fragment.platforms]
        if missing:
            fail("%s: the fragment '%s' cannot refine '%s', which %s %s not compile" % (
                ctx.label,
                name,
                fragment.name,
                " and ".join(missing),
                "does" if len(missing) == 1 else "do",
            ))
    rank = 1 + max([fragment.rank for fragment in refined]) if refined else 0

    # Tuples: a fragment is an element of the depsets of the fragments refining it, which must not be
    # mutable.
    refines = tuple([fragment.name for fragment in refined])
    own = KtFragmentInfo(
        name = name,
        platforms = platforms,
        rank = rank,
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
            rank = rank,
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
    doc = """Sources that some platforms of a kt_multiplatform_library compile: a K2 fragment of their compilations.

    Internal: kt_multiplatform_library declares one per group of its hierarchy and per alias with
    sources. It compiles nothing by itself: the libraries of its platforms list it, or a fragment
    refining it, in `kmp_fragments`.""",
    implementation = _kt_kmp_fragment_impl,
    attrs = {
        "fragment_name": attr.string(
            doc = "The name of the fragment, e.g. `ios`; by default its platforms, sorted and joined with `-`.",
        ),
        "platforms": attr.string_list(
            doc = "The platforms compiling the sources, `jvm`, `android` and konan targets: one or more.",
            mandatory = True,
        ),
        "refines": attr.label_list(
            doc = """The fragments directly above this one, which every platform of this one compiles, e.g. those of
            the groups and the aliases above its group.""",
            providers = [KtFragmentInfo],
        ),
        "srcs": attr.label_list(
            doc = "Kotlin sources.",
            allow_files = [".kt"],
        ),
    },
    provides = [KtFragmentInfo],
)

_BATCH_ESCAPED = ["\"", "&", "|", "<", ">", "(", ")"]

def _unix_launcher(graph):
    return "#!/usr/bin/env sh\nprintf '%%s' '%s'\n" % graph.replace("'", "'\\''")

def _escape_batch_line(line):
    escaped = line.replace("^", "^^").replace("%", "%%")
    for ch in _BATCH_ESCAPED:
        escaped = escaped.replace(ch, "^" + ch)
    return "echo(" + escaped

def _windows_launcher(graph):
    lines = ["@echo off", "setlocal DisableDelayedExpansion"]
    for line in graph.splitlines():
        lines.append(_escape_batch_line(line))
    return "\r\n".join(lines) + "\r\n"

def _kt_kmp_fragments_graph_impl(ctx):
    windows_constraint = ctx.attr._windows_constraint[platform_common.ConstraintValueInfo]
    is_windows = ctx.target_platform_has_constraint(windows_constraint)
    launcher = ctx.actions.declare_file(ctx.label.name + (".bat" if is_windows else ".sh"))
    content = _windows_launcher(ctx.attr.graph) if is_windows else _unix_launcher(ctx.attr.graph)
    ctx.actions.write(
        output = launcher,
        content = content,
        is_executable = True,
    )
    return [
        DefaultInfo(
            files = depset([launcher]),
            executable = launcher,
        ),
        KtFragmentsGraphInfo(graph = ctx.attr.graph),
    ]

kt_kmp_fragments_graph = rule(
    doc = """Prints the derived K2 fragment refinement graph of a kt_multiplatform_library.

    Internal: kt_multiplatform_library declares `<name>.fragments` with the formatted graph.""",
    implementation = _kt_kmp_fragments_graph_impl,
    attrs = {
        "graph": attr.string(
            doc = "The formatted fragment graph printed to stdout.",
            mandatory = True,
        ),
        "_windows_constraint": attr.label(
            default = "@platforms//os:windows",
        ),
    },
    executable = True,
    provides = [KtFragmentsGraphInfo],
)
