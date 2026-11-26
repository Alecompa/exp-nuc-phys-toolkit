package org.gamow.core.spectra

import org.gamow.core.Elements
import org.gamow.core.KinematicSolution
import org.gamow.core.MassTable
import org.gamow.core.Nubase
import org.gamow.core.Nuclide
import org.gamow.core.PhysicalConstants
import org.gamow.core.Reaction
import org.gamow.core.ReactionParticle
import org.gamow.core.TwoBodyKinematics
import org.gamow.core.stopping.StoppingCalculator
import org.gamow.core.stopping.StoppingIon
import org.gamow.core.stopping.StoppingTarget
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/** A charged-particle detector (e.g. a silicon detector) at a laboratory angle, behind absorber foils. */
data class ParticleDetectorSetup(
    /** Laboratory angle to the beam, degrees. */
    val angle: Double = 135.0,
    /** Intrinsic detector resolution, keV FWHM. */
    val resolution: Double = 15.0,
    /** Half-opening angle of the detector seen from the target, degrees (kinematic broadening). */
    val halfOpening: Double = 2.0,
    /** Absorbers between target and detector, in the order the particles cross them. */
    val foils: List<DetectorFoil> = emptyList(),
    /** Also show beam particles elastically scattered by each element of the target material. */
    val showElastic: Boolean = true,
)

/** One group of particles reaching the detector: an energy before and after the foils. */
data class ParticleGroup(
    val id: String,
    val kind: Kind,
    /** Particle label, e.g. "α" or "p". */
    val particle: String,
    /** What produced it, e.g. "⁷Li(p,α)" or "elastic on Ta". */
    val origin: String,
    /** Kinetic energy leaving the target, keV. */
    val emitted: Double,
    /** Energy after the foils, keV; null when the particle stops in them. */
    val detected: Double?,
    /** Expected peak FWHM in the detector, keV (resolution, foil straggling, kinematic spread). */
    val fwhm: Double,
    /** Index of the foil the particle stops in. */
    val stoppedIn: Int?,
    /** Neutral particles are not slowed by the foils and are usually not seen by a silicon detector. */
    val neutral: Boolean,
    /**
     * Elastic groups: Rutherford dσ/dΩ (lab, b/sr) per atom of the target material, i.e. weighted by the element's
     * atom fraction and the isotope's abundance. null for reaction groups.
     */
    val rutherford: Double? = null,
) {
    enum class Kind { REACTION, ELASTIC }
}

/**
 * Minimal Rutherford scattering (same formulas as NucPhysKit.RutherfordScattering): relativistic elastic kinematics
 * and dσ/dΩ_cm = (Z₁Z₂e²/(4E))² / sin⁴(θ/2) in b/sr. Kept private here so this package does not depend on the
 * org.gamow.core.astro port.
 */
private class Rutherford(projectile: Nuclide, target: Nuclide, beamEnergy: Double) {
    val z1 = projectile.z
    val z2 = target.z
    val kinematics = TwoBodyKinematics(projectile.kinematicMass, target.kinematicMass, projectile.kinematicMass,
        target.kinematicMass, beamEnergy)

    fun crossSectionCM(thetaCM: Double): Double {
        val a = (z1 * z2).toDouble() * PhysicalConstants.COULOMB_CONSTANT / (4 * kinematics.centerOfMassEnergy)    // fm
        return a * a / sin(thetaCM / 2).pow(4) * 1e-2
    }
}

