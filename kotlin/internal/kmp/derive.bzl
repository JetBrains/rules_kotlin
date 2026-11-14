"""The K2 fragments of a kt_multiplatform_library, derived from the sources each of its platforms lists.

A platform is `jvm`, `android` or a konan target, and each platform lists every source it compiles.
The sources that exactly the same platforms list form one fragment, named after them: their names,
sorted and joined with `-`, e.g. `android-jvm`. A fragment refines the fragments directly above it:
`A` refines `B` when the platforms of `A` are a strict subset of those of `B` and no fragment lies in
between. The sources of a single platform are the leaf of its compilation, named after the platform,
which refines the fragments directly above that platform and may be empty:

    jvm:          COMMON + NON_ANDROID + JVM
    android:      COMMON + ANDROID
    ios_arm64:    COMMON + NON_ANDROID + APPLE
    macos_arm64:  COMMON + NON_ANDROID + APPLE

    android-ios_arm64-jvm-macos_arm64  COMMON
    ios_arm64-jvm-macos_arm64          NON_ANDROID, refines android-ios_arm64-jvm-macos_arm64
    ios_arm64-macos_arm64              APPLE, refines ios_arm64-jvm-macos_arm64
    jvm, android                       the leaves of JVM and ANDROID; ios_arm64 and macos_arm64 are empty

The compilation of a platform gets every fragment whose platforms include it, most shared first, and
then its leaf (see fragments.bzl). Sources are told apart by label: a file that two labels name is in
two fragments, which the analysis of the compilation reports.
"""

def fragment_name(platforms):
    """The name of the fragment of some platforms: their names, sorted and joined with `-`.

    Args:
      platforms: the names of the platforms, e.g. `["jvm", "android"]`.

    Returns:
      The name, e.g. `android-jvm`.
    """
    return "-".join(sorted(platforms))

def _strict_subset(smaller, larger):
    """Whether the platforms of `smaller` are a strict subset of those of `larger`, both dicts keyed by platform."""
    if len(smaller) >= len(larger):
        return False
    for platform in smaller:
        if platform not in larger:
            return False
    return True

def _refined(platforms, fragments):
    """The names of the fragments directly above some platforms, in the order of `fragments`.

    Args:
      platforms: a dict keyed by the platforms of a fragment or of a leaf.
      fragments: structs of the `name` and the `platform_set`, a dict keyed by the platforms, of every fragment.

    Returns:
      The names of the fragments of a strict superset of the platforms with no fragment in between.
    """
    above = [fragment for fragment in fragments if _strict_subset(platforms, fragment.platform_set)]
    return [
        fragment.name
        for fragment in above
        if not [between for between in above if _strict_subset(between.platform_set, fragment.platform_set)]
    ]

def _most_shared_first(fragment):
    return (-len(fragment.platforms), fragment.name)

def derive_fragments(platform_srcs):
    """The fragments of the platforms of a kt_multiplatform_library, from the sources each platform lists.

    Args:
      platform_srcs: a dict of each platform (`jvm`, `android` or a konan target) to the labels of the
        sources it compiles, as strings that are equal for equal labels. A platform lists a label once.

    Returns:
      A struct of:
      - `fragments`: a struct(name, platforms, srcs, refines) per set of two or more platforms listing
        sources that no other platform lists, most shared first, then by name: `platforms` are sorted,
        `srcs` are the labels in the order the first of those platforms lists them, and `refines` are
        the names of the fragments directly above it, most shared first;
      - `leaf_srcs`: a dict of each platform to the labels that it alone lists, in its order;
      - `leaf_refines`: a dict of each platform to the names of the fragments directly above it, which
        its leaf refines, most shared first.
    """

    # The platforms listing each label, sorted, and the labels in the order the platforms list them.
    owners = {}
    for platform in sorted(platform_srcs):
        for label in platform_srcs[platform]:
            platforms = owners.setdefault(label, [])
            if not platforms or platforms[-1] != platform:
                platforms.append(platform)

    leaf_srcs = {platform: [] for platform in platform_srcs}
    shared = {}
    for label, platforms in owners.items():
        if len(platforms) == 1:
            leaf_srcs[platforms[0]].append(label)
        else:
            shared.setdefault(fragment_name(platforms), struct(platforms = platforms, srcs = [])).srcs.append(label)

    ordered = sorted(
        [struct(name = name, platforms = fragment.platforms, srcs = fragment.srcs) for name, fragment in shared.items()],
        key = _most_shared_first,
    )
    sets = [
        struct(name = fragment.name, platform_set = {platform: True for platform in fragment.platforms})
        for fragment in ordered
    ]
    return struct(
        fragments = [
            struct(
                name = fragment.name,
                platforms = fragment.platforms,
                srcs = fragment.srcs,
                refines = _refined(fragment_set.platform_set, sets),
            )
            for fragment, fragment_set in zip(ordered, sets)
        ],
        leaf_srcs = leaf_srcs,
        leaf_refines = {platform: _refined({platform: True}, sets) for platform in platform_srcs},
    )
