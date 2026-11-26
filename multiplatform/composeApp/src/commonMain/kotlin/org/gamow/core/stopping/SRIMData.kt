package org.gamow.core.stopping

import org.gamow.core.Elements
import org.gamow.core.readResourceText

/**
 * Per-element coefficients of SRIM-2013 (`SCOEF03.DAT`), Z = 1…92. Same column layout as NucPhysKit's SRIMData.swift
 * (recovered by LunaSRIM): 3 isotope mass, 4 atomic weight, 5 solid density, 9 gas density, 11–20 proton fit,
 * 21–30 helium fit, 31–40 lithium fit, 41–53 / 54–66 heavy-ion polynomials, 67 I (solid), 68–69 I (gas),
 * 70–80 and 81–88 shell corrections, 89–93 high-energy effective charge.
 */
class SRIMElement internal constructor(val z: Int, val symbol: String, private val c: DoubleArray) {
    private fun col(k: Int) = c[k - 2]
    private fun cols(lo: Int, hi: Int) = c.copyOfRange(lo - 2, hi - 1)

    /** Mass of the most abundant isotope, u (SRIM's default ion mass). */
    val isotopeMass = col(3)
    /** Isotope-averaged atomic weight, u (SRIM's default target mass). */
    val naturalMass = col(4)
    /** Density of the solid, g/cm³. */
    val density = col(5)
    /** Density of the gas at STP, g/cm³. */
    val gasDensity = col(9)
    internal val proton = cols(11, 20)
    internal val helium = cols(21, 30)
    internal val lithium = cols(31, 40)
    internal val ionPolynomial = cols(41, 53)
    internal val targetPolynomial = cols(54, 66)
    internal val meanExcitationSolid = col(67)
    internal val meanExcitationGas = cols(68, 69)
    internal val shellC = cols(70, 80)
    internal val shellD = cols(81, 88)
    internal val highEnergyCharge = cols(89, 93)
}

/** An entry of SRIM's compound dictionary (`Compound.dat`). */
data class SRIMCompound(
    val category: String,
    val title: String,
    val name: String,
    /** g/cm³ */
    val density: Double,
    val gas: Boolean,
    /** (Z, atom fraction) pairs, fractions normalised to 1. */
    val elements: List<List<Double>>,
) {
    val id: String get() = "$category/$name"

    /** Name without SRIM's underscores, e.g. "Water Liquid (ICRU-276)". */
    val displayName: String get() = name.replace("_", " ")

    /** "H 66.7% · O 33.3%" */
    val compositionSummary: String
        get() = elements.joinToString(" · ") { e ->
            "${Elements.symbol(e[0].toInt()) ?: "?"} ${formatSignificantDigits(e[1] * 100, 3, 3)}%"
        }
}

/** The SRIM-2013 tables bundled with the app (srim_scoef.csv, srim_snuc.csv, srim_compounds.json). */
class SRIMData(scoef: String, snuc: String, compoundsJson: String) {
    /** Index z − 1. */
    val elements: List<SRIMElement>
    val compounds: List<SRIMCompound>
    private val nuclearPairs: Map<Int, DoubleArray>

    init {
        val els = ArrayList<SRIMElement>(92)
        for (line in scoef.lineSequence()) {
            if (line.isEmpty() || line.startsWith("#")) continue
            val f = line.split(',').filter { it.isNotEmpty() }   // Swift's split drops empty fields
            if (f.size != 94) continue
            val z = f[0].toIntOrNull() ?: continue
            els.add(SRIMElement(z, f[1], DoubleArray(92) { f[it + 2].toDoubleOrNull() ?: 0.0 }))
        }
        require(els.size == 92 && els.withIndex().all { it.value.z == it.index + 1 }) { "SRIM coefficients incomplete" }
        elements = els

        val pairs = HashMap<Int, DoubleArray>()
        for (line in snuc.lineSequence()) {
            if (line.isEmpty() || line.startsWith("#")) continue
            val f = line.split(',').filter { it.isNotEmpty() }
            if (f.size != 6) continue
            val a = f[0].toIntOrNull() ?: continue
            val b = f[1].toIntOrNull() ?: continue
            pairs[100 * minOf(a, b) + maxOf(a, b)] = DoubleArray(4) { f[it + 2].toDoubleOrNull() ?: 0.0 }
        }
        nuclearPairs = pairs

        @Suppress("UNCHECKED_CAST")
        compounds = (MiniJson.parse(compoundsJson) as List<Map<String, Any?>>).map { o ->
            SRIMCompound(
                category = o["category"] as String,
                title = o["title"] as String,
                name = o["name"] as String,
                density = (o["density"] as Number).toDouble(),
                gas = o["gas"] as Boolean,
                elements = (o["elements"] as List<List<Number>>).map { p -> p.map { it.toDouble() } },
            )
        }
    }

