package org.gamow.core

/** Text of a bundled data file (the Swift package's Resources folder, packaged with the app). */
expect fun readResourceText(name: String): String

/** Bytes of a bundled data file. */
expect fun readResourceBytes(name: String): ByteArray

/** Fixed-point and scientific formatting (common Kotlin has no String.format). */
expect fun formatFixed(x: Double, decimals: Int): String
expect fun formatSignificant(x: Double, digits: Int): String

/** Small persistent key–value store (SharedPreferences on Android, java.util.prefs on desktop). */
expect object Prefs {
    fun get(key: String): String?
    fun put(key: String, value: String)
}

/** Now, seconds since 1970 (UTC). */
expect fun nowEpochSeconds(): Double

/** A date as "25 Nov 2026" in the device's locale. */
expect fun formatDate(epochSeconds: Double): String
