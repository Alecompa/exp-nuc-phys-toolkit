package org.gamow.core

import kotlin.math.abs
import kotlin.math.ln

/** A ground state or isomer from NUBASE2020: half-life, Jπ, decay modes, abundance. Port of NucPhysKit.NuclearState. */
data class NuclearState(
    val z: Int, val a: Int, val state: Int,
    val excitation: Double, val excitationIsEstimated: Boolean,
    /** Seconds; +∞ for stable, null when unknown. */
    val halfLife: Double?, val halfLifeUncertainty: Double?, val halfLifeText: String,
    val spinParity: String, val spinParityIsEstimated: Boolean,
    val decayModes: List<DecayMode>,
    /** Natural abundance, %. */
    val abundance: Double?,
) {
    val id: Int get() = (z * 1000 + a) * 10 + state
    val isStable: Boolean get() = halfLife == Double.POSITIVE_INFINITY
    val isRadioactive: Boolean get() = halfLife?.let { it.isFinite() && it > 0 } ?: false

    val label: String
        get() {
            val sym = Elements.symbol(z) ?: "?"
            val mark = when (state) { 0 -> ""; 1 -> "ᵐ"; 2 -> "ⁿ"; else -> "ᵐ" + Superscript.digits(state) }
            return if (z == 0 && a == 1) "n" else Superscript.digits(a) + mark + sym
        }
    val plainLabel: String
        get() {
            val mark = when (state) { 0 -> ""; 1 -> "m"; 2 -> "n"; else -> "m$state" }
            return "$a$mark${Elements.symbol(z) ?: "?"}"
        }
    val decayConstant: Double? get() = halfLife?.let { if (it == Double.POSITIVE_INFINITY) 0.0 else ln(2.0) / it }
}

/** A decay mode as NUBASE gives it ("B-=100", "EC+B+=3.4 4", "A?"). */
data class DecayMode(val code: String, val relation: String, val branch: Double?, val uncertainty: String?) {
    val name: String
        get() = listOf("B-" to "β⁻", "B+" to "β⁺", "EC" to "ε", "2B" to "2β", "A" to "α").fold(code) { s, (a, b) -> s.replace(a, b) }
    val text: String
        get() {
            val rel = when (relation) { "=" -> ""; "~" -> "≈ "; "<" -> "< "; ">" -> "> "; "?" -> "?"; else -> "$relation " }
            val b = branch ?: return "$name $rel".trim()
            // Plain decimals with up to 6 significant digits, as the Swift app shows them ("0.0000544").
            val decimals = if (b == 0.0) 0 else (5 - kotlin.math.floor(kotlin.math.log10(abs(b))).toInt()).coerceIn(0, 20)
            val v = formatFixed(b, decimals).let { if ('.' in it) it.trimEnd('0').trimEnd('.') else it }
            return "$name $rel$v %"
        }

    companion object {
        fun parse(raw: String): DecayMode {
            val s = raw.trim()
            val r = s.indexOfFirst { it in "=<>~?" }
            if (r < 0) return DecayMode(s, "", null, null)
            val rest = s.substring(r)
            val rel = rest.takeWhile { it in "=<>~?" }
            val fields = rest.drop(rel.length).split(' ').filter { it.isNotEmpty() }
            return DecayMode(s.substring(0, r), rel, fields.firstOrNull()?.replace("#", "")?.toDoubleOrNull(), fields.getOrNull(1))
        }
    }
}

/** NUBASE2020 (Kondev et al., Chin. Phys. C 45, 030001 (2021)). */
class Nubase(val states: List<NuclearState>) {
    private val index = states.groupBy { it.z * 1000 + it.a }

    fun states(z: Int, a: Int): List<NuclearState> = index[z * 1000 + a] ?: emptyList()
    fun groundState(z: Int, a: Int): NuclearState? = states(z, a).firstOrNull { it.state == 0 }

    /** "60Co", "166mHo", "26mAl", "178m2Hf", "Co-60". */
    fun state(named: String): NuclearState? {
        var s = named.trim()
        var level = 0
        val m = Regex("^(\\d+)(m\\d?|n)([A-Za-z]+)$").matchEntire(s)
        if (m != null) {
            val digits = m.groupValues[1]
            val rest = s.drop(digits.length)
            if (rest.startsWith("n") && Elements.z(rest) == null) { level = 2; s = digits + rest.drop(1) }
            else if (rest.startsWith("m") && Elements.z(rest) == null) {
                val tail = rest.drop(1)
                if (tail.firstOrNull()?.isDigit() == true) { level = tail[0].digitToInt(); s = digits + tail.drop(1) }
                else { level = 1; s = digits + tail }
            }
        }
        val (z, a) = NuclideNotation.parse(s) ?: return null
        return states(z, a).firstOrNull { it.state == level }
    }

    companion object {
        val nubase2020: Nubase by lazy { parse(readResourceText("nubase2020.csv")) }

        fun parse(csv: String): Nubase {
            val list = ArrayList<NuclearState>(5700)
            for (line in csv.lineSequence().drop(1)) {
                if (line.isBlank()) continue
                val f = fields(line)
                if (f.size < 11) continue
                val z = f[0].toIntOrNull() ?: continue
                val a = f[1].toIntOrNull() ?: continue
                val st = f[2].toIntOrNull() ?: continue
                val hl: Double? = when { f[5].isEmpty() -> null; f[5] == "-1" -> Double.POSITIVE_INFINITY; else -> f[5].toDoubleOrNull() }
                var jpi = f[8].split(' ').firstOrNull() ?: ""
                val estimated = '#' in jpi
                jpi = jpi.replace("*", "").replace("#", "")
                val modes = if (f[9].isEmpty()) emptyList() else f[9].split(';').map { DecayMode.parse(it) }
                list.add(NuclearState(z, a, st, f[3].toDoubleOrNull() ?: 0.0, f[4] == "1", hl, f[6].toDoubleOrNull(), f[7],
                    jpi, estimated, modes, f[10].toDoubleOrNull()))
            }
            return Nubase(list)
        }

        /** Splits a CSV line, honouring double quotes. */
        fun fields(line: String): List<String> {
            val out = ArrayList<String>(); val cur = StringBuilder(); var quoted = false
            for (c in line) {
                when {
                    c == '"' -> quoted = !quoted
                    c == ',' && !quoted -> { out.add(cur.toString()); cur.clear() }
                    else -> cur.append(c)
                }
            }
            out.add(cur.toString())
            return out
        }
    }
}

/** Half-lives in readable units. */
object HalfLifeFormat {
    const val YEAR = 365.2422 * 86400.0
    private val table = listOf(1e9 * YEAR to "Gy", 1e6 * YEAR to "My", 1e3 * YEAR to "ky", YEAR to "y", 86400.0 to "d",
        3600.0 to "h", 60.0 to "min", 1.0 to "s", 1e-3 to "ms", 1e-6 to "µs", 1e-9 to "ns", 1e-12 to "ps", 1e-15 to "fs", 1e-18 to "as")
    fun unit(seconds: Double): Pair<Double, String> = table.firstOrNull { abs(seconds) >= it.first } ?: table.last()
}
