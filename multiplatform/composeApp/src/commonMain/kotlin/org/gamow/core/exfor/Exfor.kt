package org.gamow.core.exfor

import org.gamow.core.ChargedChannel
import org.gamow.core.MassTable
import org.gamow.core.Nuclide
import org.gamow.core.Reaction
import org.gamow.core.Superscript
import org.gamow.core.readResourceBytes

// EXFOR experimental cross sections, from the tables that the IAEA Nuclear Data Section publishes as
// IAEA-NDS/exfortables_py. Port of NucPhysKit/NuclearData/EXFOR.swift: the app bundles an index of the tables at one
// pinned commit and downloads a table from GitHub only when it is opened (see ExforClient.kt).

// region Dataset

/** One EXFOR cross-section table: an EXFOR subentry and data pointer for one reaction. */
data class ExforDataset(
    /** Directory in exfortables_py before `/xs/`: "p/Al-27/p-g", "ion/C-12/C-12/a-L1". */
    val directory: String,
    /** File name after `/xs/` (may contain "/" for isomer labels such as "Au-196-M2/T"). */
    val fileName: String,
    /** "p", "d", "t", "h" (³He), "a" (α) or a heavy ion such as "C-12". */
    val projectile: String,
    /** "Al-27" */
    val target: String,
    /** Outgoing channel without the level suffix: "g", "a", "n", "el", "inl", "x", "n+p", "he3", "f"… */
    val outgoing: String,
    /** Final level of the residual (0 = ground state) when the table is for one level, null for the total. */
    val level: Int?,
    /** Reaction product named in the file name (residual nucleus for production cross sections), if any. */
    val product: String?,
    val author: String,
    /** EXFOR entry (5 characters), subentry (3 digits) and data pointer. */
    val entry: String,
    val subentry: String,
    val pointer: String,
    val year: Int,
) {
    val path: String get() = "$directory/xs/$fileName"
    val id: String get() = path
    /** "D6305-002", with the pointer appended when it is not 0. */
    val exforID: String get() = "$entry-$subentry" + (if (pointer == "0") "" else "-$pointer")
    /** Page of the entry in the IAEA EXFOR web retrieval. */
    val exforURL: String get() = "https://nds.iaea.org/EXFOR/$entry"

    /** The reaction channel this table belongs to. */
    val channel: ExforChannel get() = ExforChannel(projectile, target, outgoing)

    /** "Total", "Ground state", "Level 3". */
    val finalStateLabel: String
        get() = when (level) {
            null -> "Total"
            0 -> "Ground state"
            else -> "Level $level"
        }

    companion object {
        /**
         * Parses an index entry. Returns null when the names do not follow the exfortables_py grammar
         * `<target>_<code>[_<product>]_<author>-<entry>-<subentry>-<pointer>-<year>.txt`.
         */
        fun parse(directory: String, fileName: String): ExforDataset? {
            val dir = directory.split('/').filter { it.isNotEmpty() }
            val target: String
            val projectile: String
            val channelDir: String
            val first = dir.firstOrNull()
            when {
                first == "ion" && dir.size == 4 -> { target = dir[1]; projectile = dir[2]; channelDir = dir[3] }
                first != null && dir.size == 3 && first in ExforIndex.lightProjectiles -> {
                    target = dir[1]; projectile = first
                    if (!dir[2].startsWith("$first-")) return null
                    channelDir = dir[2].substring(first.length + 1)
                }
                else -> return null
            }
            val (outgoing, dirLevel) = splitLevel(channelDir)

            val fields = fileName.split('_')
            if (!(fields.size == 3 || fields.size == 4) || fields[0] != target || !fields.last().endsWith(".txt")) return null
            val product = if (fields.size == 4) fields[2] else null
            val level = splitLevel(fields[1]).second ?: dirLevel

            val tail = fields.last().dropLast(4).split('-')
            if (tail.size < 5) return null
            val year = tail[tail.size - 1].toIntOrNull() ?: return null
            if (tail[tail.size - 4].length != 5) return null
            return ExforDataset(
                directory = directory, fileName = fileName, projectile = projectile, target = target,
                outgoing = outgoing, level = level, product = product,
                author = tail.subList(0, tail.size - 4).joinToString("-"),
                entry = tail[tail.size - 4], subentry = tail[tail.size - 3], pointer = tail[tail.size - 2], year = year,
            )
        }

        private val levelSuffix = Regex("""-L\d+$""")

        /** "p-g-L1" → ("p-g", 1); "a" → ("a", null). */
        fun splitLevel(s: String): Pair<String, Int?> {
            val m = levelSuffix.find(s) ?: return s to null
            val l = m.value.drop(2).toIntOrNull() ?: return s to null
            return s.substring(0, m.range.first) to l
        }
    }
}

