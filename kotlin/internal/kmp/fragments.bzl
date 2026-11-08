"""The K2 fragments of a Kotlin Multiplatform compilation.

A rule with `source_sets` (see source_set.bzl) compiles them as the Kotlin Gradle plugin compiles a
platform: each source set of its `source_sets`, and each source set they refine, transitively, is a
fragment, and the rule's own `srcs` are the leaf fragment, named after the module of the rule, which
refines the source sets of its `source_sets`. konanc and kotlinc take the fragments with:

    -Xmulti-platform
    -Xexpect-actual-classes
    -Xfragments=<f1>,<f2>,...,<leaf>          the fragments, each after the fragments it refines
    -Xfragment-sources=<fragment>:<path>      one per source
    -Xfragment-refines=<fragment>:<refined>   one per refinement

Every Kotlin source of the compilation must belong to a fragment; Java sources need none. The paths
of -Xfragment-sources are those the compiler gets for the sources, relative to the execroot, and
come from Files, so the arguments support path mapping. The deps of every fragment are visible to
all of them, as in the unified compilation of the Kotlin Gradle plugin.

The deps of the source sets are deps of the rule, but reachable from it only through `source_sets`
and `depends_on`, attributes the aspects of other rule sets do not follow: they follow Bazel's
conventional dependency attributes, `deps`, `exports` and `runtime_deps`. The dexing aspect of the
android_binary of rules_android is one: it dexes the jars of the targets it reaches and fails on a
jar of the runtime classpath it did not reach ("Dependencies on .jar artifacts are not allowed in
Android binaries"). So a JVM or Android rule may list a source set of its compilation in
`runtime_deps` as well (see without_source_sets): the aspects reach the source set and follow its
`deps`, while the rule compiles it as before. For the aspects that forward nothing from a target
without JavaInfo, as the mobile-install of rules_android, a source set provides a JavaInfo of no
classes of its own that exports its deps (see source_set.bzl); `deps` and `exports`, which take
libraries, accept it then, and the rules reject it there (see no_source_sets).
"""

load(":source_set.bzl", "KtSourceSetInfo")

# Starlark has no while loop: the bound of the depth-first walk of the source sets, far more steps
# than a walk takes.
_MAX_WALK_STEPS = 1000000

def _walk(source_sets):
    """The source sets of `source_sets` and those they refine, transitively, each after those it refines.

    Args:
      source_sets: KtSourceSetInfo, or structs with their `label` and `depends_on` fields.

    Returns:
      A struct of `order`, the source sets, each once, and `error`, the message of a cycle, or None.
    """
    order = []
    done = {}
    for root in source_sets:
        if root.label in done:
            continue

        # The source sets from the root to the one being visited, and the position of the next source
        # set each of them refines.
        path = [root]
        positions = [0]
        for _ in range(_MAX_WALK_STEPS):
            if not path:
                break
            source_set = path[-1]
            position = positions[-1]
            if position == len(source_set.depends_on):
                path.pop()
                positions.pop()
                done[source_set.label] = True
                order.append(source_set)
                continue
            positions[-1] = position + 1
            refined = source_set.depends_on[position]
            if refined.label in done:
                continue
            labels = [visited.label for visited in path]
            if refined.label in labels:
                cycle = labels[labels.index(refined.label):] + [refined.label]
                return struct(
                    order = [],
                    error = "depends_on of Kotlin source sets must not be cyclic: " +
                            " -> ".join([str(label) for label in cycle]),
                )
            path.append(refined)
            positions.append(0)
        if path:
            fail("%s: too many source sets to walk" % root.label)
    return struct(order = order, error = None)

def _deps(order):
    """The deps of the source sets of `order`, each once, with the source set listing it first."""
    deps = []
    owners = []
    seen = {}
    for source_set in order:
        for dep in source_set.deps:
            key = str(dep.label)
            if key in seen:
                continue
            seen[key] = True
            deps.append(dep)
            owners.append(source_set.label)
    return struct(deps = deps, owners = owners)

def _path(src):
    return getattr(src, "path", src)

def _error(message):
    return struct(error = message)

