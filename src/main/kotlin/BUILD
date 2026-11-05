load("//src/main/starlark/release:packager.bzl", "release_archive")
load("//third_party:jarjar.bzl", "jar_jar")

exports_files(
    ["shade.jarjar"],
    visibility = ["//src:__subpackages__"],
)

jar_jar(
    name = "jdeps-gen",
    input_jar = "//src/main/kotlin/io/bazel/kotlin/plugin/jdeps:jdeps-gen_deploy.jar",
    rules = "shade.jarjar",
    visibility = ["//visibility:public"],
)

# The embeddable-dialect variants of the builder's compiler plugins the Build Tools API runtime uses.
# (see the btapi_*/internal_* toolchain attributes)
jar_jar(
    name = "jdeps-gen-embeddable",
    input_jar = "//src/main/kotlin/io/bazel/kotlin/plugin/jdeps:jdeps-gen_deploy.jar",
    rules = "shade.embeddable.jarjar",
    visibility = ["//visibility:public"],
)

alias(
    name = "build",
    actual = "//src/main/kotlin/io/bazel/kotlin/builder/cmd:build",
    visibility = ["//visibility:public"],
)

alias(
    name = "jdeps_merger",
    actual = "//src/main/kotlin/io/bazel/kotlin/builder/cmd:merge_jdeps",
    visibility = ["//visibility:public"],
)

alias(
    name = "ksp2",
    actual = "//src/main/kotlin/io/bazel/kotlin/builder/cmd:ksp2",
    visibility = ["//visibility:public"],
)

alias(
    name = "ksp2_invoker",
    actual = "//src/main/kotlin/io/bazel/kotlin/ksp2",
    visibility = ["//visibility:public"],
)

# The launcher of the Kotlin/Native actions (the launcher of kotlin/internal/native toolchains).
alias(
    name = "konan_launcher",
    actual = "//src/main/kotlin/io/bazel/kotlin/native:konan_launcher",
    visibility = ["//visibility:public"],
)

release_archive(
    name = "pkg",
    srcs = [
        ":jdeps-gen.jar",
        ":jdeps-gen-embeddable.jar",
    ],
    package_dir = "src/main/kotlin",  # explicitly set the package directory, as there are no parent release_archives.
    src_map = {
        "//src/main/kotlin/io/bazel/kotlin/builder/cmd:build_deploy.jar": "kotlin_worker.jar",
        "//src/main/kotlin/io/bazel/kotlin/builder/cmd:ksp2_deploy.jar": "ksp2_worker.jar",
        "//src/main/kotlin/io/bazel/kotlin/builder/cmd:merge_jdeps_deploy.jar": "jdeps_merger_worker.jar",
        "//src/main/kotlin/io/bazel/kotlin/ksp2:ksp2.jar": "ksp2_invoker.jar",
        "//src/main/kotlin/io/bazel/kotlin/native:konan_launcher_deploy.jar": "konan_launcher_lib.jar",
        "BUILD.release.bazel": "BUILD.bazel",
    },
    deps = [
        "//src/main/kotlin/io/bazel/kotlin/compiler:pkg",
    ],
)
