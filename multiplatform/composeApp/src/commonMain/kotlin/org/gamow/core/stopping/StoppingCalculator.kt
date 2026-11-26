package org.gamow.core.stopping

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.round
import kotlin.math.sqrt

enum class RangeError { NEGATIVE_VARIANCE, ENERGY_TOO_HIGH, INVALID_ENERGIES }

class RangeException(val error: RangeError) : Exception("range calculation failed: $error")

/**
 * Stopping powers, ranges and energy loss of an ion in a target, following SRIM-2013 as reconstructed by LunaSRIM
 * (port of NucPhysKit's StoppingCalculator.swift). Stopping cross sections are in eV/(10¹⁵ atoms/cm²), energies in
 * keV, lengths in Å.
 */
class StoppingCalculator(val ion: StoppingIon, val target: StoppingTarget, private val data: SRIMData = SRIMData.shared) {

    data class Stopping(val electronic: Double, val nuclear: Double) {
        val total: Double get() = electronic + nuclear
    }

    /**
     * Bragg-rule stopping with the compound correction applied once (SR tables, TRIM, energy loss); nuclear stopping
     * with SRIM's pair coefficients. Throws [StoppingException] above ≈ 5.9 GeV/u.
     */
    fun stopping(energy: Double): Stopping {
        var se = 0.0
        var sn = 0.0
        for ((c, f) in target.components.zip(target.fractions)) {
            se += f * SRIMStopping.electronic(ion.z, ion.mass, c.z, energy, target.isGas, target.compoundCorrection, data)
            sn += f * SRIMStopping.nuclear(ion.z, ion.mass, c.z, c.mass, energy, data)
        }
        return Stopping(se, sn)
    }

    /** The SR module's list mode, which applies the compound correction a second time below 10 MeV. */
    fun listModeStopping(energy: Double): Stopping {
        val s = stopping(energy)
        val corr = target.compoundCorrection
        if (!(energy < 10_000 && corr != 1.0 && corr != 0.0)) return s
        return Stopping(s.electronic * SRIMStopping.fade(corr, energy / ion.mass, 1), s.nuclear)
    }

    /** Converts a stopping cross section (eV/(10¹⁵ atoms/cm²)) to `unit`. */
    fun convert(s: Double, unit: StoppingUnit): Double = s * unit.factor(ion, target)

    // Range tables (SR module)

    data class RangeRow(
        /** keV */
        val energy: Double,
        /** eV/(10¹⁵ atoms/cm²) */
        val electronic: Double,
        /** eV/(10¹⁵ atoms/cm²), ZBL universal form as in SRModule.exe's tables */
        val nuclear: Double,
        /** Å */
        val projectedRange: Double,
        /** Å */
        val longitudinalStraggling: Double,
        /** Å */
        val lateralStraggling: Double,
    )

