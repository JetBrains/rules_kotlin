"""The declaration of a kt_multiplatform_library: its platforms, and the lists of each group and platform.

The macro takes the lists of a node of the hierarchy (see hierarchy.bzl) as `<attr>_<qualifier>`:
`<attr>` is `srcs`, `deps`, `exports` or `plugins`, and `<qualifier>` the name of a group or a
platform below `common`, whose lists are the unqualified `srcs`, `deps`, `exports` and `plugins`:

    kt_multiplatform_library(
        name = "shared",
        platforms = ["jvm", "ios_arm64", "ios_simulator_arm64"],
        srcs = COMMON,
        srcs_ios = IOS,
        deps_ios_arm64 = [":device_only"],
    )

Each platform receives, per attribute, the lists of its lineage from `common` down to itself: the
deps of `ios_arm64` are `deps + deps_native + deps_apple + deps_ios + deps_ios_arm64`. The dicts
`jvm`, `android` and `native` hold the other attributes of the library of their node.

`parse_declaration` checks a call when the macro is called, before any select() is resolved, and
names what to change. The names it reports come from the hierarchy.
"""

load("//kotlin/internal/native:targets.bzl", "KONAN_TARGETS")
load(":hierarchy.bzl", "HIERARCHY", "resolve_platforms")

# The list attributes of the libraries that a group or a platform qualifies.
QUALIFIED_ATTRS = ["srcs", "deps", "exports", "plugins"]

# The nodes of the hierarchy that have a library, which builds the platforms at or below the node.
LIBRARY_NODES = ["jvm", "android", "native"]

# How the messages call the library of each of LIBRARY_NODES.
_LIBRARY_NAMES = {
    "android": "Android",
    "jvm": "JVM",
    "native": "native",
}

# How the messages call the entries of each of QUALIFIED_ATTRS.
_ENTRIES = {
    "deps": "deps",
    "exports": "exports",
    "plugins": "plugins",
    "srcs": "sources",
}

# The attribute of the libraries that the macro derives, besides QUALIFIED_ATTRS.
_DERIVED_ATTR = "kmp_fragments"

def unsupported_platforms(hierarchy = HIERARCHY):
    """The platforms of a hierarchy that no rule of rules_kotlin builds yet, and why.

    Args:
      hierarchy: a struct returned by `make_hierarchy`.

    Returns:
      A dict of each such platform to the reason: a platform below `native` that is not a konan
      target of KONAN_TARGETS has no Kotlin/Native toolchain, and a platform at or below none of
      LIBRARY_NODES has no rules. With the default hierarchy, only `ios_x64`.
    """
    unsupported = {}
    for platform in hierarchy.platforms:
        lineage = hierarchy.lineage[platform]
        if "native" in lineage:
            if platform not in KONAN_TARGETS:
                unsupported[platform] = "rules_kotlin has no Kotlin/Native toolchain for it"
        elif not [node for node in LIBRARY_NODES if node in lineage]:
            unsupported[platform] = "rules_kotlin has no rules for it"
    return unsupported

def _error(message):
    return struct(error = message)

def _alternatives(names):
    """`a`, `a or b`, `a, b or c`."""
    return ", ".join(names[:-1]) + " or " + names[-1] if len(names) > 1 else "".join(names)

def _enumeration(names):
    """`a`, `a and b`, `a, b and c`."""
    return ", ".join(names[:-1]) + " and " + names[-1] if len(names) > 1 else "".join(names)

def _qualified(attr, node):
    return "%s_%s" % (attr, node)

def _subject(hierarchy, attr, node):
    """How the messages call the list of an attribute at a node, and the verb that agrees with it."""
    if node == hierarchy.root:
        return "the %s of the macro" % attr, "list"
    return _qualified(attr, node), "lists"

def _untargeted_error(hierarchy, unsupported, node, subject, does, remove):
    """The error of something set for a node none of whose platforms the declaration lists."""
    if node in hierarchy.platforms:
        return "%s %s, but platforms does not list %s" % (subject, does, node)
    message = "%s %s, but platforms lists no %s platform: " % (subject, does, node)
    supported = sorted([platform for platform in hierarchy.members[node] if platform not in unsupported])
    if not supported:
        return message + "none of them is supported yet, so remove %s" % remove
    return message + "add %s, or remove %s" % (_alternatives(supported), remove)

