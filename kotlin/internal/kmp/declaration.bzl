"""The declaration of a kt_multiplatform_library or a kt_multiplatform_test: its platforms, its aliases, and the lists of each qualifier.

The macro takes the lists of a node of the hierarchy (see hierarchy.bzl) or of an alias (see
qualifiers.bzl) as `<attr>_<qualifier>`, e.g. `srcs_ios`, `deps_ios_arm64` or `deps_non_android`,
and each platform receives, per attribute, the lists of the qualifiers that cover it, from `common`
down to itself. A source is in one list, as it is in one fragment (see derive.bzl): the sources of
platforms that no group gathers are those of an alias. `parse_declaration` checks a call when the
macro is called, before any select() is resolved, and names what to change. The test macro
declares a test per platform where the library macro declares a library, and takes no `exports`.
"""

load("//kotlin/internal/native:targets.bzl", "KONAN_TARGETS")
load(":hierarchy.bzl", "HIERARCHY", "resolve_platforms")
load(":qualifiers.bzl", "resolve_qualifiers")

# The list attributes of the libraries that a group, a platform or an alias qualifies.
QUALIFIED_ATTRS = ["srcs", "deps", "exports", "plugins"]

# Those of the tests, which export nothing.
TEST_QUALIFIED_ATTRS = ["srcs", "deps", "plugins"]

# The nodes of the hierarchy that have a library or a test, which builds the platforms at or below
# the node.
LIBRARY_NODES = ["jvm", "android", "native"]

# How the messages call the library or the test of each of LIBRARY_NODES.
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

# The attribute of the libraries and the tests that the macro derives, besides the qualified ones.
_DERIVED_ATTR = "kmp_fragments"

# The attributes common to every rule, and those common to every test rule, that end with
# `_<word>`: an alias named after the word, e.g. `with` or `count`, does not make them a list of
# the alias.
_COMMON_ATTRS = [
    "applicable_licenses",
    "aspect_hints",
    "compatible_with",
    "env_inherit",
    "exec_compatible_with",
    "exec_group_compatible_with",
    "exec_properties",
    "package_metadata",
    "restricted_to",
    "shard_count",
    "target_compatible_with",
]

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

def _settings_error(hierarchy, unsupported, targeted, node, attrs, qualified_attrs, kind):
    """The error of the dict of attributes of the library or the test of a node, or None."""
    library = "%s %s" % (_LIBRARY_NAMES[node], kind)
    if type(attrs) != "dict":
        return "%s must be a dict of attributes of the %s, not a %s" % (node, library, type(attrs))
    for key in sorted(attrs):
        if key in qualified_attrs:
            return "%s sets %s: pass %s to the macro" % (node, key, _qualified(key, node))
        if key in QUALIFIED_ATTRS:
            return "%s sets %s: a %s has no %s" % (node, key, kind, key)
        if key == _DERIVED_ATTR:
            return "%s sets %s, which the macro derives from the sources" % (node, key)
    if attrs and node not in targeted:
        return _untargeted_error(
            hierarchy,
            unsupported,
            node,
            node,
            "sets attributes of the %s" % library,
            node,
        )
    return None

def _split_qualified(key, qualified_attrs):
    """The attribute and the qualifier of a key `<attr>_<qualifier>`, or None for another key."""
    for attr in qualified_attrs:
        if key.startswith(attr + "_"):
            return attr, key[len(attr) + 1:]
    return None

def _suffix(key, names):
    """The longest of `names` that `key` ends with after a `_`, or None: `non_android` rather than `android`."""
    longest = None
    for name in names:
        if key.endswith("_" + name) and (longest == None or len(name) > len(longest)):
            longest = name
    return longest

def _unknown_qualifier_error(hierarchy, aliases, key, qualifier):
    groups = ", ".join(sorted([group for group in hierarchy.groups if group != hierarchy.root]))
    platforms = ", ".join(sorted(hierarchy.platforms))
    message = "%s: '%s' is neither a group, a platform nor an alias; the groups are %s" % (key, qualifier, groups)
    if aliases:
        return message + ", the platforms %s and the aliases %s" % (platforms, ", ".join(sorted(aliases)))
    return message + " and the platforms " + platforms

def _list_error(hierarchy, unsupported, covered, attr, node, value, selectable):
    """The error of the type of a list, or of entries for a qualifier that is not in `covered`, as it covers no listed platform."""
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
    if node not in covered:
        return _untargeted_error(hierarchy, unsupported, node, subject, "lists " + _ENTRIES[attr], subject)
    return None

