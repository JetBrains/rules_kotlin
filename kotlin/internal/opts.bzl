# Copyright 2020 The Bazel Authors. All rights reserved.
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

load(
    "//src/main/starlark/core/options:opts.javac.bzl",
    _JavacOptions = "JavacOptions",
    _javac_options_to_flags = "javac_options_to_flags",
    _kt_javac_options = "kt_javac_options",
)
load(
    "//src/main/starlark/core/options:opts.kotlinc.bzl",
    _KotlincOptions = "KotlincOptions",
    _kotlinc_options_to_flags = "kotlinc_options_to_flags",
    _kt_kotlinc_options = "kt_kotlinc_options",
)

JavacOptions = _JavacOptions
javac_options_to_flags = _javac_options_to_flags
kt_javac_options = _kt_javac_options

KotlincOptions = _KotlincOptions
kotlinc_options_to_flags = _kotlinc_options_to_flags
kt_kotlinc_options = _kt_kotlinc_options

# Carries Kotlin compiler options that are NOT part of the auto-generated
# KotlincOptions provider (which is built from JetBrains'
# `kotlin-compiler-arguments-description` artifact and only includes options
# already covered by JetBrains' own kotlinc CLI). Consumers populate it in
# their kt_kotlinc_options-like wrapper; the BTA compile path reads it on
# the kotlinc_opts target if present and overrides the toolchain defaults
# emitted by _init_builder_args.
KotlincExtraOptions = provider(
    doc = "Extra Kotlin compiler options not covered by the standard KotlincOptions provider.",
    fields = {
        "api_version": "Kotlin API version (-api-version flag).",
        "language_version": "Kotlin language version (-language-version flag).",
        "plugin_options": "Additional -P compiler options.",
        "x_allow_result_return_type": "Enable kotlin.Result as a return type.",
        "x_strict_java_nullability_assertions": "Enable strict Java nullability assertions.",
        "x_wasm_attach_js_exception": "Enable attaching JS exceptions for Wasm.",
        "x_wasm_kclass_fqn": "Enable KClass::qualifiedName support for Wasm.",
    },
)
