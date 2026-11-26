package org.gamow.core.exfor

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Downloads exfortables_py tables from GitHub at the index's commit and caches them on disk under
 * `<cacheRoot>/<commit>/<path>`. Tables at a fixed commit never change, so a cached table is never fetched again.
 * Port of NucPhysKit.ExforClient.
 *
 * @param fetch replaces the HTTP GET (tests); it receives the URL and returns status and body.
 */
class ExforClient(
    cacheRoot: String? = null,
    val commit: String = ExforIndex.bundled.commit,
    private val fetch: suspend (url: String) -> HttpResponse = { httpGet(it, USER_AGENT, TIMEOUT_MILLIS) },
) {
    sealed class Failure(message: String) : Exception(message) {
        class Http(val code: Int) : Failure(
            if (code == 404) "The table is not on GitHub at this commit (HTTP 404)." else "GitHub answered with HTTP $code.",
        )
        class Offline : Failure("Not connected to the internet, and this table is not cached.")
    }

    private val root: String = (cacheRoot ?: exforCacheRoot()).trimEnd('/', '\\')
    private val cacheDirectory: String = "$root/$commit"

    /** Downloads run here, not in the caller's scope: cancelling a caller does not abort a download. */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val lock = Mutex()
    /** Downloads in progress, keyed by path, shared by all callers. */
    private val inFlight = HashMap<String, Deferred<String>>()

    private fun cachePath(d: ExforDataset): String = "$cacheDirectory/${d.path}"

    /** The table's text from the cache, if downloaded before. */
    fun cachedText(d: ExforDataset): String? = ExforFiles.read(cachePath(d))?.decodeToString()

    fun isCached(d: ExforDataset): Boolean = ExforFiles.exists(cachePath(d))

    /**
     * The table's text, from the cache or downloaded (and then cached). The download runs in the client's own scope,
     * so cancelling the caller (a screen that goes away) does not abort it: the table still reaches the cache, and a
     * caller that asks again while it runs waits for the same download instead of starting a second one.
     */
    suspend fun text(d: ExforDataset): String {
        cachedText(d)?.let { return it }
        val job = lock.withLock {
            inFlight[d.path] ?: scope.async {
                try {
                    download(d)
                } finally {
                    lock.withLock { inFlight.remove(d.path) }
                }
            }.also { inFlight[d.path] = it }
        }
        return job.await()
    }

    private suspend fun download(d: ExforDataset): String {
        val response = fetch(url(d, commit))
        if (response.status != 200) throw Failure.Http(response.status)
        ExforFiles.write(cachePath(d), response.body)
        return response.body.decodeToString()
    }

    /** Downloads (or reads from the cache) and parses a table. */
    suspend fun table(d: ExforDataset): ExforTable = ExforTable.parse(text(d))

    /** Size of the cache in bytes and the number of tables in it (all commits). */
    fun cacheUsage(): Pair<Long, Int> = ExforFiles.usage(root)

    fun clearCache() = ExforFiles.deleteTree(root)

    companion object {
        const val USER_AGENT = "Gamow-toolkit/1.0 (Kotlin)"
        const val TIMEOUT_MILLIS = 20_000

        /** Shared client with the default cache and the bundled index's commit. */
        val shared: ExforClient by lazy { ExforClient() }

        private const val HEX = "0123456789ABCDEF"
        /** Characters left as they are: Foundation's urlPathAllowed without "+", "?" and "#". */
        private fun allowed(b: Int): Boolean {
            val c = b.toChar()
            return (c in 'A'..'Z') || (c in 'a'..'z') || (c in '0'..'9') || c in "!$&'()*,-./:;=@_~"
        }

        /** raw.githubusercontent.com URL of a table at the pinned commit (path percent-encoded as in the Swift app). */
        fun url(d: ExforDataset, commit: String): String {
            val sb = StringBuilder()
            for (byte in d.path.encodeToByteArray()) {
                val b = byte.toInt() and 0xFF
                if (b < 0x80 && allowed(b)) sb.append(b.toChar())
                else sb.append('%').append(HEX[b shr 4]).append(HEX[b and 0xF])
            }
            return "https://raw.githubusercontent.com/IAEA-NDS/exfortables_py/$commit/$sb"
        }
    }
}
