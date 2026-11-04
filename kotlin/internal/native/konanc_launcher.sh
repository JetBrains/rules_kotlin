#!/usr/bin/env bash
# Launcher for konanc Bazel actions.
#
# konanc does not create its -Xauto-cache-dir (and writing the auto-cache into the
# read-only distribution repo makes Bazel re-fetch it every build). So this launcher
# creates N action-local scratch dirs, then runs konanc.
#
# It runs the compiler JVM as the distribution's bin/run_konan does, but with -Dkonan.home
# in the sandbox: run_konan resolves its own symlink to the real repository, so konanc would
# read the whole distribution from outside the sandbox instead of the action inputs.
#
# Usage: konanc_launcher.sh <konan_home> <num_dirs> <dir1> ... <dirN> [konanc args...]
#
# PATH is set here (only `mkdir` is needed) so the action env stays minimal; `java` comes
# from JAVA_HOME (set by the rule from the Bazel JDK toolchain), not PATH.
set -euo pipefail
export PATH="/usr/bin:/bin${PATH:+:$PATH}"

konan_home="$1"
num_dirs="$2"
shift 2

for ((i = 0; i < num_dirs; i++)); do
  mkdir -p "$1"
  shift
done

export LIBCLANG_DISABLE_CRASH_RECOVERY=1
exec "$JAVA_HOME/bin/java" -ea -Xmx3G -XX:TieredStopAtLevel=1 -Dfile.encoding=UTF-8 \
  -Dkonan.home="$PWD/$konan_home" \
  -cp "$konan_home/konan/lib/kotlin-native-compiler-embeddable.jar" \
  org.jetbrains.kotlin.cli.utilities.MainKt konanc "$@"