def plan_fragments(source_sets, leaf_name, leaf_label, leaf_srcs):
    """The fragments of the compilation of `leaf_srcs` with `source_sets`.

    The part of collect_fragments that needs no rule context, so that unit tests run it on structs.

    Args:
      source_sets: the KtSourceSetInfo of the source_sets of the rule, or structs with their fields.
      leaf_name: the name of the leaf fragment: the module name of the rule.
      leaf_label: the label of the rule.
      leaf_srcs: the Kotlin sources of the rule, those of the leaf fragment.

    Returns:
      A struct of `error`, the message of an invalid compilation, or None. Without an error, also:
      - `names`: the fragment names, each after those of the fragments it refines, the leaf last;
      - `fragments`: a struct(name, srcs) per fragment, in the order of `names`;
      - `srcs`: the sources of the fragments, in the same order;
      - `refines`: the refinements, `<fragment>:<refined fragment>`;
      - `deps`: the deps of the source sets, each once, in the order of the source sets.
    """
    walk = _walk(source_sets)
    if walk.error:
        return _error(walk.error)

    # The compiler crashes on a fragment name that two fragments share.
    owners = {}
    for source_set in walk.order:
        if source_set.name in owners:
            return _error("fragment names must be unique in a compilation, but '%s' is both %s and %s" %
                          (source_set.name, owners[source_set.name], source_set.label))
        owners[source_set.name] = source_set.label
    for separator in [",", ":"]:
        if separator in leaf_name:
            return _error("the module name '%s' names the leaf fragment of the compilation, so it must not contain '%s'" %
                          (leaf_name, separator))
    if leaf_name in owners:
        return _error("fragment names must be unique in a compilation, but '%s' is both %s and %s" %
                      (leaf_name, owners[leaf_name], leaf_label))

    # A source belongs to one fragment.
    fragments = []
    srcs = []
    fragment_of = {}
    for name, fragment_srcs in [(source_set.name, source_set.srcs) for source_set in walk.order] + [(leaf_name, leaf_srcs)]:
        own = []
        for src in fragment_srcs:
            if src in fragment_of:
                if fragment_of[src] == name:
                    continue
                return _error("the source %s is in both fragment '%s' and '%s'; a source belongs to one source set" %
                              (_path(src), fragment_of[src], name))
            fragment_of[src] = name
            own.append(src)
        fragments.append(struct(name = name, srcs = own))
        srcs.extend(own)

    refines = [
        "%s:%s" % (source_set.name, refined.name)
        for source_set in walk.order
        for refined in source_set.depends_on
    ] + ["%s:%s" % (leaf_name, source_set.name) for source_set in source_sets]

    return struct(
        error = None,
        names = [fragment.name for fragment in fragments],
        fragments = fragments,
        srcs = srcs,
        refines = refines,
        deps = _deps(walk.order).deps,
    )

def _add_fragment_args(args, plan, flag_prefix):
    if flag_prefix:
        args.add(flag_prefix)
    args.add("-Xmulti-platform")
    args.add("-Xexpect-actual-classes")
    args.add_joined(plan.names, join_with = ",", format_joined = "-Xfragments=%s")
    for fragment in plan.fragments:
        # The name is part of the format string, where % is special.
        args.add_all(fragment.srcs, format_each = "-Xfragment-sources=%s:%%s" % fragment.name.replace("%", "%%"))
    args.add_all(plan.refines, format_each = "-Xfragment-refines=%s")

def _add_no_args(
        args,  # @unused
        flag_prefix = ""):  # @unused
    pass

def collect_fragments(ctx, source_sets, leaf_name, leaf_srcs):
    """The K2 fragments a rule compiles: its source sets and those they refine, and its own srcs as the leaf.

    Fails on a cycle of depends_on, on a fragment name two fragments share and on a source in two
    fragments.

    Args:
      ctx: the context of the rule.
      source_sets: the targets of the source_sets attribute of the rule, providing KtSourceSetInfo.
      leaf_name: the name of the leaf fragment, the module name of the rule.
      leaf_srcs: the Kotlin sources of the rule, which the leaf fragment compiles.

    Returns:
      A struct of:
      - `enabled`: whether the rule compiles fragments; without source sets it does not, and its
        compilation is the same as without this function;
      - `names`: the fragment names, each after those of the fragments it refines, the leaf last;
      - `srcs`: the Kotlin sources of every fragment, those of the leaf last: the Kotlin sources the
        rule compiles, `leaf_srcs` without source sets;
      - `deps`: the deps of the source sets, each once (see fragment_deps for checked ones);
      - `add_args`: `add_args(args, flag_prefix = "")` adds the fragment flags to the Args `args`,
        preceded by `flag_prefix` when it is not empty, e.g. by the KotlinBuilder flag whose values
        they are. It adds nothing without source sets.
    """
    if not source_sets:
        return struct(enabled = False, names = [], srcs = leaf_srcs, deps = [], add_args = _add_no_args)

    plan = plan_fragments([source_set[KtSourceSetInfo] for source_set in source_sets], leaf_name, ctx.label, leaf_srcs)
    if plan.error:
        fail("%s: %s" % (ctx.label, plan.error))

    def _add_args(args, flag_prefix = ""):
        _add_fragment_args(args, plan, flag_prefix)

    return struct(
        enabled = True,
        names = plan.names,
        srcs = plan.srcs,
        deps = plan.deps,
        add_args = _add_args,
    )

