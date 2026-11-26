package org.gamow.core

import kotlin.math.*

/**
 * A two-body channel of charged particles (e.g. p + ¹²C). Energies keV (c.m. unless stated), lengths fm,
 * masses in u (atomic masses). Port of NucPhysKit.ChargedChannel.
 */
data class ChargedChannel(val z1: Int, val a1: Int, val m1: Double, val z2: Int, val a2: Int, val m2: Double, val label: String = "") {
    constructor(projectile: Nuclide, target: Nuclide) : this(
        projectile.z, projectile.a, projectile.atomicMass / PhysicalConstants.ATOMIC_MASS_UNIT,
        target.z, target.a, target.atomicMass / PhysicalConstants.ATOMIC_MASS_UNIT,
        "${projectile.label} + ${target.label}",
    )

    val isCharged: Boolean get() = z1 > 0 && z2 > 0
    /** Reduced mass, u. */
    val reducedMass: Double get() = m1 * m2 / (m1 + m2)
    /** μc², keV. */
    val reducedMassEnergy: Double get() = reducedMass * PhysicalConstants.ATOMIC_MASS_UNIT

    fun labEnergy(cm: Double): Double = cm * (m1 + m2) / m2
    fun cmEnergy(lab: Double): Double = lab * m2 / (m1 + m2)

    /** Sommerfeld parameter η = Z₁Z₂e²/(ħv). */
    fun sommerfeld(e: Double): Double = z1 * z2 * PhysicalConstants.FINE_STRUCTURE / sqrt(2 * e / reducedMassEnergy)

    /** Gamow energy E_G = 2μc²(παZ₁Z₂)², keV. */
    val gamowEnergy: Double get() = 2 * reducedMassEnergy * (PI * PhysicalConstants.FINE_STRUCTURE * z1 * z2).pow(2)

    fun gamowFactor(e: Double): Double = exp(-2 * PI * sommerfeld(e))
    fun waveNumber(e: Double): Double = sqrt(2 * reducedMassEnergy * e) / PhysicalConstants.HBAR_C
    fun radius(r0: Double): Double = r0 * (a1.toDouble().pow(1.0 / 3) + a2.toDouble().pow(1.0 / 3))
    fun coulombBarrier(radius: Double): Double = z1 * z2 * PhysicalConstants.COULOMB_CONSTANT / radius

    data class GamowWindow(val peak: Double, val width: Double, val kT: Double) {
        val tau: Double get() = 3 * peak / kT
        val lower: Double get() = max(0.0, peak - width / 2)
        val upper: Double get() = peak + width / 2
    }

    /** E₀ = (√E_G kT/2)^⅔, Δ = 4√(E₀kT/3). */
    fun gamowWindow(t9: Double): GamowWindow {
        val kT = kT(t9)
        val e0 = (sqrt(gamowEnergy) * kT / 2).pow(2.0 / 3)
        return GamowWindow(e0, 4 / sqrt(3.0) * sqrt(e0 * kT), kT)
    }

    fun gamowIntegrand(e: Double, t9: Double): Double = if (e <= 0) 0.0 else exp(-e / kT(t9) - sqrt(gamowEnergy / e))

    /** Wigner limit 3ħ²/(2μa²), keV. */
    fun wignerLimit(radius: Double): Double =
        3 * PhysicalConstants.HBAR_C * PhysicalConstants.HBAR_C / (2 * reducedMassEnergy * radius * radius)

    /** σ = S/E · exp(−2πη), barn, for S in keV b. */
    fun crossSection(sFactor: Double, energy: Double): Double = sFactor / energy * gamowFactor(energy)
    /** S = σ E exp(2πη), keV b. */
    fun sFactor(crossSection: Double, energy: Double): Double = crossSection * energy * exp(2 * PI * sommerfeld(energy))
    /** Electron-screening enhancement exp(πη U_e/E), U_e in eV. */
    fun screeningFactor(energy: Double, potential: Double): Double = exp(PI * sommerfeld(energy) * potential / 1000 / energy)

    companion object {
        fun kT(t9: Double): Double = 86.173_332_62 * t9
        fun entrance(r: Reaction) = ChargedChannel(r.projectile, r.target)
    }
}
