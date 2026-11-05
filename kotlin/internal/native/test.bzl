"""kt_native_test: links and runs Kotlin/Native tests.

The srcs compile into a private klib, and the link generates a test runner for its tests (see
link.bzl). The runner exits with 1 when a test fails. It takes its own options, e.g.
`--ktest_filter=<pattern>`, through `args` or `bazel test --test_arg=...`.

The test runs where it is linked, on the exec host, so it must be for the konan target of the exec
host: the build's platform is the host's, as by default.
"""

load(":link.bzl", "LINK_ATTRS", "link_native")
load(":providers.bzl", "KtKlibInfo")
load(":toolchains.bzl", "KT_NATIVE_TOOLCHAIN_TYPE")

def _kt_native_test_impl(ctx):
    tc = ctx.toolchains[KT_NATIVE_TOOLCHAIN_TYPE]
    if tc.konan_target != tc.konan_host:
        fail(("%s: a kt_native_test for %s does not run on the exec host, which runs %s binaries; " +
              "build it for %s, or set target_compatible_with to skip it") %
             (ctx.label, tc.konan_target, tc.konan_host, tc.konan_host))
    if not ctx.files.srcs:
        fail("%s: kt_native_test has no srcs; its test runner only runs the tests of its srcs" % ctx.label)

    binary = ctx.actions.declare_file(ctx.label.name + ".kexe")
    link_native(
        ctx,
        rule_kind = "kt_native_test",
        produce = "program",
        output = binary,
        extra_deps = ctx.attr.associates,
        friends = [associate[KtKlibInfo].klib for associate in ctx.attr.associates],
        extra_args = ["-generate-test-runner"],
        progress_message = "Linking Kotlin/Native test %{label} (" + tc.konan_target + ")",
    )
    return [DefaultInfo(executable = binary, files = depset([binary]))]

kt_native_test = rule(
    doc = """Links the tests of the srcs into a Kotlin/Native test runner, `<name>.kexe`, which `bazel test` runs.

    Experimental. The tests use kotlin.test, e.g. `@kotlin.test.Test`. The test is for the konan target of the
    exec host, whose link dependencies must be staged: see kotlin_native.targets(...).""",
    implementation = _kt_native_test_impl,
    attrs = dict(LINK_ATTRS, **{
        "associates": attr.label_list(
            doc = """kt_native_library targets whose internal declarations the srcs see. They are deps of the test
            too.""",
            providers = [KtKlibInfo],
        ),
        "srcs": attr.label_list(
            doc = "Kotlin sources with the tests.",
            allow_files = [".kt"],
        ),
    }),
    test = True,
    toolchains = [KT_NATIVE_TOOLCHAIN_TYPE],
)
