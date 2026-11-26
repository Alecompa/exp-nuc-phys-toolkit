package org.gamow.core

import kotlin.math.*

data class KinematicSolution(
    val thetaCM: Double,
    val ejectileAngle: Double,
    val ejectileEnergy: Double,
    val ejectileMomentum: Double,
    val residualAngle: Double,
    val residualEnergy: Double,
    val residualMomentum: Double,
    /** Jacobian dΩ_cm / dΩ_lab for the ejectile. */
    val jacobian: Double,
    /** dT₃/dθ₃, keV/rad. */
    val energySlope: Double,
)

/** Relativistic two-body kinematics; masses keV/c² (photon 0), beam kinetic energy keV. Port of NucPhysKit. */
class TwoBodyKinematics(val m1: Double, val m2: Double, val m3: Double, val m4: Double, val beamEnergy: Double) {
    val sqrtS: Double
    /** Velocity (β) and Lorentz factor of the centre of mass. */
    val beta: Double
    val gamma: Double
    /** CM momentum of the products (keV/c) and their CM total energies. */
    val pStar: Double
    val e3Star: Double
    val e4Star: Double

    init {
        val e1 = beamEnergy + m1
        val p1 = sqrt(beamEnergy * (beamEnergy + 2 * m1))
        val eTot = e1 + m2
        val s = m1 * m1 + m2 * m2 + 2 * e1 * m2
        sqrtS = sqrt(s)
        beta = p1 / eTot
        gamma = eTot / sqrtS
        val sum = m3 + m4
        val diff = m3 - m4
        val arg = (s - sum * sum) * (s - diff * diff)
        pStar = if (arg > 0) sqrt(arg) / (2 * sqrtS) else 0.0
        e3Star = (s + m3 * m3 - m4 * m4) / (2 * sqrtS)
        e4Star = (s + m4 * m4 - m3 * m3) / (2 * sqrtS)
    }

    constructor(reaction: Reaction, beamEnergy: Double, residualExcitation: Double = 0.0, ejectileExcitation: Double = 0.0) : this(
        reaction.projectile.kinematicMass, reaction.target.kinematicMass,
        if (reaction.ejectile.isPhoton) 0.0 else reaction.ejectile.mass + ejectileExcitation,
        reaction.residual.kinematicMass + residualExcitation, beamEnergy,
    )

    val isOpen: Boolean get() = sqrtS > m3 + m4
    /** Kinetic energy in the CM frame, keV (relativistic). */
    val centerOfMassEnergy: Double get() = sqrtS - m1 - m2
    val ejectileBetaCM: Double get() = if (e3Star > 0) pStar / e3Star else 0.0

    /** Maximum lab angle of the ejectile (rad), or null when every angle is reachable. */
    val maxEjectileAngle: Double?
        get() {
            if (!isOpen || m3 <= 0 || beta <= ejectileBetaCM) return null
            val g3 = e3Star / m3
            val c2 = (1 - (g3 * g3) / (gamma * gamma)) / (beta * beta)
            return acos(sqrt(min(1.0, max(0.0, c2))))
        }

    /** Solution at a CM angle of the ejectile (rad). */
    fun solution(cmAngle: Double): KinematicSolution? {
        if (!isOpen) return null
        val c = cos(cmAngle)
        val s = sin(cmAngle)
        val pz3 = gamma * (pStar * c + beta * e3Star)
        val px3 = pStar * s
        val e3 = gamma * (e3Star + beta * pStar * c)
        val p3 = sqrt(pz3 * pz3 + px3 * px3)
        val theta3 = atan2(px3, pz3)
        val pz4 = gamma * (-pStar * c + beta * e4Star)
        val e4 = gamma * (e4Star - beta * pStar * c)
        val theta4 = atan2(pStar * s, pz4)
        val p4 = sqrt(pz4 * pz4 + px3 * px3)
        val denom = gamma * pStar * abs(p3 - beta * e3 * cos(theta3))
        val jac = if (denom > 0) p3 * p3 / denom else Double.POSITIVE_INFINITY
        val h = 1e-5
        val tPlus = atan2(pStar * sin(cmAngle + h), gamma * (pStar * cos(cmAngle + h) + beta * e3Star))
        val tMinus = atan2(pStar * sin(cmAngle - h), gamma * (pStar * cos(cmAngle - h) + beta * e3Star))
        val dThetaLab = (tPlus - tMinus) / (2 * h)
        val dT = -gamma * beta * pStar * s
        val slope = if (abs(dThetaLab) > 1e-12) dT / dThetaLab else 0.0
        return KinematicSolution(cmAngle, theta3, e3 - m3, p3, theta4, e4 - m4, p4, jac, slope)
    }

    /** Solutions at an ejectile lab angle (rad): none, one, or two (inverse kinematics), higher energy first. */
    fun solutions(labAngle: Double): List<KinematicSolution> {
        if (!isOpen || pStar <= 0) return emptyList()
        val c = cos(labAngle)
        val k = e3Star / gamma
        val a = 1 - beta * beta * c * c
        val disc = beta * beta * m3 * m3 * c * c - m3 * m3 + k * k
        if (disc < 0 || a <= 0) return emptyList()
        val root = sqrt(disc)
        val momenta = mutableListOf((k * beta * c + root) / a)
        if (root > 0) momenta.add((k * beta * c - root) / a)
        val result = mutableListOf<KinematicSolution>()
        for (p in momenta) {
            if (p < 0 || k + beta * p * c < 0) continue
            val cosStar = max(-1.0, min(1.0, (p * c / gamma - beta * e3Star) / pStar))
            solution(acos(cosStar))?.let { result.add(it) }
        }
        return result.sortedByDescending { it.ejectileEnergy }
    }

    /** Curve sampled uniformly in CM angle (both branches in order). */
    fun curve(samples: Int = 181): List<KinematicSolution> {
        if (!isOpen || samples < 2) return emptyList()
        return (0 until samples).mapNotNull { solution(PI * it / (samples - 1)) }
    }
}

val Double.degrees: Double get() = this * 180 / PI
val Double.radians: Double get() = this * PI / 180
