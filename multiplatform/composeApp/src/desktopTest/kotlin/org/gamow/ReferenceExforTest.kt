package org.gamow

import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.gamow.core.ChargedChannel
import org.gamow.core.MassTable
import org.gamow.core.Reaction
import org.gamow.core.exfor.*
import java.io.File
import java.nio.file.Files
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.abs
import kotlin.math.max
import kotlin.test.*

/**
 * The Kotlin EXFOR port must reproduce `Shared/reference_exfor.json`, which the Swift NucPhysKit writes and checks
 * (ReferenceExforTests.swift): index lookups, file-name grammar, URLs, parsed tables and conversions.
 */
class ReferenceExforTest {
    private val ref = Json.parseToJsonElement(File("../../Shared/reference_exfor.json").readText()).jsonObject
    private val resources = File("../../Packages/NucToolkit/Tests/NucPhysKitTests/Resources")
    private val tab = MassTable.ame2020
    private val index = ExforIndex.bundled
    private val commit = "f9c2d73f780b576cf1276b8e4018fddd1430fee8"

    private fun JsonObject.str(k: String) = this[k]!!.jsonPrimitive.content

    /** Builds a JSON object leaving out null values (as Swift's JSONEncoder does for nil optionals). */
    private fun obj(vararg pairs: Pair<String, Any?>): JsonObject = buildJsonObject {
        for ((k, v) in pairs) if (v != null) put(k, json(v))
    }

    private fun json(v: Any): JsonElement = when (v) {
        is JsonElement -> v
        is String -> JsonPrimitive(v)
        is Number -> JsonPrimitive(v)
        is List<*> -> JsonArray(v.map { json(it!!) })
        is Map<*, *> -> JsonObject(v.entries.associate { it.key as String to json(it.value!!) })
        else -> error("unsupported $v")
    }

    /** Recursive comparison: numbers to 1e-9 relative, strings, lists and keys exactly. */
    private fun compare(want: JsonElement, got: JsonElement, path: String, problems: MutableList<String>) {
        when {
            want is JsonObject && got is JsonObject -> {
                if (want.keys != got.keys) { problems += "$path: keys ${want.keys.sorted()} vs ${got.keys.sorted()}"; return }
                for (k in want.keys.sorted()) compare(want[k]!!, got[k]!!, "$path.$k", problems)
            }
            want is JsonArray && got is JsonArray -> {
                if (want.size != got.size) { problems += "$path: ${want.size} vs ${got.size} elements"; return }
                for (i in want.indices) compare(want[i], got[i], "$path[$i]", problems)
            }
            want is JsonPrimitive && got is JsonPrimitive && want.isString && got.isString ->
                if (want.content != got.content) problems += "$path: Swift ${want.content}, Kotlin ${got.content}"
            want is JsonPrimitive && got is JsonPrimitive && !want.isString && !got.isString -> {
                val u = want.double
                val v = got.double
                if (!(abs(u - v) <= 1e-9 * max(1.0, abs(u)))) problems += "$path: Swift $u, Kotlin $v"
            }
            else -> problems += "$path: Swift $want, Kotlin $got"
        }
    }

    private fun check(name: String, want: JsonElement, got: JsonElement) {
        val problems = mutableListOf<String>()
        compare(want, got, name, problems)
        assertTrue(problems.isEmpty(), problems.take(20).joinToString("\n"))
    }

    private fun dataset(d: ExforDataset) = obj(
        "path" to d.path, "directory" to d.directory, "fileName" to d.fileName, "projectile" to d.projectile,
        "target" to d.target, "outgoing" to d.outgoing, "author" to d.author, "entry" to d.entry,
        "subentry" to d.subentry, "pointer" to d.pointer, "level" to d.level, "product" to d.product, "year" to d.year,
        "exforID" to d.exforID, "exforURL" to d.exforURL, "finalStateLabel" to d.finalStateLabel,
        "channelID" to d.channel.id, "label" to d.channel.label, "kind" to d.channel.kind,
        "url" to ExforClient.url(d, commit),
    )

    private fun point(p: ExforTable.Point) = obj("e" to p.energy, "de" to p.energyUncertainty, "v" to p.value, "dv" to p.uncertainty)

