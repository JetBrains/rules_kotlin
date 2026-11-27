"""The K2 fragments of a kt_multiplatform_library, derived from the sources of the groups, aliases and platforms of its declaration.

The sources of a group of the hierarchy or of an alias (see qualifiers.bzl) form one fragment, named
after it, e.g. `common`, `ios` or `non_android`, and those of a platform are the leaf of its
compilation, named after the platform, which may be empty. A group or an alias without sources has
no fragment. The platforms of a fragment are the listed platforms its group or alias covers. A
fragment refines the fragments directly above it: `A` refines `B` when the group of `B` is above
that of `A` in the hierarchy, and otherwise when the platforms of `A` are some of the platforms of
`B`, but not all of them, and no fragment lies in between. A leaf refines the fragments directly
above its platform.

Groups of the same platforms stay apart, e.g. `common`, `native`, `apple` and `ios` in a library of
iOS targets only, so an `expect` declaration of one and its `actual` in a lower one are in two
fragments. The compilation of a platform gets every fragment its platform compiles, most shared
first, each after those it refines, and then its leaf (see fragments.bzl). A source is in one
fragment, and sources are told apart by label: a file that two labels name is in two fragments,
which the analysis of the compilation reports.

A library of one platform whose sources are all those of one group has no fragment: they are the
sources of the leaf of the platform, which is then compiled as a single-platform target.
"""

load(":qualifiers.bzl", "direct")

def _most_shared_first(fragment):
    return (-len(fragment.platforms), fragment.rank, fragment.name)

def _only_shared(qualifier_srcs, qualifiers, shared):
    """The group whose sources the only platform compiles alone, or None."""
    if len(qualifiers.leaves) != 1 or len(shared) != 1:
        return None
    if qualifier_srcs.get(qualifiers.leaves[0]):
        return None
    return list(shared)[0]

def derive_fragments(qualifier_srcs, qualifiers):
    """The fragments of a kt_multiplatform_library, from the sources of its groups, aliases and platforms.

    Args:
      qualifier_srcs: a dict of each group, alias or platform to the labels of its sources, as
        strings that are equal for equal labels. A label is listed once, by one of them. Those that
        `qualifiers` lacks, the nodes that are not targeted, are ignored.
      qualifiers: the qualifiers of the library and their order, as `resolve_qualifiers` returns
        them, without error.

    Returns:
      A struct of:
      - `fragments`: a struct(name, platforms, rank, srcs, refines) per group or alias with sources,
        most shared first, each after those it refines, then by name. `platforms` are in tree
        order, `srcs` are the labels in the order they are listed, `rank` is 0 for a fragment that
        refines nothing and otherwise one more than the highest rank it refines, and `refines` are
        the names of the fragments directly above it, in the order of `fragments`;
      - `leaf_srcs`: a dict of each listed platform to the labels of its sources, in their order;
      - `leaf_refines`: a dict of each listed platform to the names of the fragments directly
        above it, which its leaf refines, in the order of `fragments`.

      When a single platform is listed, it has no sources of its own and one group alone has
      sources, there is no fragment: `fragments` is empty, `leaf_srcs` maps the platform to the
      sources of that group and `leaf_refines` maps it to nothing.
    """
    shared = {
        qualifier: True
        for qualifier in qualifiers.names
        if qualifier not in qualifiers.leaves and qualifier_srcs.get(qualifier)
    }

    only = _only_shared(qualifier_srcs, qualifiers, shared)
    if only != None:
        platform = qualifiers.leaves[0]
        return struct(
            fragments = [],
            leaf_srcs = {platform: list(qualifier_srcs[only])},
            leaf_refines = {platform: []},
        )

    def _directly_above(qualifier):
        return direct(qualifiers, [above for above in qualifiers.above[qualifier] if above in shared])

    # `qualifiers.names` lists a qualifier after those it refines, whose ranks are thus known.
    rank = {}
    refines = {}
    for qualifier in shared:
        refines[qualifier] = _directly_above(qualifier)
        rank[qualifier] = 1 + max([rank[refined] for refined in refines[qualifier]]) if refines[qualifier] else 0

    ordered = sorted(
        [
            struct(
                name = qualifier,
                platforms = qualifiers.platforms[qualifier],
                rank = rank[qualifier],
                srcs = list(qualifier_srcs[qualifier]),
            )
            for qualifier in shared
        ],
        key = _most_shared_first,
    )
    order = {fragment.name: index for index, fragment in enumerate(ordered)}

    def _in_order(name):
        return order[name]

    return struct(
        fragments = [
            struct(
                name = fragment.name,
                platforms = fragment.platforms,
                rank = fragment.rank,
                srcs = fragment.srcs,
                refines = sorted(refines[fragment.name], key = _in_order),
            )
            for fragment in ordered
        ],
        leaf_srcs = {platform: list(qualifier_srcs.get(platform, [])) for platform in qualifiers.leaves},
        leaf_refines = {
            platform: sorted(_directly_above(platform), key = _in_order)
            for platform in qualifiers.leaves
        },
    )

def _identity(label):
    return label

def _append_node(lines, kind, name, refines, platforms, srcs, label_of):
    lines.append("%s %s" % (kind, name))
    if refines:
        lines.append("  refines: %s" % ", ".join(refines))
    if platforms:
        lines.append("  platforms: %s" % ", ".join(platforms))
    if srcs:
        lines.append("  srcs:")
        for src in srcs:
            lines.append("    %s" % label_of(src))

def format_fragments(derived, label_of = None):
    """Renders the derived shared fragments and platform leaves as deterministic text.

    Args:
      derived: a struct returned by `derive_fragments`.
      label_of: an optional function turning each source label in `derived` into its display
        string; when None, labels are rendered as stored in `derived`.

    Returns:
      The formatted fragment graph: the fragments in `derived.fragments` order, each with what it
      refines, the platforms compiling it and its sources, followed by the platform leaves in
      sorted platform order, ending with `\\n` (or `""` when empty).
    """
    display = label_of if label_of != None else _identity
    lines = []
    for fragment in derived.fragments:
        _append_node(lines, "fragment", fragment.name, fragment.refines, fragment.platforms, fragment.srcs, display)
    for platform in sorted(derived.leaf_srcs):
        _append_node(lines, "leaf", platform, derived.leaf_refines[platform], [], derived.leaf_srcs[platform], display)
    return "\n".join(lines) + "\n" if lines else ""
