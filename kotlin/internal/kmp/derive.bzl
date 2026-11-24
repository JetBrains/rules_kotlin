"""The K2 fragments of a kt_multiplatform_library, derived from the sources of the groups and platforms of its hierarchy.

The owners of a source are the groups and platforms (see hierarchy.bzl) whose srcs list it, none
above another. The sources of the same owners form one fragment: the sources of a group are the
fragment named after it, e.g. `common` or `ios`, and those of a platform are the leaf of its
compilation, named after the platform, which may be empty. A source that several groups or
platforms list is shared by exactly those, in a fragment named after them, sorted and joined with
`-`, e.g. `jvm-native`. The platforms of a fragment are the targeted platforms at or below its
owners. A fragment refines the fragments directly above it: `A` refines `B` when every owner of `A`
is at or below an owner of `B`, and no fragment lies in between. A leaf refines the fragments
directly above its platform.

Groups of the same platforms stay apart, e.g. `common`, `native`, `apple` and `ios` in a library of
iOS targets only, so an `expect` declaration of one and its `actual` in a lower one are in two
fragments. The compilation of a platform gets every fragment its platform compiles, most shared
first, each after those it refines, and then its leaf (see fragments.bzl). Sources are told apart
by label: a file that two labels name is in two fragments, which the analysis of the compilation
reports.
"""

def fragment_name(owners):
    """The name of the fragment of the sources that some groups or platforms list: their names, sorted and joined with `-`.

    Args:
      owners: the names of the groups or platforms, e.g. `["native", "jvm"]`.

    Returns:
      The name, e.g. `jvm-native`, or `ios` for `["ios"]`.
    """
    return "-".join(sorted(owners))

def _covers(lower, upper, lineage):
    """Whether every node of `lower` is at or below a node of `upper`, both lists of nodes."""
    for node in lower:
        if not [above for above in upper if above in lineage[node]]:
            return False
    return True

def _direct(candidates, lineage):
    """The candidates, structs with `owners`, that no other candidate is below."""
    return [
        candidate
        for candidate in candidates
        if not [
            other
            for other in candidates
            if other.name != candidate.name and _covers(other.owners, candidate.owners, lineage)
        ]
    ]

def _most_shared_first(fragment):
    return (-len(fragment.platforms), fragment.rank, fragment.name)

def derive_fragments(node_srcs, lineage, targeted):
    """The fragments of a kt_multiplatform_library, from the sources of its groups and platforms.

    Args:
      node_srcs: a dict of each group or platform to the labels of its sources, as strings that are
        equal for equal labels. A node lists a label once, and the nodes listing a label are none
        above another.
      lineage: a dict of each node of the hierarchy to the nodes from the root down to it.
      targeted: a dict of each node at or above a targeted platform to the targeted platforms at or
        below it, in tree order, as resolve_platforms returns it: the nodes are visited in its
        order, and the nodes of `node_srcs` it lacks are ignored.

    Returns:
      A struct of:
      - `fragments`: a struct(name, owners, platforms, rank, srcs, refines) per set of owners that
        is not a single platform, most shared first, each after those it refines, then by name.
        `owners` are sorted, `platforms` are in tree order, `srcs` are the labels in the order the
        nodes list them, `rank` is 0 for a fragment that refines nothing and otherwise one more than
        the highest rank it refines, and `refines` are the names of the fragments directly above it,
        in the order of `fragments`;
      - `leaf_srcs`: a dict of each targeted platform to the labels that it alone lists, in its order;
      - `leaf_refines`: a dict of each targeted platform to the names of the fragments directly
        above it, which its leaf refines, in the order of `fragments`.
    """
    roots = [node for node in targeted if len(lineage[node]) == 1]
    platforms = targeted[roots[0]] if roots else []

    # The nodes listing each label, and the labels in the order the nodes list them.
    owners = {}
    for node in targeted:
        for label in node_srcs.get(node, []):
            listing = owners.setdefault(label, [])
            if node not in listing:
                listing.append(node)

    leaf_srcs = {platform: [] for platform in platforms}
    grouped = {}
    for label, listing in owners.items():
        if len(listing) == 1 and listing[0] in leaf_srcs:
            leaf_srcs[listing[0]].append(label)
        else:
            grouped.setdefault(fragment_name(listing), struct(owners = sorted(listing), srcs = [])).srcs.append(label)

    found = [
        struct(
            name = name,
            owners = fragment.owners,
            platforms = [platform for platform in platforms if _covers([platform], fragment.owners, lineage)],
            srcs = fragment.srcs,
        )
        for name, fragment in grouped.items()
    ]

    # The fragments above a fragment are above every fragment below it too: those with fewer
    # fragments above them come first, before any fragment refining them.
    above = {
        fragment.name: [
            other
            for other in found
            if other.name != fragment.name and _covers(fragment.owners, other.owners, lineage)
        ]
        for fragment in found
    }

    def _fewest_above_first(fragment):
        return (len(above[fragment.name]), fragment.name)

    rank = {}
    refines = {}
    for fragment in sorted(found, key = _fewest_above_first):
        direct = _direct(above[fragment.name], lineage)
        refines[fragment.name] = direct
        rank[fragment.name] = 1 + max([rank[refined.name] for refined in direct]) if direct else 0

    ordered = sorted(
        [
            struct(
                name = fragment.name,
                owners = fragment.owners,
                platforms = fragment.platforms,
                rank = rank[fragment.name],
                srcs = fragment.srcs,
            )
            for fragment in found
        ],
        key = _most_shared_first,
    )
    order = {fragment.name: index for index, fragment in enumerate(ordered)}

    def _in_order(name):
        return order[name]

    def _names(fragments):
        return sorted([fragment.name for fragment in fragments], key = _in_order)

    return struct(
        fragments = [
            struct(
                name = fragment.name,
                owners = fragment.owners,
                platforms = fragment.platforms,
                rank = fragment.rank,
                srcs = fragment.srcs,
                refines = _names(refines[fragment.name]),
            )
            for fragment in ordered
        ],
        leaf_srcs = leaf_srcs,
        leaf_refines = {
            platform: _names(_direct(
                [fragment for fragment in found if _covers([platform], fragment.owners, lineage)],
                lineage,
            ))
            for platform in platforms
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
