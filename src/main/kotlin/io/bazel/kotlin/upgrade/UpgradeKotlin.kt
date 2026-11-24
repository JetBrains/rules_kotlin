package io.bazel.kotlin.upgrade

import java.nio.file.Path
import java.nio.file.Paths
import kotlin.system.exitProcess

/**
 * Upgrades the Kotlin release rules_kotlin pins, run with `bazel run` in a rules_kotlin checkout:
 *
 * ```
 * upgrade_kotlin --version <new> [--keep <old>]... [--dry-run]
 * upgrade_kotlin --native-version <new> [--keep <old>]... [--dry-run]
 * upgrade_kotlin --emit-overrides <release>
 * ```
 *
 * `--version` rewrites every pin of the release train, `--native-version` the Kotlin/Native pins
 * alone, `--dry-run` lists the files it would change and writes nothing, and `--emit-overrides`
 * prints the root MODULE.bazel snippet that selects a release. See docs/upgrading_kotlin.md;
 * scripts/upgrade_kotlin.sh runs the generators that follow an upgrade.
 */
object UpgradeKotlin {
  private const val USAGE =
    "usage: upgrade_kotlin --version <new> [--keep <old>]... [--dry-run]\n" +
      "       upgrade_kotlin --native-version <new> [--keep <old>]... [--dry-run]\n" +
      "       upgrade_kotlin --emit-overrides <release>"

  data class Options(
    val version: String? = null,
    val keep: List<String> = emptyList(),
    val dryRun: Boolean = false,
    val emitOverrides: String? = null,
    val nativeVersion: String? = null,
  ) {
    companion object {
      fun parse(args: List<String>): Options {
        var options = Options()
        val rest = ArrayDeque(args)

        fun value(flag: String): String =
          rest.removeFirstOrNull()?.takeIf { !it.startsWith("--") }
            ?: throw UpgradeException("$flag needs a value\n$USAGE")
        while (rest.isNotEmpty()) {
          options =
            when (val arg = rest.removeFirst()) {
              "--version" -> options.copy(version = value(arg))
              "--keep" -> options.copy(keep = options.keep + value(arg))
              "--dry-run" -> options.copy(dryRun = true)
              "--emit-overrides" -> options.copy(emitOverrides = value(arg))
              "--native-version" -> options.copy(nativeVersion = value(arg))
              else -> throw UpgradeException("unknown argument $arg\n$USAGE")
            }
        }
        val modes = listOfNotNull(options.version, options.emitOverrides, options.nativeVersion)
        if (modes.size != 1) {
          throw UpgradeException(
            "give one of --version, --native-version and --emit-overrides\n$USAGE",
          )
        }
        if (options.emitOverrides != null && (options.keep.isNotEmpty() || options.dryRun)) {
          throw UpgradeException("--emit-overrides takes no --keep or --dry-run\n$USAGE")
        }
        return options
      }
    }
  }

  /** Returns what goes to stdout; progress goes to [log]. */
  fun run(
    options: Options,
    upgrade: Upgrade,
    log: (String) -> Unit,
  ): String {
    options.emitOverrides?.let { return upgrade.overrides(it) }
    val native = options.nativeVersion
    val changes =
      if (native != null) {
        upgrade.planNative(native, options.keep)
      } else {
        upgrade.plan(options.version!!, options.keep)
      }
    if (changes.isEmpty()) {
      log(
        if (native != null) {
          "the pins of Kotlin/Native $native are up to date"
        } else {
          "the pins of Kotlin ${options.version} are up to date"
        },
      )
    } else if (options.dryRun) {
      changes.keys.sorted().forEach { log("would change $it") }
    } else {
      upgrade.write(changes)
      changes.keys.sorted().forEach { log("changed $it") }
    }
    if (options.dryRun || native != null) return ""
    return upgrade.repins().joinToString("") { "$it\n" }
  }

  @JvmStatic
  fun main(args: Array<String>) {
    val log: (String) -> Unit = { System.err.println("upgrade_kotlin: $it") }
    try {
      val options = Options.parse(args.toList())
      val workspace =
        System.getenv("BUILD_WORKSPACE_DIRECTORY")?.let(Paths::get)
          ?: throw UpgradeException("run it with `bazel run`: BUILD_WORKSPACE_DIRECTORY is unset")
      val upgrade = Upgrade(workspace, HttpReleaseSource(cacheDirectory(), log), log)
      print(run(options, upgrade, log))
    } catch (e: UpgradeException) {
      log("error: ${e.message}")
      if (!e.partial) log("nothing was written")
      exitProcess(1)
    } catch (e: Exception) {
      // Upgrade.write reports its failures as UpgradeException: this one came before it.
      log("error: unexpected ${Upgrade.describe(e)} at ${e.stackTrace.firstOrNull()}")
      log("nothing was written")
      exitProcess(1)
    }
  }

  /** `$RULES_KOTLIN_UPGRADE_CACHE`, or `rules_kotlin/upgrade_kotlin` in the user cache. */
  private fun cacheDirectory(): Path {
    System.getenv(DownloadCache.ENV)?.takeIf(String::isNotEmpty)?.let {
      return Paths.get(it)
    }
    val base =
      System.getenv("XDG_CACHE_HOME")?.takeIf(String::isNotEmpty)?.let(Paths::get)
        ?: Paths.get(System.getProperty("user.home"), ".cache")
    return base.resolve("rules_kotlin").resolve("upgrade_kotlin")
  }
}
