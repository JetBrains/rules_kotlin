#!/usr/bin/env bash
# Launcher for kt_native_binary (konanc -produce program) with PRE-STAGED konan deps.
#
# Binary linking needs the konan dependency bundle (LLVM / libffi / lldb / cross-toolchain),
# which konanc otherwise downloads to ~/.konan on first run. This launcher stages the
# Bazel-provided, pre-fetched dependency dirs of the target into a writable KONAN_DATA_DIR
# — symlinking each one and writing the `dependencies/.extracted` marker — so konanc finds
# them and skips the download. That lets the link action run sandboxed with no network.
#
# Like konanc_launcher.sh, it runs the compiler JVM with -Dkonan.home in the sandbox.
#
# Usage:
#   konanc_link_launcher.sh <konan_home> <konan_data_dir> <auto_cache_dir> <num_deps> <dep_dir1> ... <dep_dirN> [konanc args...]
set -euo pipefail
export PATH="/usr/bin:/bin${PATH:+:$PATH}"

konan_home="$1"
konan_data_dir="$2"
auto_cache_dir="$3"
num_deps="$4"
shift 4

mkdir -p "$konan_data_dir/dependencies" "$auto_cache_dir"

# Symlink each pre-staged dependency dir into the writable KONAN_DATA_DIR/dependencies,
# and write the .extracted marker to list exactly those dirs.
marker=""
for ((i = 0; i < num_deps; i++)); do
  name="$(basename "$1")"
  ln -sfn "$PWD/$1" "$konan_data_dir/dependencies/$name"
  marker+="$name"$'\n'
  shift
done
printf '%s' "$marker" > "$konan_data_dir/dependencies/.extracted"

export LIBCLANG_DISABLE_CRASH_RECOVERY=1
exec "$JAVA_HOME/bin/java" -ea -Xmx3G -XX:TieredStopAtLevel=1 -Dfile.encoding=UTF-8 \
  -Dkonan.home="$PWD/$konan_home" \
  -cp "$konan_home/konan/lib/kotlin-native-compiler-embeddable.jar" \
  org.jetbrains.kotlin.cli.utilities.MainKt konanc "$@"
