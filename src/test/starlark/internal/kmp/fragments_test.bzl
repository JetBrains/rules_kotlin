"""Unit tests for plan_fragments, the pure part of collect_fragments, on structs standing in for source sets."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load("//kotlin/internal/kmp:fragments.bzl", "plan_fragments")

def _source_set(name, srcs = [], deps = [], depends_on = [], package = "shared"):
    """A struct with the fields of KtSourceSetInfo that plan_fragments reads."""
    return struct(
        depends_on = depends_on,
        deps = [struct(label = dep) for dep in deps],
        label = "//%s:%s" % (package, name),
        name = "%s-%s" % (package, name),
        srcs = srcs,
    )

def _labels(deps):
    return [dep.label for dep in deps]

def _chain_test(ctx):
    """A source set comes after the source sets it refines, transitively, and the leaf last."""
    env = unittest.begin(ctx)

    common = _source_set("common", srcs = ["shared/Platform.kt", "shared/Greeting.kt"])
    apple = _source_set("apple", srcs = ["shared/Platform.apple.kt"], depends_on = [common])
    ios = _source_set("ios", depends_on = [apple])
    plan = plan_fragments([ios], "shared-ios_lib", "//shared:ios_lib", ["shared/Ios.kt"])

    asserts.equals(env, None, plan.error)
    asserts.equals(env, ["shared-common", "shared-apple", "shared-ios", "shared-ios_lib"], plan.names)
    asserts.equals(
        env,
        [
            ("shared-common", ["shared/Platform.kt", "shared/Greeting.kt"]),
            ("shared-apple", ["shared/Platform.apple.kt"]),
            ("shared-ios", []),
            ("shared-ios_lib", ["shared/Ios.kt"]),
        ],
        [(fragment.name, fragment.srcs) for fragment in plan.fragments],
    )
    asserts.equals(
        env,
        ["shared/Platform.kt", "shared/Greeting.kt", "shared/Platform.apple.kt", "shared/Ios.kt"],
        plan.srcs,
    )
    asserts.equals(
        env,
        ["shared-apple:shared-common", "shared-ios:shared-apple", "shared-ios_lib:shared-ios"],
        plan.refines,
    )
    asserts.equals(env, [], plan.deps)

    return unittest.end(env)

def _diamond_test(ctx):
    """A source set two others refine is one fragment, and a dep of two source sets is one dep."""
    env = unittest.begin(ctx)

    common = _source_set("common", srcs = ["shared/Platform.kt"], deps = ["//lib:a"])
    apple = _source_set("apple", srcs = ["shared/Apple.kt"], deps = ["//lib:a", "//lib:b"], depends_on = [common])
    linux = _source_set("linux", srcs = ["shared/Linux.kt"], deps = ["//lib:c"], depends_on = [common])
    plan = plan_fragments([apple, linux], "shared-native", "//shared:native", [])

    asserts.equals(env, None, plan.error)
    asserts.equals(env, ["shared-common", "shared-apple", "shared-linux", "shared-native"], plan.names)
    asserts.equals(env, ["shared/Platform.kt", "shared/Apple.kt", "shared/Linux.kt"], plan.srcs)
    asserts.equals(
        env,
        [
            "shared-apple:shared-common",
            "shared-linux:shared-common",
            "shared-native:shared-apple",
            "shared-native:shared-linux",
        ],
        plan.refines,
    )
    asserts.equals(env, ["//lib:a", "//lib:b", "//lib:c"], _labels(plan.deps))

    return unittest.end(env)

def _same_name_in_two_packages_test(ctx):
    """Source sets named alike in different packages are different fragments."""
    env = unittest.begin(ctx)

    shared = _source_set("common", srcs = ["shared/A.kt"])
    other = _source_set("common", srcs = ["other/B.kt"], package = "other")
    plan = plan_fragments([shared, other], "app-lib", "//app:lib", [])

    asserts.equals(env, None, plan.error)
    asserts.equals(env, ["shared-common", "other-common", "app-lib"], plan.names)

    return unittest.end(env)

def _repeated_source_test(ctx):
    """A source listed twice in a fragment is compiled once."""
    env = unittest.begin(ctx)

    common = _source_set("common", srcs = ["shared/A.kt", "shared/A.kt"])
    plan = plan_fragments([common], "shared-lib", "//shared:lib", ["shared/B.kt", "shared/B.kt"])

    asserts.equals(env, None, plan.error)
    asserts.equals(env, ["shared/A.kt", "shared/B.kt"], plan.srcs)
    asserts.equals(env, [["shared/A.kt"], ["shared/B.kt"]], [fragment.srcs for fragment in plan.fragments])

    return unittest.end(env)

def _cycle_test(ctx):
    """A cycle of depends_on is reported with its path."""
    env = unittest.begin(ctx)

    # Bazel rejects a cycle of targets before analysis: only structs can build one.
    refined_by_a = []
    a = _source_set("a", depends_on = refined_by_a)
    b = _source_set("b", depends_on = [a])
    refined_by_a.append(b)
    plan = plan_fragments([a], "shared-lib", "//shared:lib", [])

    asserts.equals(
        env,
        "depends_on of Kotlin source sets must not be cyclic: //shared:a -> //shared:b -> //shared:a",
        plan.error,
    )

    return unittest.end(env)

def _duplicate_name_test(ctx):
    """Two source sets of one fragment name fail the compilation, which the compiler would crash on."""
    env = unittest.begin(ctx)

    a = _source_set("a")
    b = struct(depends_on = [], deps = [], label = "//shared:b", name = "shared-a", srcs = [])
    plan = plan_fragments([a, b], "shared-lib", "//shared:lib", [])

    asserts.equals(
        env,
        "fragment names must be unique in a compilation, but 'shared-a' is both //shared:a and //shared:b",
        plan.error,
    )

    return unittest.end(env)

def _leaf_name_of_a_source_set_test(ctx):
    """The leaf fragment cannot take the name of a source set, e.g. through module_name."""
    env = unittest.begin(ctx)

    common = _source_set("common")
    plan = plan_fragments([common], "shared-common", "//shared:lib", [])

    asserts.equals(
        env,
        "fragment names must be unique in a compilation, but 'shared-common' is both //shared:common and //shared:lib",
        plan.error,
    )

    return unittest.end(env)

def _leaf_name_with_separator_test(ctx):
    """A module name with a separator of the fragment flags cannot name the leaf fragment."""
    env = unittest.begin(ctx)

    common = _source_set("common")
    asserts.equals(
        env,
        "the module name 'a,b' names the leaf fragment of the compilation, so it must not contain ','",
        plan_fragments([common], "a,b", "//shared:lib", []).error,
    )
    asserts.equals(
        env,
        "the module name 'a:b' names the leaf fragment of the compilation, so it must not contain ':'",
        plan_fragments([common], "a:b", "//shared:lib", []).error,
    )

    return unittest.end(env)

def _source_in_two_fragments_test(ctx):
    """A source belongs to one fragment."""
    env = unittest.begin(ctx)

    common = _source_set("common", srcs = ["shared/Platform.kt"])
    plan = plan_fragments([common], "shared-lib", "//shared:lib", ["shared/Platform.kt"])

    asserts.equals(
        env,
        "the source shared/Platform.kt is in both fragment 'shared-common' and 'shared-lib'; a source belongs to one source set",
        plan.error,
    )

    return unittest.end(env)

chain_test = unittest.make(_chain_test)
diamond_test = unittest.make(_diamond_test)
same_name_in_two_packages_test = unittest.make(_same_name_in_two_packages_test)
repeated_source_test = unittest.make(_repeated_source_test)
cycle_test = unittest.make(_cycle_test)
duplicate_name_test = unittest.make(_duplicate_name_test)
leaf_name_of_a_source_set_test = unittest.make(_leaf_name_of_a_source_set_test)
leaf_name_with_separator_test = unittest.make(_leaf_name_with_separator_test)
source_in_two_fragments_test = unittest.make(_source_in_two_fragments_test)

def fragments_test_suite(name):
    unittest.suite(
        name,
        chain_test,
        diamond_test,
        same_name_in_two_packages_test,
        repeated_source_test,
        cycle_test,
        duplicate_name_test,
        leaf_name_of_a_source_set_test,
        leaf_name_with_separator_test,
        source_in_two_fragments_test,
    )
