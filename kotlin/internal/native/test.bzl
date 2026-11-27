"""kt_native_test: links and runs Kotlin/Native tests.

The srcs compile into a private klib, and the link generates a test runner for its tests (see
link.bzl). The runner exits with 1 when a test fails. It takes its own options, e.g.
`--ktest_filter=<pattern>`, through `args` or `bazel test --test_arg=...`. With kmp_fragments, the
test sources a kt_multiplatform_test shares compile with the srcs, as K2 fragments (see
//kotlin/internal/kmp:fragments.bzl).

The Kotlin test runner does not read the environment of a Bazel test. The entry point of the test
is therefore the main function of TestLauncher.kt, a source of the rules that compiles with the
srcs, as the last of them: it creates TEST_SHARD_STATUS_FILE, selects the tests of
TESTBRIDGE_TEST_ONLY (`--test_filter`) and then those of the shard (TEST_TOTAL_SHARDS and
TEST_SHARD_INDEX), and runs the Kotlin test runner on them, with its options. The link sets it
with `-e`, before the `link_opts`: a test whose `link_opts` set an entry point of their own runs
that one, and has neither shards nor the filter.

The test runs on the exec host, which runs the binaries of its own konan target: the build's
platform is the host's, as by default. A test for another konan target links like a cc_test for
another platform, so a build of every target for that platform builds it too, but it does not
run on the host.
"""

load("//kotlin/internal/kmp:fragment.bzl", "KtFragmentInfo")
load("//kotlin/internal/kmp:fragments.bzl", "collect_fragments")
load(":link.bzl", "EXECUTABLE_ATTRS", "LINK_ATTRS", "executable_runfiles", "link_native")
load(":providers.bzl", "KtKlibInfo")
load(":toolchains.bzl", "KT_NATIVE_TOOLCHAIN_TYPE")
load(":transition.bzl", "kt_native_transition")

# The main function of TestLauncher.kt, the entry point of the test runner.
_LAUNCHER_MAIN = "io.bazel.kotlin.native.test.main"

def _expand_env(ctx):
    # As expand_env of //kotlin/internal/jvm:common.bzl does for kt_jvm_test.
    return {
        key: ctx.expand_make_variables("env", ctx.expand_location(value, ctx.attr.data), {})
        for key, value in ctx.attr.env.items()
    }

def _kt_native_test_impl(ctx):
    tc = ctx.toolchains[KT_NATIVE_TOOLCHAIN_TYPE]
    launcher = ctx.file._launcher
    fragments = collect_fragments(ctx, ctx.attr.kmp_fragments, tc.konan_target, ctx.files.srcs + [launcher])
    if fragments.srcs == [launcher]:
        fail("%s: kt_native_test has no sources, in its srcs or its kmp_fragments; its test runner only runs the tests of its own sources" % ctx.label)

    binary = ctx.actions.declare_file(ctx.label.name + ".kexe")
    link_native(
        ctx,
        produce = "program",
        output = binary,
        extra_deps = ctx.attr.associates,
        friends = [associate[KtKlibInfo].compile_klib for associate in ctx.attr.associates],
        extra_args = ["-generate-test-runner", "-e", _LAUNCHER_MAIN],
        fragments = fragments,
        progress_message = "Linking Kotlin/Native test %{label} (" + tc.konan_target + ")",
    )
    return [
        DefaultInfo(executable = binary, files = depset([binary]), runfiles = executable_runfiles(ctx)),
        RunEnvironmentInfo(environment = _expand_env(ctx), inherited_environment = ctx.attr.env_inherit),
    ]

kt_native_test = rule(
    doc = """Links the tests of the srcs into a Kotlin/Native test runner, `<name>.kexe`, which `bazel test` runs.

    Experimental. The tests use kotlin.test, e.g. `@kotlin.test.Test`. The link dependencies of the target
    must be staged: see kotlin_native.targets(...). `bazel test` runs the test on the exec host, so the test
    is for the konan target of that host, as it is by default. For another konan target, e.g. with
    `--platforms`, the test runner links but does not run on the host: set `target_compatible_with` on a
    test to skip it for the platforms it does not run on.

    The test takes the attributes and the flags of a Bazel test:
    - `env` and `env_inherit` set the environment of its process;
    - `shard_count` splits its tests among the shards in turn, in the order the test runner lists them in;
      a shard without a test passes;
    - `bazel test --test_filter=<filter>` runs the tests whose `<suite>#<test>` has a match of the filter,
      a regular expression, as a `kt_jvm_test` does with `<class>#<method>`: the suite of the tests of a
      class is its qualified name, e.g. `--test_filter=GreeterTest` or `--test_filter='GreeterTest#greets$'`.
      A filter that matches no test of the target, or is no regular expression, fails the test. The shards
      split the tests the filter selects.

    The options of the Kotlin test runner, e.g. `--ktest_filter=<pattern>` in `args` or in
    `bazel test --test_arg=...`, select among those tests. A test whose `link_opts` set an entry point,
    `-e <function>`, runs it in place of the one of the rule, and has neither shards nor `--test_filter`:
    Bazel then fails it when it has a `shard_count`.""",
    implementation = _kt_native_test_impl,
    attrs = dict(LINK_ATTRS, **dict(EXECUTABLE_ATTRS, **{
        "associates": attr.label_list(
            doc = """kt_native_library targets whose internal declarations the srcs see. They are deps of the test
            too. The srcs compile against their header klibs when they write one (see the build setting
            experimental_native_header_klibs): a header klib keeps internal declarations.""",
            providers = [KtKlibInfo],
        ),
        "env": attr.string_dict(
            doc = """Environment variables to set when the test runs. The values are subject to `$(location)`
            expansion over the data, and to "Make variable" substitution.""",
        ),
        "env_inherit": attr.string_list(
            doc = "Environment variables the test inherits from the environment `bazel test` runs in.",
        ),
        "kmp_fragments": attr.label_list(
            doc = """The K2 fragments of a `kt_multiplatform_test` that the srcs refine: the test sources of the groups above
            the konan target in its hierarchy, e.g. `common`, `native` and `apple`, and those it shares with other groups
            or platforms. `kt_multiplatform_test` sets it from the sources of each group and platform; it is not set by
            hand. The Kotlin sources of the fragments, and of the fragments they refine, compile with the srcs in one
            compilation (`-Xmulti-platform`), against the deps and the associates, so the `actual` declarations of the srcs
            implement the `expect` ones of the fragments; the srcs are the leaf fragment, named after the konan target, and
            may be empty. The test runner runs the tests of the fragments too.""",
            providers = [KtFragmentInfo],
        ),
        "srcs": attr.label_list(
            doc = "Kotlin sources with the tests.",
            allow_files = [".kt"],
        ),
        "_launcher": attr.label(
            default = "//kotlin/internal/native:TestLauncher.kt",
            allow_single_file = True,
        ),
    })),
    cfg = kt_native_transition,
    test = True,
    toolchains = [KT_NATIVE_TOOLCHAIN_TYPE],
)
