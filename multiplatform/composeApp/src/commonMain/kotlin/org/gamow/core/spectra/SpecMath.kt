package org.gamow.core.spectra

import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.round
import kotlin.math.truncate
import kotlin.random.Random

/**
 * erf and erfc for common Kotlin (no libm here): a port of fdlibm's s_erf.c (Sun Microsystems, 1993), error below
 * 1 ulp. The Swift app uses Apple's libm, which agrees to a few ulp; a bin far in a Gaussian tail, where
 * erf(b) − erf(a) cancels, can therefore differ in its leading digits from the Swift value, the bulk does not.
 */
internal object SpecMath {
    private const val ERX = 8.45062911510467529297e-01
    private const val EFX = 1.28379167095512586316e-01
    private const val EFX8 = 1.02703333676410069053e+00
    private const val PP0 = 1.28379167095512558561e-01
    private const val PP1 = -3.25042107247001499370e-01
    private const val PP2 = -2.84817495755985104766e-02
    private const val PP3 = -5.77027029648944159157e-03
    private const val PP4 = -2.37630166566501626084e-05
    private const val QQ1 = 3.97917223959155352819e-01
    private const val QQ2 = 6.50222499887672944485e-02
    private const val QQ3 = 5.08130628187576562776e-03
    private const val QQ4 = 1.32494738004321644526e-04
    private const val QQ5 = -3.96022827877536812320e-06
    private const val PA0 = -2.36211856075265944077e-03
    private const val PA1 = 4.14856118683748331666e-01
    private const val PA2 = -3.72207876035701323847e-01
    private const val PA3 = 3.18346619901161753674e-01
    private const val PA4 = -1.10894694282396677476e-01
    private const val PA5 = 3.54783043256182359371e-02
    private const val PA6 = -2.16637559486879084300e-03
    private const val QA1 = 1.06420880400844228286e-01
    private const val QA2 = 5.40397917702171048937e-01
    private const val QA3 = 7.18286544141962662868e-02
    private const val QA4 = 1.26171219808761642112e-01
    private const val QA5 = 1.36370839120290507362e-02
    private const val QA6 = 1.19844998467991074170e-02
    private const val RA0 = -9.86494403484714822705e-03
    private const val RA1 = -6.93858572707181764372e-01
    private const val RA2 = -1.05586262253232909814e+01
    private const val RA3 = -6.23753324503260060396e+01
    private const val RA4 = -1.62396669462573470355e+02
    private const val RA5 = -1.84605092906711035994e+02
    private const val RA6 = -8.12874355063065934246e+01
    private const val RA7 = -9.81432934416914548592e+00
    private const val SA1 = 1.96512716674392571292e+01
    private const val SA2 = 1.37657754143519042600e+02
    private const val SA3 = 4.34565877475229228821e+02
    private const val SA4 = 6.45387271733267880336e+02
    private const val SA5 = 4.29008140027567833386e+02
    private const val SA6 = 1.08635005541779435134e+02
    private const val SA7 = 6.57024977031928170135e+00
    private const val SA8 = -6.04244152148580987438e-02
    private const val RB0 = -9.86494292470009928597e-03
    private const val RB1 = -7.99283237680523006574e-01
    private const val RB2 = -1.77579549177547519889e+01
    private const val RB3 = -1.60636384855821916062e+02
    private const val RB4 = -6.37566443368389627722e+02
    private const val RB5 = -1.02509513161107724954e+03
    private const val RB6 = -4.83519191608651397019e+02
    private const val SB1 = 3.03380607434824582924e+01
    private const val SB2 = 3.25792512996573918826e+02
    private const val SB3 = 1.53672958608443695994e+03
    private const val SB4 = 3.19985821950859553908e+03
    private const val SB5 = 2.55305040643316442583e+03
    private const val SB6 = 4.74528541206955367215e+02
    private const val SB7 = -2.24409524465858183362e+01
    private const val TINY = 1e-300

    private fun small(x: Double): Double {
        val z = x * x
        val r = PP0 + z * (PP1 + z * (PP2 + z * (PP3 + z * PP4)))
        val s = 1 + z * (QQ1 + z * (QQ2 + z * (QQ3 + z * (QQ4 + z * QQ5))))
        return r / s
    }

    private fun middle(ax: Double): Double {
        val s = ax - 1
        val p = PA0 + s * (PA1 + s * (PA2 + s * (PA3 + s * (PA4 + s * (PA5 + s * PA6)))))
        val q = 1 + s * (QA1 + s * (QA2 + s * (QA3 + s * (QA4 + s * (QA5 + s * QA6)))))
        return p / q
    }

    /** erfc(|x|) for 1.25 ≤ |x| < 28. */
    private fun tail(ax: Double): Double {
        val s = 1 / (ax * ax)
        val r: Double
        val q: Double
        if (ax < 1 / 0.35) {
            r = RA0 + s * (RA1 + s * (RA2 + s * (RA3 + s * (RA4 + s * (RA5 + s * (RA6 + s * RA7))))))
            q = 1 + s * (SA1 + s * (SA2 + s * (SA3 + s * (SA4 + s * (SA5 + s * (SA6 + s * (SA7 + s * SA8)))))))
        } else {
            r = RB0 + s * (RB1 + s * (RB2 + s * (RB3 + s * (RB4 + s * (RB5 + s * RB6)))))
            q = 1 + s * (SB1 + s * (SB2 + s * (SB3 + s * (SB4 + s * (SB5 + s * (SB6 + s * SB7))))))
        }
        val z = Double.fromBits(ax.toRawBits() and -0x100000000L)     // low word cleared
        return exp(-z * z - 0.5625) * exp((z - ax) * (z + ax) + r / q) / ax
    }

