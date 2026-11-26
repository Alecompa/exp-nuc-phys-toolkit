package org.gamow.core.stopping

import org.gamow.core.Elements
import org.gamow.core.MassTable
import org.gamow.core.Superscript
import kotlin.math.abs

/** Why a formula could not be read; `message` is the text shown to the user (same wording as the Swift app). */
sealed class FormulaException(message: String) : Exception(message) {
    class Empty : FormulaException("Enter a formula, e.g. Ta2N3.")
    class UnknownSymbol(val symbol: String) : FormulaException("Unknown element “$symbol”.")
    class UnknownIsotope(val isotope: String) : FormulaException("Unknown isotope “$isotope”.")
    class UnbalancedParentheses : FormulaException("Unbalanced parentheses.")
    class Unexpected(val char: Char) : FormulaException("Unexpected “$char”.")
    class OutOfRange(val symbol: String) : FormulaException("$symbol is beyond SRIM's range (Z = 1–92).")
}

/**
 * A chemical formula with arbitrary, also fractional, stoichiometry (port of ChemicalFormula.swift).
 *
 * Syntax: element symbols with counts (`Ta2N3`, `Ti0.5Al0.5N`), groups (`Ca(OH)2`), hydrates with a leading
 * multiplier (`CuSO4·5H2O` or `CuSO4*5H2O`; a `.` between digits is a decimal point), deuterium and tritium (`D`, `T`,
 * as in `TiD2`) and isotopes in square brackets (`Ta2[17O]5`). Spaces are ignored.
 */
data class ChemicalFormula(
    /** One entry per (element, isotope), in order of first appearance. */
    val parts: List<Part>,
) {
    data class Part(
        val z: Int,
        /** Mass number for an isotopically pure entry (D, T, [17O]); null for the natural element. */
        val massNumber: Int?,
        val count: Double,
    )

    /** The formula with subscript counts and superscript mass numbers, e.g. "Ta₂N₃", "TiD₂", "Ta₂¹⁷O₅". */
    val label: String get() = parts.joinToString("") { symbol(it.z, it.massNumber) + subscriptCount(it.count) }

    companion object {
        /** Parses `text`; throws [FormulaException]. */
        fun parse(text: String): ChemicalFormula {
            val chars = text.filter { !it.isWhitespace() }
            if (chars.isEmpty()) throw FormulaException.Empty()
            val p = Parser(chars)
            val counts = p.formula()
            if (p.i != chars.length) throw FormulaException.Unexpected(chars[p.i])
            if (counts.isEmpty()) throw FormulaException.Empty()
            return ChemicalFormula(counts)
        }

        fun parseOrNull(text: String): ChemicalFormula? = try { parse(text) } catch (e: FormulaException) { null }

        internal fun symbol(z: Int, massNumber: Int?): String {
            val s = Elements.symbol(z) ?: "?"
            val a = massNumber ?: return s
            if (z == 1 && a == 2) return "D"
            if (z == 1 && a == 3) return "T"
            return Superscript.digits(a) + s
        }

        /** "" for 1, otherwise the count in subscript digits (up to 4 significant figures). */
        internal fun subscriptCount(x: Double): String {
            if (abs(x - 1) < 1e-9) return ""
            return formatSignificantDigits(x, 1, 4).map { c -> if (c in '0'..'9') '₀' + (c - '0') else c }.joinToString("")
        }
    }

    private class Parser(val chars: String) {
        var i = 0
        private val peek: Char? get() = if (i < chars.length) chars[i] else null

        private fun isSeparator(c: Char) = c == '·' || c == '*' || c == '.' || c == '•'
        private fun isAsciiDigit(c: Char) = c in '0'..'9'

        /** formula := term ( ('·' | '.' | '*') number? term )* */
        fun formula(): List<Part> {
            var out = sequence()
            // A "." left over here is a hydrate separator: decimal points were consumed by number().
            while (true) {
                val c = peek ?: break
                if (!isSeparator(c)) break
                i += 1
                val mult = number() ?: 1.0
                out = merge(out, scale(sequence(), mult))
            }
            return out
        }

        /** sequence := (element | '(' sequence ')' | '[' A Sym ']') count? */
        fun sequence(): List<Part> {
            var out = listOf<Part>()
            while (true) {
                val c = peek ?: break
                var group: List<Part>
                when {
                    c == '(' -> {
                        i += 1
                        group = sequence()
                        if (peek != ')') throw FormulaException.UnbalancedParentheses()
                        i += 1
                    }
                    c == '[' -> {
                        i += 1
                        val a = number()
                        if (a == null || a != roundHalfAway(a) || a < 1) throw FormulaException.Unexpected(peek ?: '[')
                        val sym = symbol()
                        if (peek != ']') throw FormulaException.UnbalancedParentheses()
                        i += 1
                        val z = element(sym)
                        val label = "${a.toInt()}$sym"
                        if (MassTable.ame2020.nuclide(z, a.toInt()) == null) throw FormulaException.UnknownIsotope(label)
                        group = listOf(Part(z, a.toInt(), 1.0))
                    }
                    c == ')' -> break
                    c == ']' -> throw FormulaException.UnbalancedParentheses()
                    c.isUpperCase() -> {
                        val sym = symbol()
                        group = when (sym) {
                            "D" -> listOf(Part(1, 2, 1.0))
                            "T" -> listOf(Part(1, 3, 1.0))
                            else -> listOf(Part(element(sym), null, 1.0))
                        }
                    }
                    isSeparator(c) -> break
                    else -> throw FormulaException.Unexpected(c)
                }
                number()?.let { group = scale(group, it) }
                out = merge(out, group)
            }
            return out
        }

        private fun symbol(): String {
            val c = peek
            if (c == null || !(c.isUpperCase() && c.isLetter())) throw FormulaException.Unexpected(peek ?: ' ')
            var s = c.toString()
            i += 1
            val d = peek
            if (d != null && d.isLowerCase() && d.isLetter()) { s += d; i += 1 }
            return s
        }

        private fun element(sym: String): Int {
            val z = Elements.symbols.indexOf(sym)
            if (z <= 0) throw FormulaException.UnknownSymbol(sym)
            if (z > 92) throw FormulaException.OutOfRange(sym)
            return z
        }

        /** A decimal number, or null if none starts here. "." counts as a decimal point only between digits. */
        private fun number(): Double? {
            val s = StringBuilder()
            while (peek?.let(::isAsciiDigit) == true) { s.append(chars[i]); i += 1 }
            if (peek == '.' && i + 1 < chars.length && isAsciiDigit(chars[i + 1])) {
                s.append('.'); i += 1
                while (peek?.let(::isAsciiDigit) == true) { s.append(chars[i]); i += 1 }
            } else if (s.isEmpty() && peek == '.' && i + 1 < chars.length && chars[i + 1].isDigit()) {
                // ".5" style
                s.append("0."); i += 1
                while (peek?.let(::isAsciiDigit) == true) { s.append(chars[i]); i += 1 }
            }
            return if (s.isEmpty()) null else s.toString().toDoubleOrNull()
        }

        private fun scale(parts: List<Part>, f: Double) = parts.map { Part(it.z, it.massNumber, it.count * f) }

        private fun merge(a: List<Part>, b: List<Part>): List<Part> {
            val out = a.toMutableList()
            for (p in b) {
                val k = out.indexOfFirst { it.z == p.z && it.massNumber == p.massNumber }
                if (k >= 0) out[k] = Part(p.z, p.massNumber, out[k].count + p.count) else out.add(p)
            }
            return out
        }
    }
}
