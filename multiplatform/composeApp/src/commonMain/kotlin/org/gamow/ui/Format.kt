package org.gamow.ui

import org.gamow.core.formatFixed
import org.gamow.core.formatSignificant
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.pow

/** Number formatting shared by all screens. */
object Fmt {
    fun fixed(x: Double, decimals: Int): String = if (x.isFinite()) formatFixed(x, decimals) else "—"

    /** Significant digits without exponent noise: 1234.5, 0.0123, 1.23×10⁻⁷. */
    fun sig(x: Double, digits: Int = 4): String {
        if (!x.isFinite()) return "—"
        if (x == 0.0) return "0"
        val a = abs(x)
        if (a >= 1e-3 && a < 1e6) {
            val decimals = (digits - 1 - floor(log10(a)).toInt()).coerceIn(0, 10)
            return formatFixed(x, decimals)
        }
        val e = floor(log10(a)).toInt()
        val m = x / 10.0.pow(e)
        return formatSignificant(m, digits) .trimEnd('0').trimEnd('.') + "×10" + org.gamow.core.Superscript.string(e.toString())
    }

    /** Editable text for a number: up to 7 significant digits, no trailing zeros, e-notation when large or small. */
    fun input(x: Double): String {
        if (!x.isFinite()) return ""
        if (x == 0.0) return "0"
        val a = abs(x)
        if (a >= 1e-3 && a < 1e7) {
            val s = fixed(x, (6 - floor(log10(a)).toInt()).coerceIn(0, 9))
            return if ('.' in s) s.trimEnd('0').trimEnd('.') else s
        }
        return formatSignificant(x, 7).replace(Regex("0+e"), "e").replace(".e", "e")
    }

    /** keV with sensible decimals. */
    fun keV(x: Double): String = when {
        !x.isFinite() -> "—"
        abs(x) >= 1e4 -> fixed(x, 1)
        abs(x) >= 100 -> fixed(x, 2)
        else -> fixed(x, 3)
    }

    /** Cross section with a barn prefix: (value, unit). */
    fun crossSection(b: Double): Pair<String, String> {
        val units = listOf(1.0 to "b", 1e-3 to "mb", 1e-6 to "µb", 1e-9 to "nb", 1e-12 to "pb", 1e-15 to "fb")
        val u = units.firstOrNull { abs(b) >= it.first } ?: units.last()
        return sig(b / u.first, 4) to u.second
    }
}