    /**
     * SRIM's stopping and range table between `emin` and `emax` (keV), 26 energies per decade. PRAL-type moment
     * integration (Biersack) as in SRModule.exe; see LunaSRIM docs/physics.md §4. Throws [RangeException].
     */
    fun rangeTable(emin: Double, emax: Double): List<RangeRow> {
        val lo0 = min(emin, emax)
        val hi0 = max(emin, emax)
        if (!(hi0 > 0)) throw RangeException(RangeError.INVALID_ENERGIES)
        val m = MANTISSA
        val comps = target.components
        val frac = target.fractions
        val z1 = ion.z
        val m1 = ion.mass
        val meanMass = target.meanMass

        // Energy grid (keV), 1-based like SRModule.exe.
        val grid = ArrayList<Double>().apply { add(0.0) }
        var i = 1
        while (i <= 1000) {
            val j = (i - 1) % 26 + 1
            val k = ((i - 1) / 26).toDouble() - 3
            grid.add(m[j] * 10.0.pow(k))
            if (grid[i] > hi0) break
            i += 1
        }
        val n = min(i, 1000)

        // Electronic stopping on the grid, eV/Å (N with 0.60223).
        val conv = 0.60223 * target.density / meanMass
        val se = DoubleArray(n + 1)
        for ((k, c) in comps.withIndex()) {
            for (ii in 1..n) {
                val s = try {
                    SRIMStopping.electronic(z1, m1, c.z, grid[ii], target.isGas, target.compoundCorrection, data) * 10
                } catch (e: StoppingException) {
                    throw RangeException(RangeError.ENERGY_TOO_HIGH)
                }
                se[ii] += frac[k] * s
            }
        }
        for (ii in 1..n) se[ii] *= conv

        // Nuclear stopping and its second moment per element (universal ZBL form).
        val pi = 3.1415926
        val nDensity = target.density * 0.6023 / meanMass
        val a = DoubleArray(comps.size)
        val g = DoubleArray(comps.size)
        val epsf = DoubleArray(comps.size)
        val snf = DoubleArray(comps.size)
        var sumA = 0.0
        var sumG = 0.0
        for ((k, c) in comps.withIndex()) {
            val ak = c.mass / m1
            a[k] = ak
            sumA += ak * frac[k]
            val gk = 4 * ak / (1 + ak).pow(2.0)
            g[k] = gk
            sumG += gk * frac[k]
            val sc = 0.4685 / (z1.toDouble().pow(0.23) + c.z.toDouble().pow(0.23))
            val ef = sc * ak / ((1 + ak) * z1.toDouble() * c.z.toDouble() * 14.4)
            epsf[k] = ef
            snf[k] = pi * sc * sc * gk * nDensity / ef
        }
        val sv = DoubleArray(comps.size)
        val st = DoubleArray(comps.size)
        fun nuclear(energy: Double, c4: Double) {
            for (k in comps.indices) {
                val eps = energy * epsf[k]
                val s = 0.5 * ln(1.1383 * eps + 1) / (eps.pow(0.21226) * 0.01321 + eps + c4 * sqrt(eps))
                sv[k] = snf[k] * s
                val t = 1 / (6.684 / eps.pow(1.0494) + 0.197 / eps.pow(1.6991) + 4)
                st[k] = g[k] * t * snf[k] / epsf[k]
            }
        }

        // Starting point at 1.1 eV: low-energy solution fixed by S_n / S_e.
        var i350 = 1
        var i1e0 = 0
        var i198 = 2
        var i214 = 0
        var en = m[i350 + 1] * 10.0.pow(i1e0.toDouble())
        nuclear(en, 0.19593)
        var sn = 0.0
        var stt = 0.0
        for (k in comps.indices) { sn += sv[k] * frac[k]; stt += st[k] * frac[k] }
        var idx = 1
        var ek = en / 1000
        while (idx < n && grid[idx] <= ek) idx += 1
        var seE = se[idx]
        val x38 = sumA / (seE / sn + 1)
        val x320 = 1 / (1 - stt / (sumG * en * sn))
        var rp = 2 * en / (sumA * sn * (1 / x38 + 1))
        var r2 = (1 + x38) * rp * rp
        var lat = r2 / (x320 / x38 + 2)

        val toCrossSection = 0.1 / conv          // eV/Å → eV/(10¹⁵ atoms/cm²), as SRModule.exe prints
        val rows = ArrayList<RangeRow>()
        var last: Double? = null
        fun append(lon0: Double, lat0: Double) {
            var lon = lon0
            var la = lat0
            if (lon < 0) {
                lon = 0.0
                if (la < 0) la = 0.0
            }
            if (!(la >= 0)) throw RangeException(RangeError.NEGATIVE_VARIANCE)
            rows.add(RangeRow(en / 1000, seE * toCrossSection, sn * toCrossSection, rp, sqrt(lon), sqrt(la / 2)))
            last = en
        }

        val steps = 50
        val eminEV = lo0 * 1000 - 0.2
        val emaxEV = hi0 * 1000
        while (true) {
            if (!(en < eminEV)) append(r2 - lat - rp * rp, lat)
            i350 = i198
            i1e0 = i214
            i198 = (i350 + 1) % 26
            if (i198 == 0) i198 = 26
            if (i198 == 1) i214 += 1
            val lo = m[i350] * 10.0.pow(i1e0.toDouble())
            var hi = m[i198] * 10.0.pow(i214.toDouble())
            if (emaxEV < hi) hi = emaxEV
            val de = (hi - lo) / steps.toDouble()
            if (!(de > 0)) break
            repeat(steps) {
                en += de
                nuclear(en, 0.19594)
                sn = 0.0
                var s310 = 0.0
                var sdc = 0.0
                var s1b0 = 0.0
                for (k in comps.indices) {
                    sn += frac[k] * sv[k]
                    s310 += frac[k] * a[k] * sv[k]
                    sdc += frac[k] * a[k] * st[k]
                    s1b0 += frac[k] * (1 - a[k]).pow(2.0) * st[k]
                }
                ek = en / 1000
                while (idx < n && grid[idx] < ek) idx += 1
                idx = min(max(idx, 2), n)
                val fr = (ek - grid[idx - 1]) / (grid[idx] - grid[idx - 1])
                seE = se[idx - 1] + fr * (se[idx] - se[idx - 1])
                val stot = sn + seE
                val x88 = 2 * s310 * en
                val xb0 = 2 * sdc
                val x204 = 4 * xb0
                val x154 = 4 * en * stot
                val x290 = de / en
                val x260 = 1 - x204 / x154
                rp = (4 * en * en - (x88 + sdc) * rp) * x290 / (x154 - xb0) + rp
                r2 += 2 * rp * de / stot
                val x108 = x154 - x204
                val x14c = 2 * x88 - s1b0
                val x178 = en * x204 * rp / stot
                lat = if (x260 >= 0.01) ((r2 - 2 * lat) * x14c - x178) * x290 / x108 + lat
                else 0.5 * r2 - en * en * rp / (x88 - 0.5 * s1b0)
            }
            if (en >= emaxEV) break
        }
        val l = last
        if (l == null || en > l) append(r2 - lat - rp * rp, lat)
        return rows
    }

