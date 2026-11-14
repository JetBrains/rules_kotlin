"""The K2 fragments of a Kotlin Multiplatform compilation.

kt_jvm_library, kt_android_library and kt_native_library compile the sources a
kt_multiplatform_library shares (see derive.bzl) as the Kotlin Gradle plugin compiles a platform:
the fragments of their `kmp_fragments` (see fragment.bzl), which their srcs refine, and the
fragments those refine, transitively, are fragments of the compilation, most shared first, and the
rule's own `srcs` are the leaf fragment, named after its platform: `jvm`, `android` or the konan
target. The leaf may be empty. konanc and kotlinc take the fragments with:

    -Xmulti-platform
    -Xexpect-actual-classes
    -Xfragments=<f1>,<f2>,...,<leaf>          the fragments, each after the fragments it refines
    -Xfragment-sources=<fragment>:<path>      one per source
    -Xfragment-refines=<fragment>:<refined>   one per refinement

Every Kotlin source of the compilation must belong to a fragment; Java sources need none. The paths
of -Xfragment-sources are those the compiler gets for the sources, relative to the execroot, and
come from Files, so the arguments support path mapping. The fragments have no deps of their own:
every fragment compiles against the deps of the rule, as in the unified compilation of the Kotlin
Gradle plugin, where the deps of every fragment are visible to all of them.
"""

load(":fragment.bzl", "KtFragmentInfo")

def _path(src):
    return getattr(src, "path", src)

def _error(message):
    return struct(error = message)

def _most_shared_first(fragment):
    return (-len(fragment.platforms), fragment.name)

def plan_fragments(fragments, leaf_name, leaf_srcs):
    """The fragments of the compilation of `leaf_srcs`, which refine `fragments`.

    The part of collect_fragments that needs no rule context, so that unit tests run it on structs.

    Args:
      fragments: the KtFragmentInfo of the kmp_fragments of the rule, the fragments its srcs refine,
        or structs with their fields.
      leaf_name: the name of the leaf fragment: the platform of the rule.
      leaf_srcs: the Kotlin sources of the rule, those of the leaf fragment.

    Returns:
      A struct of `error`, the message of an invalid compilation, or None. Without an error, also:
      - `names`: the fragment names, most shared first, then by name, and the leaf last;
      - `fragments`: a struct(name, srcs) per fragment, in the order of `names`;
      - `srcs`: the sources of the fragments, in the same order;
      - `refines`: the refinements, `<fragment>:<refined fragment>`.
    """
    reached = {}
    for fragment in fragments:
        for shared in fragment.transitive_fragments.to_list():
            known = reached.setdefault(shared.name, shared)
            if known != shared:
                return _error("fragment names must be unique in a compilation, but two fragments are named '%s'" % shared.name)
    if leaf_name in reached:
        return _error("fragment names must be unique in a compilation, but '%s' names both a shared fragment and the leaf" %
                      leaf_name)
    ordered = sorted(reached.values(), key = _most_shared_first)

    # A source belongs to one fragment. The platforms share sources by label, so a file that two
    # labels name is in two fragments.
    planned = []
    srcs = []
    fragment_of = {}
    for name, fragment_srcs in [(fragment.name, fragment.srcs) for fragment in ordered] + [(leaf_name, leaf_srcs)]:
        own = []
        for src in fragment_srcs:
            owner = fragment_of.get(src)
            if owner == name:
                continue
            if owner != None:
                return _error(("the source %s is in both fragment '%s' and '%s': the platforms of kt_multiplatform_library " +
                               "share sources by label, and they list it through different labels; list it by one label") %
                              (_path(src), owner, name))
            fragment_of[src] = name
            own.append(src)
        planned.append(struct(name = name, srcs = own))
        srcs.extend(own)

    refines = [
        "%s:%s" % (fragment.name, refined)
        for fragment in ordered
        for refined in fragment.refines
    ] + ["%s:%s" % (leaf_name, fragment.name) for fragment in fragments]

    return struct(
        error = None,
        names = [fragment.name for fragment in planned],
        fragments = planned,
        srcs = srcs,
        refines = refines,
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

def collect_fragments(ctx, fragments, leaf_name, leaf_srcs):
    """The K2 fragments a rule compiles: its kmp_fragments and those they refine, and its own srcs as the leaf.

    Fails on a fragment name two fragments share and on a source in two fragments.

    Args:
      ctx: the context of the rule.
      fragments: the targets of the kmp_fragments attribute of the rule, providing KtFragmentInfo.
      leaf_name: the name of the leaf fragment, the platform of the rule: `jvm`, `android` or the
        konan target.
      leaf_srcs: the Kotlin sources of the rule, which the leaf fragment compiles.

    Returns:
      A struct of:
      - `enabled`: whether the rule compiles fragments; without kmp_fragments it does not, and its
        compilation is the same as without this function;
      - `names`: the fragment names, most shared first, the leaf last;
      - `srcs`: the Kotlin sources of every fragment, those of the leaf last: the Kotlin sources the
        rule compiles, `leaf_srcs` without kmp_fragments;
      - `add_args`: `add_args(args, flag_prefix = "")` adds the fragment flags to the Args `args`,
        preceded by `flag_prefix` when it is not empty, e.g. by the KotlinBuilder flag whose values
        they are. It adds nothing without kmp_fragments.
    """
    if not fragments:
        return struct(enabled = False, names = [], srcs = leaf_srcs, add_args = _add_no_args)

    plan = plan_fragments([fragment[KtFragmentInfo] for fragment in fragments], leaf_name, leaf_srcs)
    if plan.error:
        fail("%s: %s" % (ctx.label, plan.error))

    def _add_args(args, flag_prefix = ""):
        _add_fragment_args(args, plan, flag_prefix)

    return struct(
        enabled = True,
        names = plan.names,
        srcs = plan.srcs,
        add_args = _add_args,
    )