object ParticleSpectrum {
    /**
     * Particle groups at the detector for the reaction and, optionally, for elastic scattering of the beam on each
     * element of `material`. `beamEnergy` is the laboratory energy at which the reaction happens. Sorted by detected
     * energy, highest first (stopped groups last).
     */
    fun groups(
        reaction: Reaction, beamEnergy: Double, residualExcitation: Double, material: StoppingTarget?,
        setup: ParticleDetectorSetup, table: MassTable = MassTable.ame2020,
    ): List<ParticleGroup> {
        if (!(beamEnergy > 0) || !(setup.angle > 0) || !(setup.angle < 180)) return emptyList()
        val theta = setup.angle * PI / 180
        val out = ArrayList<ParticleGroup>()

        val ej = reaction.ejectile
        if (ej is ReactionParticle.Ion) {
            val ejectile = ej.ion
            val k = TwoBodyKinematics(reaction, beamEnergy, residualExcitation = residualExcitation)
            val origin = "${reaction.target.label}(${reaction.projectile.reactionLabel},${ejectile.reactionLabel})" +
                (if (residualExcitation > 0) " Eₓ ${SpecMath.roundHalfAway(residualExcitation).toInt()} keV" else "")
            k.solutions(theta).forEachIndexed { i, s ->
                out.add(group("r$i", ParticleGroup.Kind.REACTION, ejectile, origin, s, setup))
            }
        }

        if (setup.showElastic && material != null) {
            var totalAtoms = 0.0
            for (c in material.components) totalAtoms += c.stoichiometry
            val seen = HashSet<Int>()
            for (c in material.components) {
                if (!seen.add(c.z)) continue
                val same = material.components.filter { it.z == c.z }
                var elementAtoms = 0.0
                for (s in same) elementAtoms += s.stoichiometry
                val atomFraction = elementAtoms / max(totalAtoms, 1e-300)
                // Each component of the element with its own share: a named isotope (enriched ¹³C next to ¹²C),
                // else the natural isotopes (NUBASE2020 abundances).
                val isotopes = ArrayList<Pair<Nuclide, Double>>()
                for (comp in same) {
                    val share = comp.stoichiometry / max(elementAtoms, 1e-300)
                    val named = comp.isotopeMassNumber?.let { table.nuclide(c.z, it) }
                    if (named != null) {
                        isotopes.add(named to share)
                    } else {
                        var natural = naturalIsotopes(c.z, table)
                        if (natural.isEmpty()) {
                            table.nuclide(c.z, SpecMath.roundHalfAway(comp.mass).toInt())?.let { natural = listOf(it to 1.0) }
                        }
                        isotopes += natural.map { it.first to it.second * share }
                    }
                }
                // The same isotope from two components is one scatterer.
                val merged = LinkedHashMap<Nuclide, Double>()
                for ((n, w) in isotopes) merged[n] = (merged[n]?.let { it + w }) ?: w
                val sorted = merged.entries.map { it.key to it.value }.sortedBy { it.first.a }
                out += elasticGroups(c.z, sorted, atomFraction, reaction.projectile, beamEnergy, theta, setup)
            }
        }
        return out.sortedByDescending { it.detected ?: -1.0 }
    }

    /** Stable isotopes of an element with their natural abundance fractions. */
    fun naturalIsotopes(z: Int, table: MassTable = MassTable.ame2020): List<Pair<Nuclide, Double>> =
        table.isotopes(z).mapNotNull { n ->
            val ab = Nubase.nubase2020.groundState(z, n.a)?.abundance
            if (ab == null || !(ab > 0)) null else n to ab / 100
        }

    private class Hit(val nucleus: Nuclide, val weight: Double, val solution: KinematicSolution, val sigma: Double, val branch: Int)