    /** Projected range and stragglings at `energy` (keV). */
    fun range(energy: Double): RangeRow =
        rangeTable(energy, energy).lastOrNull() ?: throw RangeException(RangeError.INVALID_ENERGIES)

    // Energy loss and straggling through a layer

    data class EnergyLoss(
        val energyIn: Double,
        val energyOut: Double,
        val electronicLoss: Double,
        val nuclearLoss: Double,
        /** keV, one standard deviation, TRIM's straggling model (Bohr with integer mean Z₂). */
        val sigma: Double,
        /** keV, Bohr's formula with the exact mean Z₂. */
        val sigmaBohr: Double,
        /** Path length in the layer, Å. */
        val pathLength: Double,
        /** Mean energy along the path (where a thin-target cross section is effectively measured), keV. */
        val meanEnergy: Double,
        /** The ions stopped inside the layer (mean energy below 1 % of the initial energy). */
        val stopped: Boolean,
        val profile: List<Point>,
    ) {
        /** depth Å, energy keV, sigma keV (TRIM model). */
        data class Point(val depth: Double, val energy: Double, val sigma: Double)

        val energyLoss: Double get() = energyIn - energyOut
        val fwhm: Double get() = sigma * 2 * sqrt(2 * ln(2.0))
    }

    /**
     * Mean energy loss and energy straggling of ions of `energy` keV crossing `thickness` Å at `angle` degrees to the
     * layer normal (LunaSRIM `straggling.energy_loss`, Eq. 26). `sigmaIn` (keV) is the energy spread of the incoming
     * beam; the variance equation then also follows how the slope of S widens or narrows it.
     */
    fun energyLoss(energy: Double, thickness: Double, angle: Double = 0.0, sigmaIn: Double = 0.0, steps: Int = 500): EnergyLoss {
        require(energy > 0 && thickness > 0)
        val nA3 = target.atomsPerA3
        val path = thickness / cos(angle * PI / 180)
        // TRIM's integer mean Z₂ and Bohr straggling.
        val total = target.components.fold(0.0) { s, c -> s + c.stoichiometry }
        var zz = 0
        for (c in target.components) {
            zz = round(c.stoichiometry / total * c.z.toDouble() + zz.toDouble()).toInt()   // ties to even, as Swift
        }
        val zExact = target.meanZ
        val z1 = ion.z.toDouble()
        val bohr = 177 * z1 * sqrt(zz.toDouble() * nA3)
        val kLow = sqrt(3.2 * 12 * nA3 / (ion.mass * 1000) * (zz.toDouble() + z1).pow(8.0 / 3.0))
        val e2 = 14.39964
        val wBohr = 4 * PI * e2 * e2 * z1 * z1 * zExact * nA3          // eV²/Å

        fun wTrim(eKeV: Double): Double {
            val e = eKeV * 1000
            var w = kLow * e
            if (w > bohr) {
                val q = 1 - 1 / (1 + e / (ion.mass * 1000 * 931_494)).pow(2.0)
                w = bohr * ((1 / q - 0.5) / (1 / q - 1))
            }
            return w * w / 12
        }
        // eV/Å
        fun stop(e: Double): Stopping {
            val s = stopping(e)
            return Stopping(s.electronic * 10 * nA3, s.nuclear * 10 * nA3)
        }
        fun slope(e: Double): Double {
            val d = 1e-3
            return (stop(e * (1 + d)).total - stop(e * (1 - d)).total) / (2 * d * e * 1000)
        }
        fun deriv(e: Double, v: Double, vb: Double): Triple<Double, Double, Double> {
            val s = stop(e).total
            val sp = slope(e)
            return Triple(-s / 1000, wTrim(e) - 2 * sp * v, wBohr - 2 * sp * vb)
        }

        val eStop = energy * 0.01
        val h = path / steps.toDouble()
        val v0 = (max(sigmaIn, 0.0) * 1000).pow(2.0)
        var x = 0.0
        var e = energy
        var v = v0
        var vb = v0
        var lossE = 0.0
        var lossN = 0.0
        var stopped = false
        val profile = ArrayList<EnergyLoss.Point>(steps + 1)
        profile.add(EnergyLoss.Point(0.0, e, max(sigmaIn, 0.0)))
        for (step in 0 until steps) {
            val k1 = deriv(e, v, vb)
            val k2 = deriv(max(e + h / 2 * k1.first, eStop / 2), v + h / 2 * k1.second, vb + h / 2 * k1.third)
            val k3 = deriv(max(e + h / 2 * k2.first, eStop / 2), v + h / 2 * k2.second, vb + h / 2 * k2.third)
            val k4 = deriv(max(e + h * k3.first, eStop / 2), v + h * k3.second, vb + h * k3.third)
            val de = h / 6 * (k1.first + 2 * k2.first + 2 * k3.first + k4.first)
            val eNew = e + de
            if (eNew <= eStop) { stopped = true; break }
            val mid = stop(max(e + de / 2, eStop / 2))
            lossE += -de * mid.electronic / mid.total
            lossN += -de * mid.nuclear / mid.total
            v = max(v + h / 6 * (k1.second + 2 * k2.second + 2 * k3.second + k4.second), 0.0)
            vb = max(vb + h / 6 * (k1.third + 2 * k2.third + 2 * k3.third + k4.third), 0.0)
            e = eNew
            x += h
            profile.add(EnergyLoss.Point(x, e, sqrt(v) / 1000))
        }
        // Path-averaged energy (trapezoidal).
        var meanE = profile[0].energy
        if (profile.size > 1 && x > 0) {
            var s = 0.0
            for (k in 1 until profile.size) {
                s += (profile[k].depth - profile[k - 1].depth) * (profile[k].energy + profile[k - 1].energy) / 2
            }
            meanE = s / x
        }
        return EnergyLoss(energy, e, lossE, lossN, sqrt(v) / 1000, sqrt(vb) / 1000, path, meanE, stopped, profile)
    }

    companion object {
        internal val MANTISSA = doubleArrayOf(0.0, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 2.0, 2.25, 2.5, 2.75,
            3.0, 3.25, 3.5, 3.75, 4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0, 8.0, 9.0)
    }
}