def _shared_source_error(hierarchy, qualifiers, first, second, label):
    """The error of a source that two qualifiers list, neither refining the other, with the list of both to move it to."""
    names = sorted([first, second])
    message = "%s and %s both list %s: a source is in one fragment; " % (
        _qualified("srcs", names[0]),
        _qualified("srcs", names[1]),
        label,
    )
    both = [
        platform
        for platform in qualifiers.leaves
        if platform in qualifiers.platforms[first] or platform in qualifiers.platforms[second]
    ]

    # Of the qualifiers of exactly their platforms, groups of one lineage, the lowest one: its
    # fragment sees what the fragments of the others declare.
    same = [qualifier for qualifier in qualifiers.names if qualifiers.platforms[qualifier] == both]
    if same:
        subject, _ = _subject(hierarchy, "srcs", same[-1])
        return message + "list it in %s alone" % subject
    alias = "_".join(names)
    return message + "declare an alias of their platforms, e.g. aliases = {\"%s\": %s}, and list it in %s alone" % (
        alias,
        repr(both),
        _qualified("srcs", alias),
    )

def parse_declaration(
        platforms,
        common,
        settings,
        kwargs,
        aliases = None,
        normalize = str,
        hierarchy = HIERARCHY,
        unsupported = None,
        attrs = QUALIFIED_ATTRS,
        kind = "library"):
    """The declaration of a kt_multiplatform_library or a kt_multiplatform_test from the arguments of the macro, or its error.

    Args:
      platforms: the `platforms` of the macro.
      common: the lists of the macro for each of `attrs`, e.g. its `srcs`, by attribute: the lists
        of `common`; a missing one is empty.
      settings: the `jvm`, `android` and `native` of the macro by name, each None or a dict.
      kwargs: the other keyword arguments of the macro: the `<attr>_<qualifier>` lists, and the
        attributes common to every rule.
      aliases: the `aliases` of the macro: a dict of the name of each alias to the listed platforms
        it groups, or None for no alias.
      normalize: the function turning a label into a string equal for equal labels, to find the
        labels a list repeats; by default the label as written.
      hierarchy: a struct returned by `make_hierarchy`.
      unsupported: the platforms of the hierarchy that no rule builds yet, as `unsupported_platforms`
        returns them; by default those of `hierarchy`.
      attrs: the list attributes that a group, a platform or an alias qualifies: QUALIFIED_ATTRS
        for the libraries, TEST_QUALIFIED_ATTRS for the tests.
      kind: how the messages call what the macro declares for each of LIBRARY_NODES: `library` or
        `test`.

    Returns:
      `struct(error = message)` for the first error: of the platforms, of the aliases, of the
      keyword arguments taken in sorted order, of the settings, and then of the lists, each
      qualifier taken after those it refines. Otherwise a struct of:
      - `error`: None;
      - `hierarchy`: the hierarchy;
      - `platforms`: the listed platforms, in tree order;
      - `targeted`: a dict of each node at or above a listed platform to the listed platforms at or
        below it, in tree order;
      - `qualifiers`: the targeted nodes, the aliases and their order, as `resolve_qualifiers`
        returns them;
      - `lists`: a dict of each of `attrs` to a dict of each qualifier with a non-empty list to
        that list, as written, `common` holding the list of the macro: the nodes in tree order,
        then the aliases by name;
      - `settings`: a dict of each of LIBRARY_NODES to the attributes of its library or test;
      - `rule_attrs`: the other keyword arguments;
      - `normalize`: the function given.
    """
    if unsupported == None:
        unsupported = unsupported_platforms(hierarchy)
    resolved = resolve_platforms(hierarchy, platforms, unsupported)
    if resolved.error:
        return resolved
    targeted = resolved.targeted
    qualifiers = resolve_qualifiers(hierarchy, targeted, aliases)
    if qualifiers.error:
        return qualifiers

    given = {attr: {hierarchy.root: common.get(attr, [])} for attr in attrs}
    rule_attrs = {}
    for key in sorted(kwargs):
        qualified = _split_qualified(key, attrs)
        if qualified:
            attr, qualifier = qualified
            if qualifier == hierarchy.root:
                return _error("%s: the %s of every platform are the %s of the macro" % (key, _ENTRIES[attr], attr))
            if qualifier not in hierarchy.lineage and qualifier not in qualifiers.aliases:
                return _error(_unknown_qualifier_error(hierarchy, qualifiers.aliases, key, qualifier))
            given[attr][qualifier] = kwargs[key]
            continue
        for attr in QUALIFIED_ATTRS:
            if attr not in attrs and (key == attr or key.startswith(attr + "_")):
                return _error("%s: a %s has no %s; its lists are %s" % (key, kind, attr, _enumeration(attrs)))
        if key in hierarchy.lineage or key in qualifiers.aliases:
            return _error("%s: only %s take a dict of attributes of their %s" % (key, _enumeration(LIBRARY_NODES), kind))
        suffix = _suffix(key, hierarchy.nodes + list(qualifiers.aliases))
        if suffix in hierarchy.lineage:
            return _error("%s: only %s take a group or a platform" % (key, _enumeration(attrs)))
        if suffix != None and key not in _COMMON_ATTRS:
            return _error("%s: only %s take an alias" % (key, _enumeration(attrs)))
        if key == _DERIVED_ATTR:
            return _error("%s: the macro derives it from the sources" % key)
        rule_attrs[key] = kwargs[key]

    for node in LIBRARY_NODES:
        if settings.get(node) != None:
            error = _settings_error(hierarchy, unsupported, targeted, node, settings[node], attrs, kind)
            if error:
                return _error(error)

    # The lists of a library or a test built for a single platform are passed to it as they are, so
    # they may be a select(); the macro concatenates the others into a select() of each konan target.
    selectable = [node for node in LIBRARY_NODES if node in hierarchy.platforms]

    # A list is checked after those of the qualifiers it refines; a node that is not targeted
    # refines none of them.
    ordered = qualifiers.names + [node for node in hierarchy.nodes if node not in targeted]
    found = {attr: {} for attr in attrs}
    for attr in attrs:
        # The labels of the plain lists, normalized, to find those a list repeats from one above it.
        listed = {}
        for qualifier in ordered:
            value = given[attr].get(qualifier)
            if value == None:
                continue
            error = _list_error(hierarchy, unsupported, qualifiers.platforms, attr, qualifier, value, selectable)
            if error:
                return _error(error)
            if type(value) == "list" and not value:
                continue
            found[attr][qualifier] = value
            if type(value) != "list":
                # The labels of a select() cannot be read before it is resolved.
                continue
            subject, verb = _subject(hierarchy, attr, qualifier)
            labels = {}
            for label in value:
                normalized = normalize(label)
                if normalized in labels:
                    return _error("%s %s %s twice" % (subject, verb, labels[normalized]))
                labels[normalized] = label
            for normalized, label in labels.items():
                for above in qualifiers.above.get(qualifier, []):
                    if normalized in listed.get(above, {}):
                        above_subject, above_verb = _subject(hierarchy, attr, above)
                        return _error("%s %s %s, which %s already %s" % (subject, verb, label, above_subject, above_verb))
                if attr != "srcs":
                    continue

                # The lists checked before that are left refine `qualifier` no more than it refines
                # them: the source would be in two fragments, neither seeing the other.
                for other, other_labels in listed.items():
                    if normalized in other_labels:
                        return _error(_shared_source_error(hierarchy, qualifiers, other, qualifier, label))
            listed[qualifier] = labels

    in_tree_order = hierarchy.nodes + sorted(qualifiers.aliases)
    return struct(
        error = None,
        hierarchy = hierarchy,
        platforms = resolved.platforms,
        targeted = targeted,
        qualifiers = qualifiers,
        lists = {
            attr: {qualifier: found[attr][qualifier] for qualifier in in_tree_order if qualifier in found[attr]}
            for attr in attrs
        },
        settings = {node: dict(settings.get(node) or {}) for node in LIBRARY_NODES},
        rule_attrs = rule_attrs,
        normalize = normalize,
    )