def _settings_error(hierarchy, unsupported, targeted, node, attrs):
    """The error of the dict of attributes of the library of a node, or None."""
    library = _LIBRARY_NAMES[node]
    if type(attrs) != "dict":
        return "%s must be a dict of attributes of the %s library, not a %s" % (node, library, type(attrs))
    for key in sorted(attrs):
        if key in QUALIFIED_ATTRS:
            return "%s sets %s: pass %s to the macro" % (node, key, _qualified(key, node))
        if key == _DERIVED_ATTR:
            return "%s sets %s, which the macro derives from the sources" % (node, key)
    if attrs and node not in targeted:
        return _untargeted_error(
            hierarchy,
            unsupported,
            node,
            node,
            "sets attributes of the %s library" % library,
            node,
        )
    return None

def _split_qualified(key):
    """The attribute and the qualifier of a key `<attr>_<qualifier>`, or None for another key."""
    for attr in QUALIFIED_ATTRS:
        if key.startswith(attr + "_"):
            return attr, key[len(attr) + 1:]
    return None

def _ends_with_node(hierarchy, key):
    for node in hierarchy.nodes:
        if key.endswith("_" + node):
            return True
    return False

def _list_error(hierarchy, unsupported, targeted, attr, node, value, selectable):
    """The error of the type of a list, or of entries for a node that no listed platform is at or below."""
    subject, _ = _subject(hierarchy, attr, node)
    if type(value) == "select":
        if attr == "srcs":
            return ("%s must be a list of labels, not a select: the macro derives the fragments from the sources " +
                    "when it is called, before any select() is resolved") % subject
        if node not in selectable:
            return ("%s must be a list of labels, not a select: only %s may be a select(), as the macro " +
                    "selects the %s of each konan target itself") % (
                subject,
                _enumeration([_qualified(attr, platform) for platform in selectable]),
                attr,
            )
    elif type(value) != "list":
        return "%s must be a list of labels, not a %s" % (subject, type(value))
    elif not value:
        return None
    if node not in targeted:
        return _untargeted_error(hierarchy, unsupported, node, subject, "lists " + _ENTRIES[attr], subject)
    return None