// endregion
// region Channel

/** A reaction channel target(projectile, outgoing) with all its tables. */
data class ExforChannel(val projectile: String, val target: String, val outgoing: String) {
    val id: String get() = "$target($projectile,$outgoing)"

    /** The projectile as a nuclide ("h" is ³He, "C-12" is ¹²C). */
    fun projectileNuclide(table: MassTable = MassTable.ame2020): Nuclide? = when (projectile) {
        "p", "d", "t", "a" -> table.nuclide(named = projectile)
        "h" -> table.nuclide(named = "3He")
        else -> {
            val p = projectile.split('-').filter { it.isNotEmpty() }
            if (p.size != 2) null else table.nuclide(named = "${p[1]}${p[0]}")
        }
    }

    /** Entrance channel projectile + target, used for lab ↔ c.m. and σ ↔ S conversions. */
    fun entranceChannel(target: Nuclide, table: MassTable = MassTable.ame2020): ChargedChannel? =
        projectileNuclide(table)?.let { ChargedChannel(it, target) }

    /** Readable notation: "(p,γ)", "(α,n)", "(¹²C,α)", "(p,X)", "(p,p′)". */
    val label: String get() = "(${particleLabel(projectile)},$outgoingLabel)"

    /** "p", "α", "³He", "¹²C" */
    val projectileLabel: String get() = particleLabel(projectile)

    val outgoingLabel: String
        get() = when (outgoing) {
            "el" -> particleLabel(projectile)
            "inl" -> particleLabel(projectile) + "′"
            "x" -> "X"
            "non" -> "nonel."
            "abs" -> "abs."
            "tot" -> "total"
            else -> outgoing.split('+').filter { it.isNotEmpty() }.joinToString("+") { particleLabel(it) }
        }

    /** Short description for list rows. */
    val kind: String
        get() = when (outgoing) {
            "g" -> "Radiative capture"
            "el" -> "Elastic scattering"
            "inl" -> "Inelastic scattering"
            "x" -> "Production cross sections"
            "non" -> "Nonelastic"
            "f" -> "Fission"
            "abs" -> "Absorption"
            else -> "Reaction"
        }

    companion object {
        /** Code of a nuclide as an exfortables_py projectile: "p", "d", "t", "h", "a" or "C-12". */
        fun projectileCode(n: Nuclide): String = when (n.z to n.a) {
            1 to 1 -> "p"
            1 to 2 -> "d"
            1 to 3 -> "t"
            2 to 3 -> "h"
            2 to 4 -> "a"
            else -> ExforIndex.name(n)
        }

        /**
         * Outgoing-channel codes that correspond to a two-body reaction. Elastic scattering maps to "el" and the
         * inelastic channel "inl"; for the light-ion tree ³He is written "he3".
         */
        fun outgoingCodes(r: Reaction): List<String> {
            val e = r.ejectile.nuclide ?: return listOf("g")
            if (e == r.projectile && r.residual == r.target) return listOf("el", "inl")
            return when (e.z to e.a) {
                0 to 1 -> listOf("n")
                1 to 1 -> listOf("p")
                1 to 2 -> listOf("d")
                1 to 3 -> listOf("t")
                2 to 3 -> listOf("he3", "h")
                2 to 4 -> listOf("a")
                else -> listOf(ExforIndex.name(e))
            }
        }

        /** "a" → "α", "h"/"he3" → "³He", "g" → "γ", "2n" stays, "C-12" → "¹²C". */
        fun particleLabel(code: String): String {
            when (code) {
                "g" -> return "γ"
                "a" -> return "α"
                "h", "he3" -> return "³He"
                "p", "n", "d", "t" -> return code
            }
            val parts = code.split('-').filter { it.isNotEmpty() }
            if (parts.size == 2) parts[1].toIntOrNull()?.let { return Superscript.digits(it) + parts[0] }
            // multiplicities such as "2n", "3p", "2a"
            val m = code.firstOrNull()
            if (m != null && m.isDigit()) return m + particleLabel(code.drop(1))
            return code
        }
    }
}