def sourceless_error(declaration, platform):
    """The error of a listed platform that compiles no source, for a macro whose platforms each need some.

    Args:
      declaration: a struct returned by `parse_declaration`, without error.
      platform: a platform the declaration lists, none of whose qualifiers lists sources.

    Returns:
      The message, which names the lists of the qualifiers covering the platform, from `common`
      down to itself: `srcs_native`, `srcs_linux` and `srcs_linux_x64` below the srcs of the macro
      for `linux_x64`.
    """
    lists = [
        _subject(declaration.hierarchy, "srcs", qualifier)[0]
        for qualifier in declaration.qualifiers.of_platform[platform]
    ]
    return "%s has no sources: list some in %s, or remove %s from platforms" % (platform, _alternatives(lists), platform)

def platform_list(declaration, attr, platform):
    """The list of an attribute that the library or the test of a platform receives: the lists of the qualifiers covering it, from `common` down.

    Args:
      declaration: a struct returned by `parse_declaration`, without error.
      attr: one of the qualified attributes of the declaration.
      platform: a platform the declaration lists.

    Returns:
      The lists concatenated, the missing ones skipped: `deps + deps_native + deps_apple + deps_ios
      + deps_ios_arm64` for the deps of `ios_arm64`, and `deps + deps_non_android + deps_jvm` for
      those of `jvm` below an alias `non_android`. A label that two qualifiers list, neither
      refining the other, is kept once, where it comes first. The list of `jvm` or `android` may
      be a select(), which comes last; the result is then a select().
    """
    merged = []
    kept = {}
    for qualifier in declaration.qualifiers.of_platform[platform]:
        value = declaration.lists[attr].get(qualifier, [])
        if type(value) == "list":
            # Two qualifiers that share the platform without one covering the other, e.g. an alias
            # and a group, may both list a label, which a library takes once.
            fresh = []
            for label in value:
                normalized = declaration.normalize(label)
                if normalized not in kept:
                    kept[normalized] = True
                    fresh.append(label)
            value = fresh
        merged = merged + value
    return merged
