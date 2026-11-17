"""The language and API version a Kotlin toolchain defaults to on a compiler release."""

def _level(release):
    """The (major, minor) language level of a Kotlin release, or None if it is not one."""
    parts = release.split("-")[0].split(".")
    if len(parts) < 2 or not parts[0].isdigit() or not parts[1].isdigit():
        return None
    return (int(parts[0]), int(parts[1]))

def toolchain_language_level(kotlinc_version, pinned_version):
    """The default language and API version of a toolchain on a compiler release.

    A kotlinc_version override may select an older compiler than the pinned release, which
    treats the default version of the toolchain rule as experimental: the toolchain then compiles
    at the major and minor version of that compiler.

    Args:
        kotlinc_version: the configured compiler release, such as "2.4.21".
        pinned_version: the compiler release rules_kotlin pins.

    Returns:
        The "major.minor" of `kotlinc_version`, or None, the default of the toolchain rule, for a
        compiler newer than the pinned release or older than Kotlin 2.0.
    """
    compiler = _level(kotlinc_version)
    pinned = _level(pinned_version)
    if compiler == None or pinned == None or compiler < (2, 0) or compiler > pinned:
        return None
    return "%d.%d" % compiler
