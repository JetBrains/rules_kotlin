"""The qualifiers of a kt_multiplatform_library: the groups and platforms it targets, and its aliases.

A qualifier names some of the listed platforms and qualifies the lists of the macro, e.g. `srcs_ios`
or `deps_non_android`. The groups and the platforms of the hierarchy (see hierarchy.bzl) at or above
a listed platform are qualifiers. An alias is a qualifier that the library declares for platforms
that no group gathers, e.g. `non_android` for `jvm` and the konan targets.

A qualifier refines another one when that one is above it in the hierarchy, and otherwise when its
platforms are some of the platforms of the other one, but not all of them. Groups of the same
platforms, e.g. `native`, `apple` and `ios` in a library of iOS targets only, are ordered by the
hierarchy, and an alias is ordered by its platforms. Two qualifiers of the same platforms that the
hierarchy does not order would refine neither each other, so an alias of the platforms of a group,
of a platform or of another alias is an error.
"""

load(":hierarchy.bzl", "name_error")

def _error(message):
    return struct(error = "aliases: " + message)

def _alias_error(hierarchy, targeted, name, members):
    """The error of the name and of the members of an alias, or None."""
    error = name_error(name)
    if error:
        return error
    if name in hierarchy.lineage:
        return "'%s' is a %s of the hierarchy: give the alias another name" % (
            name,
            "group" if name in hierarchy.groups else "platform",
        )
    if type(members) != "list":
        return "'%s' must be a list of the platforms it groups, not a %s" % (name, type(members))
    if not members:
        return "'%s' must list the platforms it groups" % name
    listed = {}
    for member in members:
        if type(member) != "string":
            return "'%s' must list the names of platforms, not a %s" % (name, type(member))
        if member in hierarchy.groups:
            among = sorted(targeted.get(member, []))
            return "'%s' lists the group '%s': list its platforms instead, %s" % (
                name,
                member,
                "among " + ", ".join(among) if among else "though platforms lists none of them",
            )
        if member not in hierarchy.lineage:
            return "'%s' lists the unknown platform '%s'; the listed ones are %s" % (
                name,
                member,
                ", ".join(sorted(targeted.get(hierarchy.root, []))),
            )
        if member not in targeted:
            return "'%s' lists %s, which platforms does not list" % (name, member)
        if member in listed:
            return "'%s' lists '%s' twice" % (name, member)
        listed[member] = True
    return None

def _same_platforms_error(hierarchy, name, nodes):
    """The error of an alias of the platforms of some groups and platforms."""
    if hierarchy.root in nodes:
        return "'%s' groups every platform: the lists of the macro without a qualifier, e.g. srcs, are those of every platform" % name
    if len(nodes) > 1:
        return "'%s' groups the platforms of %s: use one of those qualifiers instead" % (name, ", ".join(nodes))
    if nodes[0] in hierarchy.platforms:
        return "'%s' groups %s alone: use that qualifier instead" % (name, nodes[0])
    return "'%s' groups the platforms of %s: use that qualifier instead" % (name, nodes[0])

def resolve_qualifiers(hierarchy, targeted, aliases):
    """The qualifiers of a kt_multiplatform_library and their order, from its targeted nodes and its aliases.

    Args:
      hierarchy: a struct returned by `make_hierarchy`.
      targeted: a dict of each node at or above a listed platform to the listed platforms at or
        below it, in tree order, as `resolve_platforms` returns it.
      aliases: the `aliases` of the macro: a dict of the name of each alias to the listed platforms
        it groups, in any order, or None for no alias.

    Returns:
      `struct(error = message)` for the first error, the aliases taken in the order of the dict:
      `aliases` is not a dict, a name is not made of lowercase letters, digits and `_` or is the
      name of a node of the hierarchy, the members are not a non-empty list of names, or list a
      group, an unknown platform, a platform that is not listed or a platform twice, or the alias
      groups the platforms of a targeted node or of another alias. Otherwise a struct of:
      - `error`: None;
      - `names`: the targeted nodes and the aliases, each after the qualifiers it refines: those
        of more platforms first, then the nodes in tree order, then the aliases by name;
      - `leaves`: the listed platforms, in tree order;
      - `platforms`: a dict of each qualifier to the listed platforms it covers, in tree order;
      - `aliases`: a dict of each alias to its platforms, in tree order;
      - `above`: a dict of each qualifier to the qualifiers it refines, in the order of `names`;
      - `of_platform`: a dict of each listed platform to the qualifiers covering it, in the order
        of `names`, which ends with the platform.
    """
    if aliases == None:
        aliases = {}
    if type(aliases) != "dict":
        return struct(error = "aliases must be a dict of a name to the platforms it groups, not a %s" % type(aliases))
    leaves = targeted.get(hierarchy.root, [])

    nodes_of = {}
    for node, below in targeted.items():
        nodes_of.setdefault(tuple(below), []).append(node)
    alias_of = {}
    resolved = {}
    for name, members in aliases.items():
        error = _alias_error(hierarchy, targeted, name, members)
        if error:
            return _error(error)
        grouped = tuple([platform for platform in leaves if platform in members])
        if grouped in nodes_of:
            return _error(_same_platforms_error(hierarchy, name, nodes_of[grouped]))
        if grouped in alias_of:
            return _error("'%s' and '%s' group the same platforms: declare one of them" % (alias_of[grouped], name))
        alias_of[grouped] = name
        resolved[name] = list(grouped)

    platforms = dict(targeted)
    platforms.update(resolved)
    tree_index = {node: index for index, node in enumerate(hierarchy.nodes)}

    def _most_platforms_first(qualifier):
        if qualifier in resolved:
            return (-len(platforms[qualifier]), 1, qualifier)
        return (-len(platforms[qualifier]), 0, tree_index[qualifier])

    names = sorted(platforms, key = _most_platforms_first)

    def _refines(lower, upper):
        if lower in hierarchy.lineage and upper in hierarchy.lineage:
            if upper in hierarchy.lineage[lower][:-1]:
                return True
            if lower in hierarchy.lineage[upper][:-1]:
                return False
        if len(platforms[upper]) <= len(platforms[lower]):
            return False
        return not [platform for platform in platforms[lower] if platform not in platforms[upper]]

    return struct(
        error = None,
        names = names,
        leaves = leaves,
        platforms = platforms,
        aliases = resolved,
        above = {
            qualifier: [other for other in names if _refines(qualifier, other)]
            for qualifier in names
        },
        of_platform = {
            platform: [qualifier for qualifier in names if platform in platforms[qualifier]]
            for platform in leaves
        },
    )

def direct(qualifiers, candidates):
    """The qualifiers directly above one, among those above it.

    Args:
      qualifiers: a struct returned by `resolve_qualifiers`, without error.
      candidates: names of qualifiers.

    Returns:
      The candidates that no other candidate refines, in the order of `candidates`.
    """
    return [
        candidate
        for candidate in candidates
        if not [other for other in candidates if candidate in qualifiers.above[other]]
    ]
