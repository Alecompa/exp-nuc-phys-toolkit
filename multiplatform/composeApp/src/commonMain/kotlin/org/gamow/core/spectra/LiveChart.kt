package org.gamow.core.spectra

import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import org.gamow.core.Elements
import org.gamow.core.Nubase
import org.gamow.core.exfor.ExforClient
import org.gamow.core.exfor.ExforFiles
import org.gamow.core.exfor.HttpResponse
import org.gamow.core.exfor.exforCacheRoot
import org.gamow.core.exfor.httpGet
import org.gamow.core.nowEpochSeconds

/** An excited level from ENSDF (IAEA LiveChart). */
data class Level(
    val index: Int,
    /** keV */
    val energy: Double,
    val energyUncertainty: Double?,
    val spinParity: String,
    /** Half-life as printed, e.g. "475 fs", "stable". */
    val halfLife: String,
    val halfLifeSeconds: Double?,
) {
    val id: Int get() = index
}

/** A γ transition between ENSDF levels. */
data class GammaTransition(
    val initialLevel: Double,
    val finalLevel: Double,
    val initialSpinParity: String,
    val finalSpinParity: String,
    /** keV */
    val energy: Double,
    val energyUncertainty: Double?,
    /** Relative intensity within the decay of the initial level (strongest = 100). */
    val relativeIntensity: Double?,
    val multipolarity: String,
) {
    val id: String
        get() = "${SpecMath.swiftDescription(initialLevel)}-${SpecMath.swiftDescription(finalLevel)}-${SpecMath.swiftDescription(energy)}"
}

/** ENSDF data for one nuclide. `retrieved` in seconds since 1970. */
data class LevelScheme(
    val levels: List<Level>,
    val gammas: List<GammaTransition>,
    /** ENSDF evaluation reference (authors, cut-off date). */
    val reference: String,
    val retrieved: Double,
)

/**
 * Client of the IAEA LiveChart of Nuclides data API (https://nds.iaea.org/relnsd/v1/data) with an on-disk cache
 * (the two CSV answers and the retrieval time, next to the EXFOR cache in `<cache>/livechart`). Network and files go
 * through the EXFOR client's expect/actual layer (HttpURLConnection on Dispatchers.IO). Port of NucPhysKit.LiveChartClient.
 *
 * @param fetch replaces the HTTP GET (tests); it receives the URL and returns status and body.
 */