    fun erf(x: Double): Double {
        if (x.isNaN()) return x
        if (x.isInfinite()) return if (x > 0) 1.0 else -1.0
        val ax = abs(x)
        if (ax < 0.84375) {
            if (ax < 3.725290298461914e-9) return if (ax < 2.848094538889218e-306) 0.125 * (8.0 * x + EFX8 * x) else x + EFX * x
            return x + x * small(x)
        }
        if (ax < 1.25) {
            val pq = middle(ax)
            return if (x >= 0) ERX + pq else -ERX - pq
        }
        if (ax >= 6) return if (x >= 0) 1 - TINY else TINY - 1
        val r = tail(ax)
        return if (x >= 0) 1 - r else r - 1
    }

    fun erfc(x: Double): Double {
        if (x.isNaN()) return x
        if (x.isInfinite()) return if (x > 0) 0.0 else 2.0
        val ax = abs(x)
        if (ax < 0.84375) {
            if (ax < 1.3877787807814457e-17) return 1 - x
            val y = small(x)
            return if (x < 0.25) 1 - (x + x * y) else 0.5 - (x * y + (x - 0.5))
        }
        if (ax < 1.25) {
            val pq = middle(ax)
            return if (x >= 0) 1 - ERX - pq else 1 + (ERX + pq)
        }
        if (ax < 28) {
            if (x < -6) return 2 - TINY
            val r = tail(ax)
            return if (x > 0) r else 2 - r
        }
        return if (x > 0) TINY * TINY else 2 - TINY
    }

    /** Swift's `rounded()`: to nearest, ties away from zero. */
    fun roundHalfAway(x: Double): Double {
        val t = truncate(x)
        return if (abs(x - t) == 0.5) t + (if (x > 0) 1.0 else -1.0) else round(x)
    }

    private val decimal = Regex("^[+-]?(\\d+\\.?\\d*|\\.\\d+)([eE][+-]?\\d+)?$")

    /** Swift's `Double(String)` for decimal text: no surrounding spaces, no Java "d"/"f" suffixes; inf and nan words. */
    fun parseDouble(s: String): Double? {
        if (decimal.matches(s)) return s.toDoubleOrNull()
        val body = s.removePrefix("+").removePrefix("-")
        val sign = if (s.startsWith("-")) -1.0 else 1.0
        return when (body.lowercase()) {
            "inf", "infinity" -> sign * Double.POSITIVE_INFINITY
            "nan" -> Double.NaN
            else -> null
        }
    }

    /** Swift's `Int(String)`: optional sign and decimal digits only. */
    fun parseInt(s: String): Int? = if (Regex("^[+-]?\\d+$").matches(s)) s.toIntOrNull() else null

    /**
     * Swift's `description` of a Double: shortest round-trip digits, "1e-05" / "1e+16" outside 1e-4 ≤ |x| < 2^53
     * (Swift switches at 1e16), otherwise plain with at least one decimal ("2.0").
     */
    fun swiftDescription(x: Double): String {
        if (x.isNaN()) return "nan"
        if (x.isInfinite()) return if (x > 0) "inf" else "-inf"
        if (x == 0.0) return if (1.0 / x < 0) "-0.0" else "0.0"
        // Java's shortest digits, re-rendered.
        val j = abs(x).toString()
        val mantissa: String
        var exp10: Int
        if ('E' in j) {
            mantissa = j.substringBefore('E'); exp10 = j.substringAfter('E').toInt()
        } else {
            mantissa = j; exp10 = 0
        }
        val intPart = mantissa.substringBefore('.')
        val frac = mantissa.substringAfter('.', "")
        var digits = (intPart + frac).trimStart('0')
        val lead = (intPart + frac).length - (intPart + frac).trimStart('0').length
        // value = 0.d1d2... × 10^(intPart.length − lead + exp10)
        exp10 += intPart.length - lead
        digits = digits.trimEnd('0').ifEmpty { "0" }
        val e = exp10 - 1                                       // scientific exponent of d1.d2...
        val sign = if (x < 0) "-" else ""
        return if (e < -4 || e >= 16) {
            val m = if (digits.length == 1) digits else digits[0] + "." + digits.substring(1)
            val es = if (e < 0) "-" else "+"
            val ea = abs(e).toString().padStart(2, '0')
            "$sign${m}e$es$ea"
        } else if (e < 0) {
            sign + "0." + "0".repeat(-e - 1) + digits
        } else if (digits.length <= e + 1) {
            sign + digits + "0".repeat(e + 1 - digits.length) + ".0"
        } else {
            sign + digits.substring(0, e + 1) + "." + digits.substring(e + 1)
        }
    }

    /** A random identifier (the Swift structs use UUIDs; only uniqueness matters). */
    fun newId(): String {
        val hex = "0123456789abcdef"
        return (0 until 32).map { hex[Random.nextInt(16)] }.joinToString("")
    }
}