def without_source_sets(label, runtime_deps, source_sets):
    """The runtime_deps of a JVM or Android rule without the source sets listed there for the aspects of its consumers.

    A source set adds nothing to the runtime classpath: its deps are deps of the rule through
    `source_sets` (see the module docstring).

    Args:
      label: the label of the rule, for the error message.
      runtime_deps: the targets of the runtime_deps attribute of the rule.
      source_sets: the targets of the source_sets attribute of the rule, providing KtSourceSetInfo.

    Returns:
      The targets of `runtime_deps` that are not source sets, in their order. Fails on a source set the
      rule does not compile: one that is neither in `source_sets` nor refined by one of them.
    """
    listed = [dep for dep in runtime_deps if KtSourceSetInfo in dep]
    if not listed:
        return runtime_deps
    compiled = {}
    for source_set in source_sets:
        for info in source_set[KtSourceSetInfo].transitive_source_sets.to_list():
            compiled[info.label] = True
    for source_set in listed:
        if source_set[KtSourceSetInfo].label not in compiled:
            fail(("%s: the source set %s in runtime_deps is none the target compiles: list it in source_sets, or list " +
                  "there a source set refining it (a source set in runtime_deps only makes its deps reachable to the " +
                  "aspects of the consumers of the target, which follow deps, exports and runtime_deps, not source_sets)") %
                 (label, source_set[KtSourceSetInfo].label))
    return [dep for dep in runtime_deps if KtSourceSetInfo not in dep]

def no_source_sets(label, attr, targets):
    """Fails on a source set listed in a dependency attribute that takes libraries, as `deps` or `exports`.

    Its JavaInfo (see source_set.bzl) makes those attributes accept it, where it would export its deps
    and compile none of its sources.

    Args:
      label: the label of the rule, for the error message.
      attr: the name of the attribute, for the error message.
      targets: the targets of the attribute.
    """
    for target in targets:
        if KtSourceSetInfo in target:
            fail(("%s: %s lists the source set %s, which is compiled, not depended on: list it in source_sets (its deps " +
                  "are then deps of the target), and in runtime_deps for the aspects of the consumers of the target") %
                 (label, attr, target.label))

def fragment_deps(label, source_sets, provider, provider_name, consumer):
    """The deps of the source sets of a rule, which it compiles against, each providing `provider`.

    Args:
      label: the label of the rule, for the error messages.
      source_sets: the targets of the source_sets attribute of the rule, providing KtSourceSetInfo.
      provider: the provider the rule needs of every dep, e.g. JavaInfo.
      provider_name: the name of `provider`, for the error messages.
      consumer: what the rule needs, for the error messages, e.g. "a JVM consumer needs JVM deps".

    Returns:
      The deps of the source sets and of those they refine, transitively, each once, in the order of
      the source sets.
    """
    if not source_sets:
        return []
    walk = _walk([source_set[KtSourceSetInfo] for source_set in source_sets])
    if walk.error:
        fail("%s: %s" % (label, walk.error))
    deps = _deps(walk.order)
    for dep, owner in zip(deps.deps, deps.owners):
        if KtSourceSetInfo in dep:
            fail("%s: dep %s of source set %s is a source set, which refines another through depends_on, not deps" %
                 (label, dep.label, owner))
        if provider not in dep:
            fail(("%s: dep %s of source set %s provides no %s; %s (use an alias selecting the klib on " +
                  "@rules_kotlin//kotlin/native/platforms:native_<konan target> and the JVM library by default)") %
                 (label, dep.label, owner, provider_name, consumer))
    return deps.deps
