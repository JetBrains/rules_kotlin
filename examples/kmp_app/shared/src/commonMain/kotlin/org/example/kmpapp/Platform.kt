package org.example.kmpapp

/** The platform the code runs on. */
interface Platform {
  val name: String
}

/** The platform of the code: each platform implements it with `actual`. */
expect fun getPlatform(): Platform