    private fun quantityName(q: ExforTable.Quantity) = if (q == ExforTable.Quantity.CROSS_SECTION) "crossSection" else "sFactor"
    private fun frameName(f: ExforTable.Frame) = if (f == ExforTable.Frame.CM) "cm" else "lab"
    private fun qualifierName(q: ExforTable.Qualifier) = when (q) {
        ExforTable.Qualifier.VALUE -> "value"
        ExforTable.Qualifier.UPPER_LIMIT -> "upperLimit"
        ExforTable.Qualifier.APPROXIMATE -> "approximate"
        ExforTable.Qualifier.OTHER -> "other"
    }

    @Test fun index() {
        val all = index.allDatasets().filterNotNull()
        val got = obj(
            "commit" to index.commit, "date" to index.date, "count" to index.count, "parsed" to all.size,
            "withLevel" to all.count { it.level != null }, "withProduct" to all.count { it.product != null },
            "yearSum" to all.sumOf { it.year.toLong() }, "byProjectile" to all.groupingBy { it.projectile }.eachCount(),
        )
        check("index", ref["index"]!!, got)
        assertEquals(51871, index.count)
        assertEquals(index.count, all.size)
    }

    @Test fun reactions() {
        val got = ref["reactions"]!!.jsonArray.map { c ->
            val n = c.jsonObject.str("reaction")
            val r = Reaction.parse(n)
            val (under, found) = index.datasetsAllowingInverse(r)
            obj(
                "reaction" to n, "projectileCode" to ExforChannel.projectileCode(r.projectile),
                "outgoingCodes" to ExforChannel.outgoingCodes(r), "swapped" to r.swappedBeamAndTarget?.plainLabel,
                "filedUnder" to under?.plainLabel, "paths" to found.map { it.path }, "first" to found.firstOrNull()?.let(::dataset),
            )
        }
        check("reactions", ref["reactions"]!!, JsonArray(got))
    }

    @Test fun channels() {
        val got = ref["channels"]!!.jsonArray.map { c ->
            val t = c.jsonObject.str("target")
            val target = tab.nuclide(named = t)!!
            obj("target" to t, "channels" to index.channels(target).map { cd ->
                val ch = cd.channel
                val p = ch.projectileNuclide(tab)!!
                assertEquals(cd.datasets, index.datasets(ch, target))
                obj("id" to ch.id, "label" to ch.label, "projectileLabel" to ch.projectileLabel,
                    "outgoingLabel" to ch.outgoingLabel, "kind" to ch.kind, "projectileZ" to p.z, "projectileA" to p.a,
                    "paths" to cd.datasets.map { it.path })
            })
        }
        check("channels", ref["channels"]!!, JsonArray(got))
    }

    @Test fun fileNamesAndUnits() {
        val names = ref["names"]!!.jsonArray.map { c ->
            val o = c.jsonObject
            val dir = o.str("directory"); val file = o.str("fileName")
            obj("directory" to dir, "fileName" to file, "dataset" to ExforDataset.parse(dir, file)?.let(::dataset))
        }
        check("names", ref["names"]!!, JsonArray(names))
        val units = ref["units"]!!.jsonArray.map { c ->
            val u = c.jsonObject.str("unit")
            val r = runCatching { ExforTable.dataUnit(u) }.getOrNull()
            obj("unit" to u, "quantity" to r?.first?.let(::quantityName), "factor" to r?.second)
        }
        check("units", ref["units"]!!, JsonArray(units))
        assertFailsWith<ExforTable.ParseError.UnsupportedUnit> { ExforTable.energyUnit("FURLONG") }
    }

