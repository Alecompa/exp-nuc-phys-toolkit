package org.gamow.core

/** Data files are packaged as Java resources on the desktop classpath (the Swift package's Resources folder). */
actual fun readResourceBytes(name: String): ByteArray =
    (ResourceAnchor::class.java.getResourceAsStream("/$name") ?: error("$name missing from the app")).use { it.readBytes() }

actual fun readResourceText(name: String): String = readResourceBytes(name).decodeToString()

actual fun formatFixed(x: Double, decimals: Int): String = String.format(java.util.Locale.ROOT, "%.${decimals}f", x)
actual fun formatSignificant(x: Double, digits: Int): String = String.format(java.util.Locale.ROOT, "%.${digits}g", x)

private object ResourceAnchor

actual object Prefs {
    private val node = java.util.prefs.Preferences.userRoot().node("org/gamow")
    actual fun get(key: String): String? = node.get(key, null)
    actual fun put(key: String, value: String) { node.put(key, value); node.flush() }
}

actual fun nowEpochSeconds(): Double = System.currentTimeMillis() / 1000.0

actual fun formatDate(epochSeconds: Double): String =
    java.text.DateFormat.getDateInstance(java.text.DateFormat.MEDIUM).format(java.util.Date((epochSeconds * 1000).toLong()))