    fun element(z: Int): SRIMElement {
        require(z in 1..92) { "SRIM covers Z = 1…92" }
        return elements[z - 1]
    }

    internal fun nuclearCoefficients(z1: Int, z2: Int): DoubleArray? = nuclearPairs[100 * minOf(z1, z2) + maxOf(z1, z2)]

    companion object {
        val shared: SRIMData by lazy {
            SRIMData(readResourceText("srim_scoef.csv"), readResourceText("srim_snuc.csv"),
                readResourceText("srim_compounds.json"))
        }
    }
}

/** Minimal JSON reader (objects → Map, arrays → List, numbers → Double, true/false, null, strings). */
internal object MiniJson {
    fun parse(text: String): Any? {
        val p = P(text)
        val v = p.value()
        p.ws()
        require(p.i == text.length) { "trailing JSON at ${p.i}" }
        return v
    }

    private class P(val s: String) {
        var i = 0
        fun ws() { while (i < s.length && s[i].isWhitespace()) i++ }
        fun value(): Any? {
            ws()
            require(i < s.length) { "unexpected end of JSON" }
            return when (val c = s[i]) {
                '{' -> obj()
                '[' -> arr()
                '"' -> str()
                't' -> lit("true", true)
                'f' -> lit("false", false)
                'n' -> lit("null", null)
                else -> if (c == '-' || c.isDigit()) num() else error("unexpected '$c' in JSON at $i")
            }
        }
        fun lit(w: String, v: Any?): Any? {
            require(s.startsWith(w, i)) { "bad JSON literal at $i" }
            i += w.length
            return v
        }
        fun num(): Double {
            val st = i
            while (i < s.length && (s[i].isDigit() || s[i] in "+-.eE")) i++
            return s.substring(st, i).toDouble()
        }
        fun str(): String {
            i++
            val b = StringBuilder()
            while (true) {
                val c = s[i++]
                when (c) {
                    '"' -> return b.toString()
                    '\\' -> {
                        when (val e = s[i++]) {
                            'n' -> b.append('\n'); 't' -> b.append('\t'); 'r' -> b.append('\r')
                            'b' -> b.append('\b'); 'f' -> b.append('\u000C')
                            'u' -> { b.append(s.substring(i, i + 4).toInt(16).toChar()); i += 4 }
                            else -> b.append(e)
                        }
                    }
                    else -> b.append(c)
                }
            }
        }
        fun obj(): Map<String, Any?> {
            i++
            val m = LinkedHashMap<String, Any?>()
            ws()
            if (s[i] == '}') { i++; return m }
            while (true) {
                ws()
                val k = str()
                ws(); require(s[i] == ':'); i++
                m[k] = value()
                ws()
                if (s[i] == ',') { i++; continue }
                require(s[i] == '}') { "bad JSON object at $i" }
                i++
                return m
            }
        }
        fun arr(): List<Any?> {
            i++
            val l = ArrayList<Any?>()
            ws()
            if (s[i] == ']') { i++; return l }
            while (true) {
                l.add(value())
                ws()
                if (s[i] == ',') { i++; continue }
                require(s[i] == ']') { "bad JSON array at $i" }
                i++
                return l
            }
        }
    }
}
