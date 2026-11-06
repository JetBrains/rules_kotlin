package examples.kmp.shared

/** The name of the platform the code runs on, e.g. `JVM 21` or `macOS`. */
expect fun platformName(): String

/** What the platform tells about itself. */
expect class PlatformInfo() {
  val name: String
  val is64Bit: Boolean
}
