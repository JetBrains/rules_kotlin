"""The hierarchy of the platforms of a kt_multiplatform_library: the default one of Kotlin Multiplatform.

The hierarchy is a tree whose inner nodes are groups and whose leaves are platforms.
`DEFAULT_HIERARCHY` describes it as `(group, members)` pairs, a member being a group of the table or
a platform. What kt_multiplatform_library knows of groups and platforms is derived from this table:
the qualified attributes (`srcs_ios`, `deps_apple`), the lists each platform receives, the fragments
and the messages. A group or a platform is added with one entry.

A library lists a platform in its `platforms` once a rule builds it: `jvm`, `android`, and the konan
targets of //kotlin/internal/native:targets.bzl below `native`. The others, `ios_x64` among them,
have their place in the tree and are reported as not supported yet.
"""

DEFAULT_HIERARCHY = [
    ("common", ["jvm", "android", "native"]),
    ("native", ["linux", "apple"]),
    ("linux", ["linux_x64", "linux_arm64"]),
    ("apple", ["macos", "ios"]),
    ("macos", ["macos_arm64"]),
    ("ios", ["ios_arm64", "ios_simulator_arm64", "ios_x64"]),
]

_ROOT = "common"

_NAME_CHARS = "abcdefghijklmnopqrstuvwxyz0123456789_"

# The platforms of the example of the message of a declaration that lists none.
_EXAMPLE_PLATFORMS = ["jvm", "android", "ios_arm64"]

def _quoted(name):
    return "'%s'" % name if type(name) == "string" else repr(name)

def name_error(name):
    """The error of the name of a group, a platform or an alias.

    Args:
      name: the name.

    Returns:
      The message, or None when the name is made of lowercase letters, digits and `_`.
    """
    message = "%s is not a name of lowercase letters, digits and _" % _quoted(name)
    if type(name) != "string" or not name:
        return message
    for char in name.elems():
        if char not in _NAME_CHARS:
            return message
    return None

def hierarchy_error(groups):
    """The error of a table of the hierarchy, or None when it describes a tree rooted at `common`.

    Args:
      groups: a list of `(group, members)` pairs, `members` being the names of the groups and the
        platforms directly below the group.

    Returns:
      The message of the first error, or None: every name is made of lowercase letters, digits and
      `_`, a group is listed once and has members, a member has a single group, and every node is
      below `common`, the root, which is a member of no group.
    """
    if type(groups) != "list" or not groups:
        return "the hierarchy must be a non-empty list of (group, members) pairs"
    parent = {}
    listed = {}
    for entry in groups:
        if type(entry) not in ("tuple", "list") or len(entry) != 2 or type(entry[1]) != "list":
            return "the entry %r of the hierarchy is not a (group, members) pair" % (entry,)
        group, members = entry
        error = name_error(group)
        if error:
            return error
        if group in listed:
            return "the hierarchy lists the group '%s' twice" % group
        listed[group] = True
        if not members:
            return "the group '%s' has no members, so it would be both a group and a platform" % group
        for member in members:
            error = name_error(member)
            if error:
                return error
            if member in parent:
                if parent[member] == group:
                    return "the group '%s' lists '%s' twice" % (group, member)
                return "'%s' is a member of both '%s' and '%s'" % (member, parent[member], group)
            parent[member] = group
    if _ROOT not in listed:
        return "the hierarchy has no group %s, its root" % _ROOT
    if _ROOT in parent:
        return "the group '%s' lists %s, the root of the hierarchy" % (parent[_ROOT], _ROOT)
    for group in listed:
        if group != _ROOT and group not in parent:
            return "the group '%s' is a member of no group: every group but %s is a member of one" % (group, _ROOT)

    # Climb from every node, at most once per node: a node that does not reach the root is in a cycle.
    nodes = list(listed) + [member for member in parent if member not in listed]
    for node in nodes:
        climbed = node
        for _ in nodes:
            if climbed not in parent:
                break
            climbed = parent[climbed]
        if climbed != _ROOT:
            return "'%s' is not below %s: its groups form a cycle" % (node, _ROOT)
    return None

