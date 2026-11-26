package org.gamow.core.stopping

import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

enum class StoppingError { ENERGY_TOO_HIGH }

class StoppingException(val error: StoppingError) :
    Exception("SRIM's phase correction overflows above ≈ 5.9 GeV/u")

/**
 * SRIM-2013 stopping powers of an ion in one element, ported from NucPhysKit's SRIMStopping.swift (itself from
 * LunaSRIM's `stopping.py`, which reconstructs SRModule.exe / TRIM.exe). Energies in keV (or keV/u where stated);
 * stopping cross sections in eV/(10¹⁵ atoms/cm²). Equation numbers refer to LunaSRIM's docs/physics.md.
 */
object SRIMStopping {
    /** Noble gases: no phase correction. */
    internal val nobleGases = setOf(2, 10, 18, 36, 54, 86)
    /** Elements that are gaseous in their natural state. */
    internal val gasElements = setOf(1, 2, 7, 8, 9, 10, 17, 18, 35, 36, 53, 54, 85, 86)
    internal const val PHASE_FACTOR_VALUE = 0.92

    /** True for elements SRIM treats as gaseous in their natural state. */
    fun isNaturalGas(z: Int): Boolean = z in gasElements

    // Electronic stopping

    private fun polynomial(c: DoubleArray, x: Double): Double {
        var s = 0.0
        var p = 1.0
        for (v in c) { s += v * p; p *= x }
        return s
    }

    /** The ten-parameter SRIM fit, Eq. (3). */
    private fun fit(c: DoubleArray, e: Double): Double {
        val low = c[0] * e.pow(c[1]) + c[2] * e.pow(c[3]) + c[8] * sqrt(e)
        val high = (c[4] / e.pow(c[5])) * (ln(c[6] / e + c[7] * e) + c[9] / e.pow(0.2))
        return low * high / (low + high)
    }

    /** Bethe formula with shell, Barkas and Bloch terms, Eqs. (4)–(6). `e` in keV/u. */
    internal fun bethe(z1: Int, t: SRIMElement, e: Double, gas: Boolean): Double {
        val z1d = z1.toDouble()
        val z2 = t.z.toDouble()
        val beta2 = 1 - 1 / (1 + e / 931_494).pow(2.0)
        val lx = ln(e / 1000)
        val shellD = if (gas) 0.0 else polynomial(t.shellD, lx)
        val shellC = polynomial(t.shellC, lx)
        val meanI: Double
        val q: Double
        if (gas) {
            meanI = if (z1 == 1) t.meanExcitationGas[0] else t.meanExcitationGas[1]
            q = 1.35 / e.pow(0.4)
        } else {
            meanI = t.meanExcitationSolid
            q = 1.5 / e.pow(0.4) + 45_000 / (z2 * e.pow(1.6))
        }
        val barkas = (z1d * (0.001 * e) * q) / (0.001 * e + q)
        val y = (z1d / 137.036).pow(2.0) / beta2
        val bloch = -y * (1.20206 - y * (1.042 - 0.8549 * y + 0.343 * y * y))
        val l = ln(1_022_000 * beta2 / (1 - beta2)) - beta2 - shellD - shellC - ln(meanI) + barkas + bloch
        return z1d * z1d * z2 / (beta2 * 1961.16) * l
    }

    /** H, He, Li ions: fit between 2 keV/u and `emax`, Bethe above 1.2·emax, linear in between. */
    private fun lightIon(coef: DoubleArray, z1: Int, t: SRIMElement, e: Double, emax: Double, gas: Boolean): Double {
        val emin = 2.0
        val ehigh = emax * 1.2
        if (e > ehigh) return bethe(z1, t, e, gas)
        val s = fit(coef, min(max(e, emin), emax))
        if (e > emax) {
            val sb = bethe(z1, t, ehigh, gas)
            return s + (sb - s) * (e - emax) / (ehigh - emax)
        }
        if (e < emin) return s * sqrt(e / emin)
        return s
    }

    /** High-energy effective charge of heavy ions, Eq. (8). */
    private fun highEnergyCharge(hi: DoubleArray, e: Double): Double {
        val d = log10(e) - hi[1]
        val w = if (d >= 0) hi[3] else hi[2]
        return hi[0] + (1 - hi[0]) / (exp(-d / w) + 1) + hi[4] * exp(-abs(1.3 + hi[1] - log10(e)))
    }