/** A channel with its tables, newest first. */
data class ExforChannelDatasets(val channel: ExforChannel, val datasets: List<ExforDataset>)

// endregion
// region Index

/** Index of the EXFOR cross-section tables in IAEA-NDS/exfortables_py at one commit. */
class ExforIndex(text: String) {
    /** Commit of IAEA-NDS/exfortables_py the index was built from; table URLs use it. */
    val commit: String
    /** Commit date (YYYY-MM-DD). */
    val date: String
    /** Number of tables. */
    val count: Int

    private class Group(val directory: String, val from: Int, val until: Int)
    private val lines: List<String>
    private val groupsByTarget: Map<String, List<Group>>

    class Failure(message: String) : Exception(message)

    init {
        lines = splitLines(text)
        val header = lines.firstOrNull()
        if (header == null || !header.startsWith("#exfortables_py ")) throw Failure("The EXFOR index could not be read.")
        val h = header.split(' ').filter { it.isNotEmpty() }
        commit = h.getOrElse(1) { "" }
        date = h.getOrElse(2) { "" }
        val groups = LinkedHashMap<String, MutableList<Group>>()
        var i = 1
        var n = 0
        while (i < lines.size) {
            if (!lines[i].startsWith("@")) { i++; continue }
            val dir = lines[i].substring(1)
            var j = i + 1
            while (j < lines.size && !lines[j].startsWith("@")) j++
            val parts = dir.split('/').filter { it.isNotEmpty() }
            if (parts.size >= 3) {
                groups.getOrPut(parts[1]) { ArrayList() }.add(Group(dir, i + 1, j))
                n += j - i - 1
            }
            i = j
        }
        groupsByTarget = groups
        count = n
    }

    /** All tables with `target` as the target nucleus, in index order. */
    fun datasets(target: Nuclide): List<ExforDataset> =
        (groupsByTarget[name(target)] ?: emptyList()).flatMap { g ->
            (g.from until g.until).mapNotNull { ExforDataset.parse(g.directory, lines[it]) }
        }

    /** Every entry of the index parsed as a dataset (null where a name does not parse); for validation. */
    fun allDatasets(): List<ExforDataset?> =
        groupsByTarget.values.flatten().flatMap { g -> (g.from until g.until).map { ExforDataset.parse(g.directory, lines[it]) } }

    /**
     * Reaction channels measured on `target`, with their tables, sorted light projectiles first (p, α, d, ³He, t,
     * then heavy ions alphabetically) and, within a projectile, by number of tables. Ties are broken by channel id
     * so the order is reproducible (the Swift version leaves ties in dictionary order).
     */
    fun channels(target: Nuclide): List<ExforChannelDatasets> {
        val order = mapOf("p" to 0, "a" to 1, "d" to 2, "h" to 3, "t" to 4)
        return datasets(target).groupBy { it.channel }
            .map { (c, ds) -> ExforChannelDatasets(c, ds.sortedWith(newestFirst)) }
            .sortedWith(
                compareBy<ExforChannelDatasets> { order[it.channel.projectile] ?: 9 }
                    .thenBy { it.channel.projectile }
                    .thenByDescending { it.datasets.size }
                    .thenBy { it.channel.id },
            )
    }