def make_hierarchy(groups):
    """The hierarchy a table describes, indexed once.

    Args:
      groups: a list of `(group, members)` pairs, as `DEFAULT_HIERARCHY`, which `hierarchy_error`
        accepts. The call fails otherwise.

    Returns:
      A struct of:
      - `root`: `common`;
      - `nodes`: the names of the groups and the platforms, in tree order;
      - `groups`: the names of the groups, in tree order;
      - `platforms`: the names of the platforms, in tree order;
      - `lineage`: a dict of each node to the nodes from the root down to it, both included;
      - `members`: a dict of each node to the platforms at or below it, in tree order: a platform is
        its only member.
      Tree order lists a group before its members, and the members of a group in the order of the
      table.
    """
    error = hierarchy_error(groups)
    if error:
        fail("invalid hierarchy: " + error)
    children = {}
    parent = {}
    for group, members in groups:
        children[group] = members
        for member in members:
            parent[member] = group

    # A walk of the tree with a stack, as Starlark has neither recursion nor while: it pops each node
    # once, and pushes its members so that the first one is popped next.
    nodes = []
    stack = [_ROOT]
    for _ in range(1 + len(parent)):
        node = stack.pop()
        nodes.append(node)
        stack.extend(reversed(children.get(node, [])))

    lineage = {}
    for node in nodes:
        lineage[node] = (lineage[parent[node]] if node in parent else []) + [node]
    platforms = [node for node in nodes if node not in children]
    members = {node: [] for node in nodes}
    for platform in platforms:
        for node in lineage[platform]:
            members[node].append(platform)
    return struct(
        root = _ROOT,
        nodes = nodes,
        groups = [node for node in nodes if node in children],
        platforms = platforms,
        lineage = lineage,
        members = members,
    )

HIERARCHY = make_hierarchy(DEFAULT_HIERARCHY)

def _looks_like_label(name):
    return name.startswith("@") or ":" in name or "/" in name

def _unknown_platform_error(name, supported):
    message = "platforms lists the unknown platform '%s'; " % name
    if _looks_like_label(name):
        short = name.rpartition(":")[2].rpartition("/")[2]
        if short in supported:
            return message + "it takes the names of platforms, not labels: write '%s'" % short
        message += "it takes the names of platforms, not labels, and "
    return message + "the supported ones are " + ", ".join(sorted(supported))

def resolve_platforms(hierarchy, platforms, unsupported = {}):
    """The targeted part of a hierarchy: the platforms a kt_multiplatform_library lists, and the nodes above them.

    Args:
      hierarchy: a struct returned by `make_hierarchy`.
      platforms: the `platforms` of the macro: names of platforms of the hierarchy, in any order.
      unsupported: a dict of the platforms of the hierarchy that no rule builds yet to the reason,
        e.g. `{"ios_x64": "rules_kotlin has no Kotlin/Native toolchain for it"}`.

    Returns:
      `struct(error = message)` when `platforms` is missing or empty, is not a list of names, or
      lists a group, an unknown or unsupported platform, or a platform twice. Otherwise a struct of:
      - `error`: None;
      - `platforms`: the listed platforms, in tree order;
      - `targeted`: a dict of each node at or above a listed platform to the listed platforms at or
        below it, in tree order.
    """
    supported = [platform for platform in hierarchy.platforms if platform not in unsupported]
    if platforms == None or platforms == []:
        return struct(error = "it declares no platforms: list them in platforms, e.g. %s" % repr(_EXAMPLE_PLATFORMS))
    if type(platforms) != "list":
        return struct(error = "platforms must be a list of the names of platforms, not a %s" % type(platforms))
    listed = {}
    for platform in platforms:
        if type(platform) != "string":
            return struct(error = "platforms must list the names of platforms, not a %s" % type(platform))
        if platform in hierarchy.groups:
            among = [member for member in hierarchy.members[platform] if member not in unsupported]
            return struct(error = "platforms lists the group '%s': list the platforms to build for instead, %s" % (
                platform,
                "among " + ", ".join(sorted(among)) if among else "though none of its platforms is supported yet",
            ))
        if platform not in hierarchy.members:
            return struct(error = _unknown_platform_error(platform, supported))
        if platform in unsupported:
            return struct(error = "platform '%s' is not supported yet: %s" % (platform, unsupported[platform]))
        if platform in listed:
            return struct(error = "platforms lists '%s' twice" % platform)
        listed[platform] = True

    targeted = {}
    for node in hierarchy.nodes:
        below = [platform for platform in hierarchy.members[node] if platform in listed]
        if below:
            targeted[node] = below
    return struct(
        error = None,
        platforms = targeted[hierarchy.root],
        targeted = targeted,
    )
