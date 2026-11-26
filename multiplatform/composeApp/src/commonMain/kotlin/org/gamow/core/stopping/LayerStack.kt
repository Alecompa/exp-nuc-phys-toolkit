package org.gamow.core.stopping

import kotlin.math.max
import kotlin.random.Random

/** One layer of a target stack: a material and its thickness (Å) along the layer normal. */
data class StackLayer(
    val target: StoppingTarget,
    /** Å */
    val thickness: Double,
    val id: String = newLayerId(),
)

private fun newLayerId(): String = Random.nextLong().toULong().toString(16).padStart(16, '0')

/** A beam crossing several layers in turn (window, dead layer, target, backing…). */
object LayerStack {
    /**
     * Energy loss in each layer the beam reaches, in beam order. The mean energy and the energy spread leaving one
     * layer enter the next; the list ends early when the beam stops. The tilt `angle` (degrees to the normal)
     * applies to every layer.
     */
    fun transport(ion: StoppingIon, layers: List<StackLayer>, energy: Double, angle: Double = 0.0, sigmaIn: Double = 0.0,
                  data: SRIMData = SRIMData.shared): List<StoppingCalculator.EnergyLoss> {
        val out = ArrayList<StoppingCalculator.EnergyLoss>()
        var e = energy
        var sigma = sigmaIn
        for (layer in layers) {
            if (!(layer.thickness > 0)) continue
            val r = StoppingCalculator(ion, layer.target, data).energyLoss(e, layer.thickness, angle, sigma)
            out.add(r)
            if (r.stopped) break
            e = r.energyOut
            sigma = r.sigma
        }
        return out
    }
}

/** Gas targets: density from pressure and temperature (ideal gas). */
object GasTarget {
    /** Boltzmann constant, J/K. */
    internal const val BOLTZMANN = 1.380_649e-23

    /** Atoms per cm³ of a gas at `pressure` mbar and `temperature` K with `atomsPerMolecule`. */
    fun atomDensity(pressure: Double, temperature: Double, atomsPerMolecule: Double): Double =
        pressure * 100 / (BOLTZMANN * temperature) * 1e-6 * atomsPerMolecule

    /**
     * Mass density (g/cm³) giving `target` the atom density of the gas, with SRIM's Avogadro constant, so that
     * `target.atomDensity` reproduces p/(kT) exactly.
     */
    fun density(target: StoppingTarget, pressure: Double, temperature: Double, atomsPerMolecule: Double): Double =
        atomDensity(pressure, temperature, atomsPerMolecule) * target.meanMass / 6.022e23

    /**
     * Atoms per molecule: 2 for the diatomic gases H, N, O, F, Cl, Br, I as single elements, 1 for other single
     * elements, otherwise the sum of the stoichiometries (N₂O → 3).
     */
    fun defaultAtomsPerMolecule(target: StoppingTarget): Double {
        if (target.components.size == 1) {
            val z = target.components[0].z
            val stoich = target.components[0].stoichiometry
            if (stoich > 1 && stoich == roundHalfAway(stoich)) return stoich
            return if (z in setOf(1, 7, 8, 9, 17, 35, 53)) 2.0 else 1.0
        }
        return max(1.0, target.components.fold(0.0) { s, c -> s + c.stoichiometry })
    }
}