    /** Tables for a two-body reaction (all final states). For inverse kinematics use [Reaction.swappedBeamAndTarget]. */
    fun datasets(reaction: Reaction): List<ExforDataset> {
        val p = ExforChannel.projectileCode(reaction.projectile)
        val out = ExforChannel.outgoingCodes(reaction).toSet()
        return datasets(reaction.target).filter { it.projectile == p && it.outgoing in out }.sortedWith(newestFirst)
    }

    /**
     * Tables for a reaction as the user entered it: the normal-kinematics tables, or, when there are none and the
     * reaction is written in inverse kinematics (heavy beam on a light target, e.g. p(⁷Be,γ)⁸B), the tables of the
     * swapped reaction ⁷Be(p,γ)⁸B. Returns the reaction the tables are filed under (null when there are none),
     * as the Swift EXFOR screen does.
     */
    fun datasetsAllowingInverse(reaction: Reaction): Pair<Reaction?, List<ExforDataset>> {
        val direct = datasets(reaction)
        if (direct.isNotEmpty()) return reaction to direct
        val swapped = reaction.swappedBeamAndTarget ?: return null to emptyList()
        val other = datasets(swapped)
        return if (other.isEmpty()) null to emptyList() else swapped to other
    }

    /** Tables of one channel. */
    fun datasets(channel: ExforChannel, target: Nuclide): List<ExforDataset> =
        datasets(target).filter { it.channel == channel }.sortedWith(newestFirst)

    companion object {
        val lightProjectiles = setOf("p", "d", "t", "h", "a")

        /** Newest first, then by path. */
        val newestFirst: Comparator<ExforDataset> = compareByDescending<ExforDataset> { it.year }.thenBy { it.path }

        /** exfortables_py name of a nuclide: "Al-27", "He-4", "H-1". */
        fun name(n: Nuclide): String = "${n.symbol}-${n.a}"

        /** Reads the raw-DEFLATE file written by Tools/build_exfor_index.py. */
        fun fromCompressed(data: ByteArray): ExforIndex {
            val raw = try { inflateRaw(data) } catch (e: Exception) { throw Failure("The EXFOR index could not be read.") }
            return ExforIndex(raw.decodeToString())
        }

        /** The index bundled with the app (empty if the resource is missing, which the tests catch). */
        val bundled: ExforIndex by lazy {
            runCatching { fromCompressed(readResourceBytes("exfor_index.deflate")) }.getOrNull()
                ?: ExforIndex("#exfortables_py unavailable -\n")
        }
    }
}

// endregion
// region Table