    /** Electronic stopping of ion `z1` in pure element `z2`, without phase correction. `ePerU` in keV/u. */
    fun electronicElement(z1: Int, z2: Int, ePerU: Double, gas: Boolean = false, data: SRIMData = SRIMData.shared): Double {
        val e = ePerU
        val t = data.element(z2)
        if (e > 1e7) return 0.0
        return when (z1) {
            1 -> lightIon(t.proton, 1, t, e, 1000.0, gas)
            2 -> lightIon(t.helium, 2, t, e, 2000.0, gas)
            3 -> lightIon(t.lithium, 3, t, e, 2000.0, gas)
            else -> {
                // Heavy ions: helium stopping scaled with ion and target polynomials in ln E, Eq. (7).
                val emin = 2.0
                val emax = 30_000.0
                val ec = min(max(e, emin), emax)
                val lne = ln(ec)
                val ion = data.element(z1)
                val s = lightIon(t.helium, 2, t, ec, 2000.0, gas) *
                    polynomial(ion.ionPolynomial, lne) * (z1 * z1).toDouble() / 4 * polynomial(t.targetPolynomial, lne)
                when {
                    e < emin -> s * sqrt(e / emin)
                    e > emax -> {
                        val hi = highEnergyCharge(ion.highEnergyCharge, e) * bethe(2, t, e, gas)
                        val lo = highEnergyCharge(ion.highEnergyCharge, emax) * bethe(2, t, emax, gas)
                        s * hi / lo
                    }
                    else -> s
                }
            }
        }
    }

    /** SRIM's gas/solid phase factor (0.92 for a gaseous element in a solid, 1/0.92 the other way). */
    internal fun phaseFactor(z2: Int, gas: Boolean): Double {
        if (z2 in nobleGases) return 1.0
        val natural = z2 in gasElements
        if (natural == gas) return 1.0
        return if (natural) PHASE_FACTOR_VALUE else 1 / PHASE_FACTOR_VALUE
    }

    /** Correction factor fully applied at low velocity, fading out at high velocity, Eq. (9). */
    internal fun fade(factor: Double, ePerU: Double, z1: Int): Double {
        val c = if (z1 == 1) 7.0 else 4.0
        val x = 1.48 * (sqrt(ePerU / 25) - c)
        if (x > 709.782712893384) throw StoppingException(StoppingError.ENERGY_TOO_HIGH)
        if (x > 700) return 1.0
        return 1 + (factor - 1) / (1 + exp(x))
    }

    /**
     * Electronic stopping of an ion (z1, m1 in u, energy in keV) in element z2 including the phase correction and the
     * per-element part of the compound correction. Throws [StoppingException] above ≈ 5.9 GeV/u.
     */
    fun electronic(z1: Int, m1: Double, z2: Int, energy: Double, gas: Boolean = false, correction: Double = 1.0,
                   data: SRIMData = SRIMData.shared): Double {
        val e = energy / m1
        val s = electronicElement(z1, z2, e, gas, data)
        val corr = if (correction <= 0) 1.0 else correction
        return s * fade(phaseFactor(z2, gas) * corr, e, z1)
    }

    // Nuclear stopping

    /** ZBL reduced energy, Eq. (11). Energy in keV. */
    fun reducedEnergy(z1: Int, m1: Double, z2: Int, m2: Double, energy: Double): Double =
        energy * 32.53 * m2 / ((z1 * z2).toDouble() * (m1 + m2) * (z1.toDouble().pow(0.23) + z2.toDouble().pow(0.23)))

    private fun nuclearPrefactor(z1: Int, m1: Double, z2: Int, m2: Double): Double =
        8.462 * (z1 * z2).toDouble() * m1 / ((m1 + m2) * (z1.toDouble().pow(0.23) + z2.toDouble().pow(0.23)))

    /** Nuclear stopping with SRIM-2013's pair coefficients (`SNUC03.dat`), Eqs. (12)–(13). */
    fun nuclear(z1: Int, m1: Double, z2: Int, m2: Double, energy: Double, data: SRIMData = SRIMData.shared): Double {
        val eps = reducedEnergy(z1, m1, z2, m2, energy)
        val sn = if (eps > 30) {
            ln(eps) / (2 * eps)
        } else {
            val c = data.nuclearCoefficients(z1, z2) ?: doubleArrayOf(1.1383, 0.01321, 0.21226, 0.19593)
            0.5 * ln(1 + c[0] * eps) / (eps + c[1] * eps.pow(c[2]) + c[3] * sqrt(eps))
        }
        return sn * nuclearPrefactor(z1, m1, z2, m2)
    }

    /** ZBL universal nuclear stopping. */
    fun universalNuclear(z1: Int, m1: Double, z2: Int, m2: Double, energy: Double): Double {
        val eps = reducedEnergy(z1, m1, z2, m2, energy)
        val sn = if (eps > 30) ln(eps) / (2 * eps)
        else ln(1 + 1.1383 * eps) / (2 * (eps + 0.01321 * eps.pow(0.21226) + 0.19593 * sqrt(eps)))
        return sn * nuclearPrefactor(z1, m1, z2, m2)
    }
}
