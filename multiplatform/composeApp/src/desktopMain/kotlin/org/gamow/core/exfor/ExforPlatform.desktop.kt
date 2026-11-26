package org.gamow.core.exfor

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

actual fun inflateRaw(data: ByteArray): ByteArray = jvmInflateRaw(data)

actual fun exforCacheRoot(): String {
    val home = System.getProperty("user.home") ?: "."
    val os = (System.getProperty("os.name") ?: "").lowercase()
    val base = when {
        os.contains("win") -> System.getenv("LOCALAPPDATA")?.let { File(it, "gamow/cache") } ?: File(home, "AppData/Local/gamow/cache")
        os.contains("mac") -> File(home, "Library/Caches/gamow")
        else -> System.getenv("XDG_CACHE_HOME")?.takeIf { it.isNotBlank() }?.let { File(it, "gamow") } ?: File(home, ".cache/gamow")
    }
    return File(base, "exfor").path
}

actual suspend fun httpGet(url: String, userAgent: String, timeoutMillis: Int): HttpResponse =
    withContext(Dispatchers.IO) { jvmHttpGet(url, userAgent, timeoutMillis) }

actual object ExforFiles {
    actual fun read(path: String): ByteArray? = jvmRead(path)
    actual fun exists(path: String): Boolean = File(path).isFile
    actual fun write(path: String, data: ByteArray) = jvmWrite(path, data)
    actual fun usage(root: String): Pair<Long, Int> = jvmUsage(root)
    actual fun deleteTree(root: String) { File(root).deleteRecursively() }
}

// The same JVM code is duplicated in ExforPlatform.android.kt (no shared JVM source set in this build).

private fun jvmInflateRaw(data: ByteArray): ByteArray {
    val inflater = java.util.zip.Inflater(true)
    try {
        // nowrap mode needs one extra dummy byte at the end of the input.
        inflater.setInput(data + byteArrayOf(0))
        val out = java.io.ByteArrayOutputStream(data.size * 4)
        val buf = ByteArray(64 * 1024)
        while (!inflater.finished()) {
            val n = inflater.inflate(buf)
            if (n == 0 && (inflater.needsInput() || inflater.needsDictionary())) break
            out.write(buf, 0, n)
        }
        if (!inflater.finished()) throw java.util.zip.DataFormatException("truncated DEFLATE stream")
        return out.toByteArray()
    } finally {
        inflater.end()
    }
}

private fun jvmHttpGet(url: String, userAgent: String, timeoutMillis: Int): HttpResponse {
    val conn = try {
        (java.net.URI(url).toURL().openConnection() as java.net.HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = timeoutMillis
            readTimeout = timeoutMillis
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", userAgent)
        }
    } catch (e: java.io.IOException) {
        throw ExforClient.Failure.Offline()
    }
    try {
        val status = try {
            conn.responseCode
        } catch (e: java.net.UnknownHostException) {
            throw ExforClient.Failure.Offline()
        } catch (e: java.net.ConnectException) {
            throw ExforClient.Failure.Offline()
        } catch (e: java.net.NoRouteToHostException) {
            throw ExforClient.Failure.Offline()
        }
        val body = if (status == 200) conn.inputStream.use { it.readBytes() } else ByteArray(0)
        return HttpResponse(status, body)
    } finally {
        conn.disconnect()
    }
}

private fun jvmRead(path: String): ByteArray? = File(path).takeIf { it.isFile }?.let { runCatching { it.readBytes() }.getOrNull() }

private fun jvmWrite(path: String, data: ByteArray) {
    runCatching {
        val f = File(path)
        f.parentFile?.mkdirs()
        val tmp = File(f.parentFile, f.name + ".part")
        tmp.writeBytes(data)
        if (!tmp.renameTo(f)) { f.writeBytes(data); tmp.delete() }
    }
}

private fun jvmUsage(root: String): Pair<Long, Int> {
    var bytes = 0L
    var n = 0
    File(root).walkTopDown().filter { it.isFile }.forEach { bytes += it.length(); n++ }
    return bytes to n
}
