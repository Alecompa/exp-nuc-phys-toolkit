package org.gamow.core.exfor

/** Decompresses raw DEFLATE data (no zlib or gzip header), as written by Tools/build_exfor_index.py. */
expect fun inflateRaw(data: ByteArray): ByteArray

/**
 * Root of the on-disk EXFOR cache (tables go to `<root>/<commit>/<path>`): the app's cache directory on Android,
 * the user cache directory on the desktop (~/.cache/gamow/exfor on Linux, ~/Library/Caches/gamow/exfor on macOS,
 * %LOCALAPPDATA%\gamow\cache\exfor on Windows).
 */
expect fun exforCacheRoot(): String

/** Answer of an HTTP GET: status code and body. */
class HttpResponse(val status: Int, val body: ByteArray)

/**
 * HTTP GET with java.net.HttpURLConnection on an I/O thread. Throws [ExforClient.Failure.Offline] when the host
 * cannot be reached and rethrows other I/O errors.
 */
expect suspend fun httpGet(url: String, userAgent: String, timeoutMillis: Int): HttpResponse

/** Minimal file access for the cache (common Kotlin has no file API). Paths are absolute, separated by "/". */
expect object ExforFiles {
    fun read(path: String): ByteArray?
    fun exists(path: String): Boolean
    /** Writes the file, creating its parent directories; errors are ignored (the cache is optional). */
    fun write(path: String, data: ByteArray)
    /** Total size in bytes and number of files below `root`. */
    fun usage(root: String): Pair<Long, Int>
    fun deleteTree(root: String)
}
