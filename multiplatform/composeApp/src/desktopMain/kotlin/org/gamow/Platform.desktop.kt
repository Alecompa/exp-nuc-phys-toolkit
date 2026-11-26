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
    /** java.util.prefs rejects values over 8192 characters: long values are split into numbered chunk keys. */
    private const val CHUNK = 7000
    private const val MARK = "@@gamow-chunks:"   // java.util.prefs also rejects the NUL character

    actual fun get(key: String): String? {
        val v = node.get(key, null) ?: return null
        if (!v.startsWith(MARK)) return v
        val n = v.removePrefix(MARK).toIntOrNull() ?: return null
        return (0 until n).joinToString("") { node.get("$key#$it", "") }
    }

    actual fun put(key: String, value: String) {
        try {
            val old = node.get(key, null)?.takeIf { it.startsWith(MARK) }?.removePrefix(MARK)?.toIntOrNull() ?: 0
            if (value.length <= CHUNK) node.put(key, value)
            else {
                val parts = value.chunked(CHUNK)
                parts.forEachIndexed { i, p -> node.put("$key#$i", p) }
                node.put(key, MARK + parts.size)
            }
            val now = if (value.length <= CHUNK) 0 else (value.length + CHUNK - 1) / CHUNK
            for (i in now until old) node.remove("$key#$i")
            node.flush()
        } catch (e: Exception) {
            System.err.println("Gamow: could not save setting $key: ${e.message}")
        }
    }
}

actual fun nowEpochSeconds(): Double = System.currentTimeMillis() / 1000.0

actual fun formatDate(epochSeconds: Double): String =
    java.text.DateFormat.getDateInstance(java.text.DateFormat.MEDIUM).format(java.util.Date((epochSeconds * 1000).toLong()))