class LiveChartClient(
    cacheDirectory: String? = null,
    private val fetch: suspend (url: String) -> HttpResponse = { httpGet(it, USER_AGENT, TIMEOUT_MILLIS) },
) {
    sealed class Failure(message: String) : Exception(message) {
        class Http(val code: Int) : Failure("The IAEA server answered with HTTP $code.")
        class Empty : Failure("No ENSDF levels for this nuclide.")
        class Offline : Failure("Not connected to the internet, and nothing is cached.")
    }

    private val directory: String = (cacheDirectory ?: defaultDirectory()).trimEnd('/', '\\')

    /** Cached data older than this (s) is refreshed when online. */
    var maxAge: Double = 30 * 86400.0

    private fun path(z: Int, a: Int, kind: String) = "$directory/${apiName(z, a)}.$kind"

    fun cached(z: Int, a: Int): LevelScheme? {
        val lv = ExforFiles.read(path(z, a, "levels.csv"))?.decodeToString() ?: return null
        val gm = ExforFiles.read(path(z, a, "gammas.csv"))?.decodeToString() ?: return null
        val t = ExforFiles.read(path(z, a, "retrieved"))?.decodeToString()?.trim()?.toDoubleOrNull() ?: return null
        return runCatching { parse(lv, gm, t) }.getOrNull()
    }

    /** Levels and γ rays, from the cache when fresh, otherwise from the network (falling back to stale cache). */
    suspend fun levelScheme(z: Int, a: Int, forceRefresh: Boolean = false): LevelScheme {
        val cache = cached(z, a)
        if (cache != null && !forceRefresh && nowEpochSeconds() - cache.retrieved < maxAge) return cache
        try {
            val name = apiName(z, a)
            val (lv, gm) = coroutineScope {
                val l = async { get("fields=levels&nuclides=$name") }
                val g = async { get("fields=gammas&nuclides=$name") }
                l.await() to g.await()
            }
            val now = nowEpochSeconds()
            val scheme = parse(lv, gm, now)
            ExforFiles.write(path(z, a, "levels.csv"), lv.encodeToByteArray())
            ExforFiles.write(path(z, a, "gammas.csv"), gm.encodeToByteArray())
            ExforFiles.write(path(z, a, "retrieved"), now.toString().encodeToByteArray())
            return scheme
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            if (cache != null) return cache
            if (e is ExforClient.Failure.Offline) throw Failure.Offline()
            throw e
        }
    }

    private suspend fun get(query: String): String {
        val r = fetch("https://nds.iaea.org/relnsd/v1/data?$query")
        if (r.status != 200) throw Failure.Http(r.status)
        return r.body.decodeToString()
    }

    companion object {
        const val USER_AGENT = "Gamow-toolkit/1.0 (Kotlin)"
        const val TIMEOUT_MILLIS = 20_000

        val shared: LiveChartClient by lazy { LiveChartClient() }

        /** `<platform cache>/livechart`, the sibling of the EXFOR cache directory. */
        private fun defaultDirectory(): String {
            val exfor = exforCacheRoot().trimEnd('/', '\\')
            val parent = exfor.substring(0, maxOf(exfor.lastIndexOf('/'), exfor.lastIndexOf('\\')).coerceAtLeast(0))
            return "$parent/livechart"
        }

        /** API name: lower-case mass number + symbol ("28si"). */
        fun apiName(z: Int, a: Int): String = "$a${(Elements.symbol(z) ?: "").lowercase()}"

        /** Parses the API's CSV answers. Throws [Failure.Empty] without levels. */
        fun parse(levels: String, gammas: String, retrieved: Double = nowEpochSeconds()): LevelScheme {
            val lv = table(levels)
            val gm = table(gammas)
            var reference = ""
            val levelList = lv.mapNotNull { r ->
                val e = SpecMath.parseDouble(r["energy"] ?: "") ?: return@mapNotNull null
                if (reference.isEmpty()) {
                    val au = r["ENSDF_authors"]
                    val cut = r["ENSDF_publication_cut-off"]
                    if (au != null && cut != null) reference = "$au, ENSDF cut-off $cut"
                }
                val hl = listOfNotNull(r["operator_hl"], r["half_life"], r["unit_hl"]).filter { it.isNotEmpty() }.joinToString(" ")
                Level(SpecMath.parseInt(r["idx"] ?: "") ?: 0, e, SpecMath.parseDouble(r["unc_e"] ?: ""), r["jp"] ?: "",
                    if (hl == "STABLE") "stable" else hl, SpecMath.parseDouble(r["half_life_sec"] ?: ""))
            }
            val gammaList = gm.mapNotNull { r ->
                val e = SpecMath.parseDouble(r["energy"] ?: "") ?: return@mapNotNull null
                val ei = SpecMath.parseDouble(r["start_level_energy"] ?: "") ?: return@mapNotNull null
                GammaTransition(ei, SpecMath.parseDouble(r["end_level_energy"] ?: "") ?: 0.0, r["start_level_jp"] ?: "",
                    r["end_level_jp"] ?: "", e, SpecMath.parseDouble(r["unc_en"] ?: ""),
                    SpecMath.parseDouble(r["relative_intensity"] ?: ""), r["multipolarity"] ?: "")
            }
            if (levelList.isEmpty()) throw Failure.Empty()
            return LevelScheme(levelList.sortedBy { it.energy }, gammaList, reference, retrieved)
        }

        /** CSV → rows keyed by header (later duplicate headers do not overwrite earlier ones). */
        internal fun table(csv: String): List<Map<String, String>> {
            val lines = csv.split('\n', '\r', '\u000B', '\u000C', '\u0085', ' ', ' ').filter { it.isNotEmpty() }
            val header = lines.firstOrNull()?.let { Nubase.fields(it) } ?: return emptyList()
            if (header.size <= 1) return emptyList()
            return lines.drop(1).map { line ->
                val row = HashMap<String, String>()
                for ((k, v) in header.zip(Nubase.fields(line))) if (k !in row) row[k] = v
                row
            }
        }
    }
}