    @Test fun tables() {
        val got = ref["tables"]!!.jsonArray.map { c ->
            val o = c.jsonObject
            val file = o["file"]?.jsonPrimitive?.content
            val inline = o["text"]?.jsonPrimitive?.content
            val text = if (file != null) File(resources, file).readText() else inline!!
            val t = ExforTable.parse(text)
            val p = o.str("projectile"); val target = o.str("target")
            val ch = ChargedChannel(tab.nuclide(named = p)!!, tab.nuclide(named = target)!!)
            val conv = ExforTable.Quantity.entries.flatMap { q ->
                ExforTable.Frame.entries.map { f ->
                    obj("quantity" to quantityName(q), "frame" to frameName(f), "points" to t.points(q, f, ch).map(::point))
                }
            }
            obj(
                "file" to file, "text" to inline, "projectile" to p, "target" to target,
                "quantity" to quantityName(t.quantity), "frame" to frameName(t.frame), "qualifier" to qualifierName(t.qualifier),
                "missing" to t.missingValues, "zeroEnergy" to t.zeroEnergyPoints.size, "levelEnergy" to t.levelEnergy,
                "title" to t.title, "reactionCode" to t.reactionCode, "residual" to t.residual, "firstAuthor" to t.firstAuthor,
                "year" to t.year, "reference" to t.reference, "institute" to t.institute, "facility" to t.facility,
                "entryID" to t.entryID, "points" to t.points.map(::point), "conversions" to conv,
            )
        }
        check("tables", ref["tables"]!!, JsonArray(got))
        assertFailsWith<ExforTable.ParseError.NoColumns> { ExforTable.parse("# Title: nothing\n1 2 3 4\n") }
        assertFailsWith<ExforTable.ParseError.NoData> {
            ExforTable.parse("#   E_in_lab(MeV) dE_in_lab(MeV) data(B) ddata(B)\n 1.0 0 NAN 0\n")
        }
    }

    @Test fun inflateRawRoundTrip() {
        val text = "#exfortables_py abc 2026-01-01\n@p/Al-27/p-g\nAl-27_p-g_Si-28_A.B-C1234-002-0-2000.txt\n".repeat(50)
        val d = java.util.zip.Deflater(9, true)
        d.setInput(text.encodeToByteArray()); d.finish()
        val buf = ByteArray(65536); val n = d.deflate(buf); d.end()
        assertEquals(text, inflateRaw(buf.copyOf(n)).decodeToString())
    }

    /** A cancelled caller does not abort the download; a second caller joins it; the table reaches the cache. */
    @Test fun clientSharesDownloadsAndCaches() = runBlocking {
        val dir = Files.createTempDirectory("exfor-test").toFile()
        try {
            val body = File(resources, "exfor_al27pg_chakrabarty.txt").readBytes()
            val requests = AtomicInteger()
            val urls = mutableListOf<String>()
            val client = ExforClient(dir.path, "test") { url ->
                requests.incrementAndGet(); synchronized(urls) { urls += url }
                delay(300); HttpResponse(200, body)
            }
            val d = ExforDataset.parse("p/Al-27/p-g", "Al-27_p-g-L0_Al-27_D.R.Chakrabarty-D6305-002-0-2017.txt")!!
            assertFalse(client.isCached(d))
            val first = async { client.text(d) }
            delay(50)
            first.cancel()
            val second = client.text(d)
            assertTrue(second.contains("D.R.Chakrabarty"))
            assertEquals(1, requests.get())
            assertTrue(client.isCached(d))
            assertEquals(second, client.text(d))
            assertEquals(1, requests.get())
            assertEquals(listOf("https://raw.githubusercontent.com/IAEA-NDS/exfortables_py/test/${d.path}"), urls)
            assertEquals(3, client.table(d).points.size)
            assertEquals(1, client.cacheUsage().second)
            val missing = ExforClient(dir.path, "test") { HttpResponse(404, ByteArray(0)) }
            val e = assertFailsWith<ExforClient.Failure.Http> { missing.text(d.copy(fileName = "x" + d.fileName)) }
            assertEquals(404, e.code)
            client.clearCache()
            assertFalse(client.isCached(d))
        } finally {
            dir.deleteRecursively()
        }
    }

    /** Downloads from GitHub; run with GAMOW_NETWORK_TESTS=1. */
    @Test fun downloadsPinnedTable() = runBlocking {
        if (System.getenv("GAMOW_NETWORK_TESTS") != "1") return@runBlocking
        val dir = Files.createTempDirectory("exfor-net").toFile()
        try {
            val client = ExforClient(dir.path)
            val d = index.datasets(Reaction.parse("27Al(p,g)28Si")).first { it.entry == "D6305" && it.directory == "p/Al-27/p-g" }
            assertEquals(File(resources, "exfor_al27pg_chakrabarty.txt").readText(), client.text(d))
            assertTrue(client.isCached(d))
            val space = ExforDataset.parse("a/Ni-58/a-p", "Ni-58_a-p_Cu-61_Abhishek Yadav-D6067-002-0-2008.txt")!!
            assertTrue(client.table(space).points.isNotEmpty())
        } finally {
            dir.deleteRecursively()
        }
    }
}
