/*
 * Copyright 2026 The Bazel Authors. All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.jetbrains.kotlin.cli.utilities;

import static java.nio.charset.StandardCharsets.UTF_8;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.LinkOption;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;
import java.util.stream.Stream;
import org.jetbrains.kotlin.backend.konan.KonanCompilationException;

/**
 * A stand-in for the entry point of the Kotlin/Native compiler jar, for KonanLauncherTest.
 *
 * <p>{@code daemonMain} writes a report of what it gets and sees to the file after {@code -o}: the
 * tool and its arguments, {@code konan.home}, the class loaders, and the dependencies staged in the
 * {@code -Xkonan-data-dir}. Then it throws a compilation error for {@code -fail} and a crash for
 * {@code -crash}.
 */
public final class MainKt {
  private MainKt() {}

  public static void daemonMain(String[] args) throws IOException {
    List<String> report = new ArrayList<>();
    report.add("tool=" + args[0]);
    report.add("konan.home=" + System.getProperty("konan.home"));
    ClassLoader loader = MainKt.class.getClassLoader();
    report.add("context-loader-is-compiler-loader=" + (Thread.currentThread().getContextClassLoader() == loader));
    report.add("launcher-visible=" + visible("io.bazel.kotlin.native.KonanLauncher", loader));
    report.add("kotlin-stdlib-visible=" + visible("kotlin.Unit", loader));

    Path output = null;
    for (int i = 1; i < args.length; i++) {
      String arg = args[i];
      report.add("arg=" + arg);
      if (arg.equals("-o")) {
        output = Paths.get(args[i + 1]);
      } else if (arg.startsWith("-Xkonan-data-dir=")) {
        reportDependencies(Paths.get(arg.substring("-Xkonan-data-dir=".length())), report);
      } else if (arg.startsWith("-Xauto-cache-dir=")) {
        Path cache = Paths.get(arg.substring("-Xauto-cache-dir=".length()));
        report.add("auto-cache-dir=" + (Files.isDirectory(cache) ? entries(cache).size() + " entries" : "missing"));
      }
    }
    if (output != null) {
      Files.write(output, report, UTF_8);
    }

    for (String arg : args) {
      if (arg.equals("-fail")) {
        throw new KonanCompilationException("Compilation finished with errors");
      }
      if (arg.equals("-crash")) {
        throw new IllegalStateException("the fake compiler crashed");
      }
    }
  }

  private static void reportDependencies(Path dataDir, List<String> report) throws IOException {
    if (!Files.isDirectory(dataDir)) {
      report.add("data-dir=missing");
      return;
    }
    report.add("data-dir=" + entries(dataDir).size() + " entries");
    Path dependencies = dataDir.resolve("dependencies");
    if (!Files.isDirectory(dependencies)) {
      return;
    }
    for (Path entry : entries(dependencies)) {
      if (Files.isSymbolicLink(entry)) {
        report.add("dependency=" + entry.getFileName() + " -> " + Files.readSymbolicLink(entry));
      } else if (!entry.getFileName().toString().equals(".extracted")) {
        report.add("not-a-link=" + entry.getFileName());
      }
    }
    Path extracted = dependencies.resolve(".extracted");
    if (Files.exists(extracted, LinkOption.NOFOLLOW_LINKS)) {
      report.add("extracted=" + new String(Files.readAllBytes(extracted), UTF_8).replace("\n", "\\n"));
    }
  }

  private static List<Path> entries(Path dir) throws IOException {
    try (Stream<Path> stream = Files.list(dir)) {
      return stream.sorted().collect(Collectors.toList());
    }
  }

  private static boolean visible(String className, ClassLoader loader) {
    try {
      Class.forName(className, false, loader);
      return true;
    } catch (ClassNotFoundException e) {
      return false;
    }
  }
}