def parse_declaration(platforms, common, settings, kwargs, normalize = str, hierarchy = HIERARCHY, unsupported = None):
    """The declaration of a kt_multiplatform_library from the arguments of the macro, or its error.

    Args:
      platforms: the `platforms` of the macro.
      common: the `srcs`, `deps`, `exports` and `plugins` of the macro by attribute, the lists of
        `common`; a missing one is empty.
      settings: the `jvm`, `android` and `native` of the macro by name, each None or a dict.
      kwargs: the other keyword arguments of the macro: the `<attr>_<qualifier>` lists, and the
        attributes common to every rule.
      normalize: the function turning a label into a string equal for equal labels, to find the
        labels a list repeats; by default the label as written.
      hierarchy: a struct returned by `make_hierarchy`.
      unsupported: the platforms of the hierarchy that no rule builds yet, as `unsupported_platforms`
        returns them; by default those of `hierarchy`.

    Returns:
      `struct(error = message)` for the first error, the keyword arguments taken in sorted order
      and the lists in tree order. Otherwise a struct of:
      - `error`: None;
      - `hierarchy`: the hierarchy;
      - `platforms`: the listed platforms, in tree order;
      - `targeted`: a dict of each node at or above a listed platform to the listed platforms at or
        below it, in tree order;
      - `lists`: a dict of each of QUALIFIED_ATTRS to a dict of each node with a non-empty list to
        that list, as written, `common` holding the list of the macro;
      - `settings`: a dict of each of LIBRARY_NODES to the attributes of its library;
      - `rule_attrs`: the other keyword arguments.
    """
    if unsupported == None:
        unsupported = unsupported_platforms(hierarchy)
    resolved = resolve_platforms(hierarchy, platforms, unsupported)
    if resolved.error:
        return resolved
    targeted = resolved.targeted

    given = {attr: {hierarchy.root: common.get(attr, [])} for attr in QUALIFIED_ATTRS}
    rule_attrs = {}
    for key in sorted(kwargs):
        qualified = _split_qualified(key)
        if qualified:
            attr, node = qualified
            if node == hierarchy.root:
                return _error("%s: the %s of every platform are the %s of the macro" % (key, _ENTRIES[attr], attr))
            if node not in hierarchy.lineage:
                return _error("%s: '%s' is neither a group nor a platform; the groups are %s and the platforms %s" % (
                    key,
                    node,
                    ", ".join(sorted([group for group in hierarchy.groups if group != hierarchy.root])),
                    ", ".join(sorted(hierarchy.platforms)),
                ))
            given[attr][node] = kwargs[key]
        elif key in hierarchy.lineage:
            return _error("%s: only %s take a dict of attributes of their library" % (key, _enumeration(LIBRARY_NODES)))
        elif _ends_with_node(hierarchy, key):
            return _error("%s: only %s take a group or a platform" % (key, _enumeration(QUALIFIED_ATTRS)))
        elif key == _DERIVED_ATTR:
            return _error("%s: the macro derives it from the sources" % key)
        else:
            rule_attrs[key] = kwargs[key]

    for node in LIBRARY_NODES:
        if settings.get(node) != None:
            error = _settings_error(hierarchy, unsupported, targeted, node, settings[node])
            if error:
                return _error(error)

    # The lists of a library built for a single platform are passed to it as they are, so they may
    # be a select(); the macro concatenates the others into a select() of each konan target.
    selectable = [node for node in LIBRARY_NODES if node in hierarchy.platforms]
    lists = {attr: {} for attr in QUALIFIED_ATTRS}
    for attr in QUALIFIED_ATTRS:
        # The labels of the plain lists, normalized, to find those a list repeats from one above it.
        listed = {}
        for node in hierarchy.nodes:
            value = given[attr].get(node)
            if value == None:
                continue
            error = _list_error(hierarchy, unsupported, targeted, attr, node, value, selectable)
            if error:
                return _error(error)
            if type(value) == "list" and not value:
                continue
            lists[attr][node] = value
            if type(value) != "list":
                # The labels of a select() cannot be read before it is resolved.
                continue
            subject, verb = _subject(hierarchy, attr, node)
            labels = {}
            for label in value:
                normalized = normalize(label)
                if normalized in labels:
                    return _error("%s %s %s twice" % (subject, verb, labels[normalized]))
                labels[normalized] = label
            for normalized, label in labels.items():
                for above in hierarchy.lineage[node][:-1]:
                    if normalized in listed.get(above, {}):
                        above_subject, above_verb = _subject(hierarchy, attr, above)
                        return _error("%s %s %s, which %s already %s" % (subject, verb, label, above_subject, above_verb))
            listed[node] = labels

    return struct(
        error = None,
        hierarchy = hierarchy,
        platforms = resolved.platforms,
        targeted = targeted,
        lists = lists,
        settings = {node: dict(settings.get(node) or {}) for node in LIBRARY_NODES},
        rule_attrs = rule_attrs,
    )

def platform_list(declaration, attr, platform):
    """The list of an attribute that the library of a platform receives: the lists of its lineage, from `common` down.

    Args:
      declaration: a struct returned by `parse_declaration`, without error.
      attr: one of QUALIFIED_ATTRS.
      platform: a platform the declaration lists.

    Returns:
      The lists concatenated, the missing ones skipped: `deps + deps_native + deps_apple + deps_ios
      + deps_ios_arm64` for the deps of `ios_arm64`. The list of `jvm` or `android` may be a
      select(), which comes last; the result is then a select().
    """
    merged = []
    for node in declaration.hierarchy.lineage[platform]:
        merged = merged + declaration.lists[attr].get(node, [])
    return merged