/** A downloaded exfortables_py table, in keV and barn (or keV b for S factors). */
data class ExforTable(
    val quantity: Quantity,
    val frame: Frame,
    val qualifier: Qualifier,
    /** Points with a numerical value (rows with NAN are dropped), sorted by energy. */
    val points: List<Point>,
    /** Number of rows without a value (NAN in the table). */
    val missingValues: Int,
    val title: String = "",
    /** EXFOR reaction code, e.g. "(13-AL-27(P,G)14-SI-28,PAR,SIG)". */
    val reactionCode: String = "",
    val residual: String = "",
    /** Excitation energy of the final level, keV, when the table is for one level. */
    val levelEnergy: Double? = null,
    val firstAuthor: String = "",
    val year: String = "",
    /** EXFOR reference code, e.g. "(J,PR/C,95,014614,2017)". */
    val reference: String = "",
    val institute: String = "",
    val facility: String = "",
    val entryID: String = "",
) {
    enum class Quantity { CROSS_SECTION, S_FACTOR }
    enum class Frame { LAB, CM }
    /** EXFOR data heading: an ordinary value, an upper limit (DATA-MAX) or an approximate value (DATA-APRX). */
    enum class Qualifier { VALUE, UPPER_LIMIT, APPROXIMATE, OTHER }

    data class Point(
        /** keV, in `frame` */
        val energy: Double,
        val energyUncertainty: Double?,
        /** barn for a cross section, keV b for an S factor */
        val value: Double,
        val uncertainty: Double?,
    )

    sealed class ParseError(message: String) : Exception(message) {
        class NoColumns : ParseError("The table has no column header.")
        class UnsupportedUnit(val unit: String) : ParseError("Unit “$unit” is not supported.")
        class NoData : ParseError("The table has no data points.")
    }

    /**
     * Rows at zero energy. EXFOR stores extrapolated S(0) values this way; they cannot be converted to σ or plotted
     * on a logarithmic energy axis, and [points] with a channel leaves them out.
     */
    val zeroEnergyPoints: List<Point> get() = points.filter { it.energy <= 0 }

    /**
     * The points as σ or S at laboratory or centre-of-mass energies, converted with the entrance channel
     * (non-relativistic, target at rest; S = σ E exp(2πη) at the c.m. energy). The relative uncertainty of the value
     * is kept; the energy uncertainty is not propagated into the value.
     */
    fun points(quantity: Quantity, frame: Frame, channel: ChargedChannel): List<Point> = points.mapNotNull { p ->
        val ecm = if (this.frame == Frame.CM) p.energy else channel.cmEnergy(p.energy)
        if (!(ecm > 0)) return@mapNotNull null
        val eOut = if (frame == Frame.CM) ecm else channel.labEnergy(ecm)
        val eFactor = eOut / p.energy
        var factor = 1.0
        if (quantity != this.quantity) {
            val sOverSigma = ecm * kotlin.math.exp(2 * kotlin.math.PI * channel.sommerfeld(ecm))
            factor = if (quantity == Quantity.S_FACTOR) sOverSigma else 1 / sOverSigma
        }
        val v = p.value * factor
        if (!v.isFinite()) return@mapNotNull null
        Point(eOut, p.energyUncertainty?.let { it * eFactor }, v, p.uncertainty?.let { it * kotlin.math.abs(factor) })
    }

    companion object {
        /** Parses an exfortables_py text table. Throws [ParseError]. */
        fun parse(text: String): ExforTable {
            val meta = HashMap<String, String>()
            var columns: List<String> = emptyList()
            val points = ArrayList<Point>()
            var missing = 0
            var eScale = 1.0; var eUncScale = 1.0; var yScale = 1.0; var yUncScale = 1.0
            var quantity = Quantity.CROSS_SECTION; var frame = Frame.LAB; var qualifier = Qualifier.VALUE

            for (raw in splitLines(text)) {
                val line = raw.trim(' ', '\t')
                if (line.startsWith("#")) {
                    val body = line.substring(1).trim(' ', '\t')
                    if (body.startsWith("E_in_") || body.startsWith("dE_in_")) {
                        columns = body.split(' ').filter { it.isNotEmpty() }
                        if (columns.size < 4) throw ParseError.NoColumns()
                        frame = if (columns[0].startsWith("E_in_cm")) Frame.CM else Frame.LAB
                        eScale = energyUnit(unitOf(columns[0]))
                        eUncScale = energyUnit(unitOf(columns[1]))
                        dataUnit(unitOf(columns[2])).let { quantity = it.first; yScale = it.second }
                        yUncScale = dataUnit(unitOf(columns[3])).second
                        qualifier = when (columns[2].takeWhile { it != '(' }) {
                            "data" -> Qualifier.VALUE
                            "data_max" -> Qualifier.UPPER_LIMIT
                            "data_aprx" -> Qualifier.APPROXIMATE
                            else -> Qualifier.OTHER
                        }
                    } else {
                        val colon = body.indexOf(':')
                        if (colon >= 0) {
                            val key = body.substring(0, colon).trim(' ', '\t')
                            val value = body.substring(colon + 1).trim(' ', '\t')
                            // The file has two "Nuclide:" keys (target, then residual); keep both.
                            if (key == "Nuclide" && meta.containsKey("Nuclide")) meta["Residual nuclide"] = value else meta[key] = value
                        }
                    }
                    continue
                }
                if (columns.isEmpty()) continue
                val f = line.split(' ', '\t').filter { it.isNotEmpty() }
                if (f.size < 4) continue
                val e = parseNumber(f[0]) ?: continue
                val y = parseNumber(f[2])
                if (y == null || !y.isFinite()) { missing++; continue }
                val de = parseNumber(f[1])?.takeIf { it.isFinite() && it > 0 }?.let { it * eUncScale }
                val dy = parseNumber(f[3])?.takeIf { it.isFinite() && it > 0 }?.let { it * yUncScale }
                points.add(Point(e * eScale, de, y * yScale, dy))
            }
            if (columns.isEmpty()) throw ParseError.NoColumns()
            if (points.isEmpty()) throw ParseError.NoData()

            val level = meta["Level energy"]?.let { s ->
                val p = s.split(' ').filter { it.isNotEmpty() }
                val v = p.firstOrNull()?.let { parseNumber(it) } ?: return@let null
                v * (runCatching { energyUnit(if (p.size > 1) p[1] else "MeV") }.getOrNull() ?: 1000.0)
            }
            return ExforTable(
                quantity, frame, qualifier, points.sortedBy { it.energy }, missing,
                title = meta["Title"] ?: "", reactionCode = meta["Reaction code"] ?: "",
                residual = meta["Residual nuclide"] ?: "", levelEnergy = level,
                firstAuthor = meta["First author"] ?: "", year = meta["Year"] ?: "",
                reference = meta["Reference"] ?: "", institute = meta["Institute"] ?: "",
                facility = meta["Facility"] ?: "", entryID = meta["Entry id"] ?: "",
            )
        }

        /** "E_in_lab(MeV)" → "MeV" */
        private fun unitOf(column: String): String {
            val o = column.indexOf('(')
            val c = column.lastIndexOf(')')
            return if (o < 0 || c < 0 || o >= c) "" else column.substring(o + 1, c)
        }

        /** keV per unit. */
        fun energyUnit(u: String): Double = when (u.uppercase()) {
            "EV" -> 1e-3
            "KEV" -> 1.0
            "MEV" -> 1e3
            "GEV" -> 1e6
            else -> throw ParseError.UnsupportedUnit(u)
        }

        /** Barn per unit for σ; for "σ-unit*energy-unit" an S factor in keV b per unit. */
        fun dataUnit(u: String): Pair<Quantity, Double> {
            val parts = u.uppercase().split('*').filter { it.isNotEmpty() }
            fun barn(s: String): Double = when (s) {
                "B" -> 1.0
                "MB" -> 1e-3
                "MUB", "MICRO-B", "UB" -> 1e-6
                "NB" -> 1e-9
                "PB" -> 1e-12
                else -> throw ParseError.UnsupportedUnit(u)
            }
            return when (parts.size) {
                1 -> Quantity.CROSS_SECTION to barn(parts[0])
                2 -> Quantity.S_FACTOR to barn(parts[0]) * energyUnit(parts[1])
                else -> throw ParseError.UnsupportedUnit(u)
            }
        }

        private val decimal = Regex("""[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?""")

        /**
         * A number as Swift's Double(String) reads it in these tables: decimal or scientific notation, and "nan",
         * "inf", "infinity" in any case (Java's parser rejects "NAN" and accepts suffixes such as "1d").
         */
        internal fun parseNumber(s: String): Double? {
            val body = s.removePrefix("+").removePrefix("-")
            val sign = if (s.startsWith("-")) -1.0 else 1.0
            when (body.lowercase()) {
                "nan" -> return Double.NaN
                "inf", "infinity" -> return sign * Double.POSITIVE_INFINITY
            }
            return if (decimal.matches(s)) s.toDoubleOrNull() else null
        }
    }
}

// endregion

/** Lines without terminators, empty lines dropped (as Swift's split(whereSeparator: \.isNewline)). */
internal fun splitLines(text: String): List<String> = text.split('\n', '\r').filter { it.isNotEmpty() }