    /**
     * Elastic scattering of the beam on one element: one group per isotope and kinematic branch, merged into a single
     * abundance-weighted group when the isotopes are closer than half the detector resolution.
     */
    private fun elasticGroups(
        z: Int, isotopes: List<Pair<Nuclide, Double>>, atomFraction: Double, projectile: Nuclide, beamEnergy: Double,
        theta: Double, setup: ParticleDetectorSetup,
    ): List<ParticleGroup> {
        val hits = ArrayList<Hit>()
        for ((n, w) in isotopes) {
            val ruth = Rutherford(projectile, n, beamEnergy)
            // Both branches when the projectile is heavier than the target: the slow one is the projectile
            // scattered at large c.m. angle, not the recoil. Equal masses: the θ* = π branch has no energy.
            ruth.kinematics.solutions(theta).forEachIndexed { i, s ->
                if (s.ejectileEnergy > 1e-6 * beamEnergy) {
                    hits.add(Hit(n, w, s, ruth.crossSectionCM(s.thetaCM) * s.jacobian, i))
                }
            }
        }
        if (hits.isEmpty()) return emptyList()
        val symbol = Elements.symbol(z) ?: "?"
        val out = ArrayList<ParticleGroup>()
        for (branch in hits.map { it.branch }.toSet().sorted()) {
            val hs = hits.filter { it.branch == branch }
            val es = hs.map { it.solution.ejectileEnergy }
            val suffix = if (branch > 0) " (slow branch)" else ""
            if (hs.size > 1 && (es.max() - es.min()) < setup.resolution / 2) {
                // Merge: the weighted mean energy, the main isotope's kinematics for the width.
                var wsum = 0.0
                for (h in hs) wsum += h.weight
                var mean = 0.0
                for (h in hs) mean += h.weight * h.solution.ejectileEnergy
                mean /= wsum
                val main = hs.maxBy { it.weight }
                var sig = 0.0
                for (h in hs) sig += h.weight * h.sigma
                out.add(group("e${z}b$branch", ParticleGroup.Kind.ELASTIC, projectile, "elastic on $symbol$suffix",
                    main.solution, setup, mean).copy(rutherford = atomFraction * sig))
            } else {
                for (h in hs) {
                    if (!(h.weight >= 0.01)) continue
                    val pct = if (h.weight < 1) " (${SpecMath.roundHalfAway(100 * h.weight).toInt()} %)" else ""
                    out.add(group("e$z-${h.nucleus.a}b$branch", ParticleGroup.Kind.ELASTIC, projectile,
                        "elastic on ${h.nucleus.label}$pct$suffix", h.solution, setup).copy(rutherford = atomFraction * h.weight * h.sigma))
                }
            }
        }
        return out
    }

    private fun group(
        id: String, kind: ParticleGroup.Kind, particle: Nuclide, origin: String, s: KinematicSolution,
        setup: ParticleDetectorSetup, energy: Double? = null,
    ): ParticleGroup {
        val kinematic = abs(s.energySlope) * 2 * setup.halfOpening * PI / 180
        val emitted = energy ?: s.ejectileEnergy
        val label = particleLabel(particle)
        if (particle.z <= 0) {
            val fwhm = sqrt(setup.resolution * setup.resolution + (0.68 * kinematic).pow(2))
            return ParticleGroup(id, kind, label, origin, emitted, emitted, fwhm, null, true)
        }
        val ion = StoppingIon(particle)
        var e = emitted
        var sigma = 0.0
        var stoppedIn: Int? = null
        for ((i, foil) in setup.foils.withIndex()) {
            if (!(foil.thickness > 0)) continue
            val r = if (e > 0) runCatching {
                StoppingCalculator(ion, foil.material).energyLoss(e, foil.thickness, foil.angle, sigma)
            }.getOrNull() else null
            if (r == null || r.stopped || r.energyOut <= 0) { stoppedIn = i; break }
            e = r.energyOut; sigma = r.sigma
        }
        val straggling = 2 * sqrt(2 * ln(2.0)) * sigma
        val fwhm = sqrt(setup.resolution * setup.resolution + straggling * straggling + (0.68 * kinematic).pow(2))
        return ParticleGroup(id, kind, label, origin, emitted, if (stoppedIn == null) e else null, fwhm, stoppedIn, false)
    }

    /** p, d, t, ³He, α, n by their usual symbols; other nuclides as ¹²C. */
    fun particleLabel(n: Nuclide): String = when (n.z to n.a) {
        1 to 1 -> "p"; 1 to 2 -> "d"; 1 to 3 -> "t"; 2 to 4 -> "α"; 0 to 1 -> "n"
        else -> n.label
    }
}
