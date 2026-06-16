# Copyright 2018 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
load("@bazel_skylib//lib:sets.bzl", _sets = "sets")
load(
    "@rules_java//java:defs.bzl",
    "JavaInfo",
)
load("//kotlin/internal/jvm:associates.bzl", _associate_utils = "associate_utils")

def _java_info(target):
    return target[JavaInfo] if JavaInfo in target else None

def _jvm_deps(ctx, toolchains, associate_deps, deps = [], deps_java_infos = [], exports = [], runtime_deps = []):
    """Encapsulates jvm dependency metadata."""
    associates = _associate_utils.get_associates(
        ctx,
        toolchains = toolchains,
        associates = associate_deps,
    )
    dep_infos = (
        deps_java_infos +
        [_java_info(d) for d in deps] +
        associates.dep_infos +
        [toolchains.kt.jvm_stdlibs]
    )

    prune_transitive_deps = (toolchains.kt.experimental_prune_transitive_deps and
                             not "kt_experimental_prune_transitive_deps_incompatible" in ctx.attr.tags)

    # Reduced classpath, exclude transitive deps from compilation
    if prune_transitive_deps:
        transitive = [
            d.compile_jars
            for d in dep_infos
        ]
    else:
        transitive = [
            d.compile_jars
            for d in dep_infos
        ] + [
            d.transitive_compile_time_jars
            for d in dep_infos
        ]

    # Put associate jars FIRST (as direct) so they appear first on the classpath.
    # This ensures that when the same class exists in both an associate jar and a regular dep,
    # the associate's version is found first. This is critical for internal visibility to work
    # correctly when there are split packages across modules.
    compile_depset_list = depset(direct = associates.jars.to_list(), transitive = transitive).to_list()
    compile_depset_list_filtered = [jar for jar in compile_depset_list if not _sets.contains(associates.abi_jar_set, jar)]

    # When experimental_prune_transitive_deps is enabled, the project asserts a
    # completeness invariant: every type javac may need to resolve -- including
    # types referenced in class-file signatures of direct deps -- is itself declared as a direct dep on the consuming target.
    # Under that invariant, pruning the Java compile classpath to direct ABI jars is sound:
    # javac never reaches for types in transitive deps because they are already present as direct entries.
    #
    # We expose one synthetic JavaInfo per direct ABI jar so that
    # java_common.compile() sees a transitive_compile_time_jars equal to the
    # pruned direct set (deps=[] prevents the depset from compounding).
    if prune_transitive_deps:
        # neverlink: these synthetic deps exist only to narrow javac's *compile* classpath to the pruned direct ABI set
        pruned_deps_for_java = [
            JavaInfo(output_jar = jar, compile_jar = jar, deps = [], neverlink = True)
            for jar in compile_depset_list_filtered
        ]
    else:
        pruned_deps_for_java = None

    return struct(
        module_name = associates.module_name,
        deps = dep_infos,
        pruned_deps_for_java = pruned_deps_for_java,
        exports = [_java_info(d) for d in exports],
        associate_jars = associates.jars,
        compile_jars = depset(direct = compile_depset_list_filtered),
        runtime_deps = [_java_info(d) for d in runtime_deps],
    )

jvm_deps_utils = struct(
    jvm_deps = _jvm_deps,
)
