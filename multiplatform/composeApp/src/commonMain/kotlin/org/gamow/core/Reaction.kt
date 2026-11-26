package org.gamow.core

import kotlin.math.max
import kotlin.math.sqrt

/** A participant in a two-body reaction: a nuclide or a photon. */
sealed class ReactionParticle {
    data class Ion(val ion: Nuclide) : ReactionParticle()
    data object Photon : ReactionParticle()

    val z: Int get() = (this as? Ion)?.ion?.z ?: 0
    val a: Int get() = (this as? Ion)?.ion?.a ?: 0
    val massExcess: Double get() = (this as? Ion)?.ion?.massExcess ?: 0.0
    /** Ion mass, keV/c²; zero for a photon. */
    val mass: Double get() = (this as? Ion)?.ion?.kinematicMass ?: 0.0
    val nuclide: Nuclide? get() = (this as? Ion)?.ion
    val isPhoton: Boolean get() = this is Photon
    val reactionLabel: String get() = (this as? Ion)?.ion?.reactionLabel ?: "γ"
}

class ReactionException(val kind: Kind, val detail: String = "") : Exception() {
    enum class Kind { MALFORMED, UNKNOWN_NUCLIDE, NOT_CONSERVED, NO_RESIDUAL }

    override val message: String
        get() = when (kind) {
            Kind.MALFORMED -> "Use the form Target(projectile,ejectile)Residual, e.g. 12C(p,γ)13N."
            Kind.UNKNOWN_NUCLIDE -> "“$detail” is not in AME2020."
            Kind.NOT_CONSERVED -> "Charge or mass number is not conserved."
            Kind.NO_RESIDUAL -> "No bound residual nucleus for this channel."
        }
}

/** A two-body reaction A(a,b)B. */
data class Reaction(
    val target: Nuclide,
    val projectile: Nuclide,
    val ejectile: ReactionParticle,
    val residual: Nuclide,
) {
    init {
        if (target.z + projectile.z != ejectile.z + residual.z || target.a + projectile.a != ejectile.a + residual.a) {
            throw ReactionException(ReactionException.Kind.NOT_CONSERVED)
        }
    }

    /** Ground-state Q value, keV (AME atomic mass excesses; electron masses cancel). */
    val qValue: Double get() = target.massExcess + projectile.massExcess - ejectile.massExcess - residual.massExcess

    /** Quadrature uncertainty of Q; a nuclide on both sides cancels (elastic: 0). */
    val qValueUncertainty: Double
        get() {
            val weight = HashMap<Nuclide, Pair<Int, Double>>()
            fun add(n: Nuclide?, sign: Int) {
                if (n == null) return
                val w = weight[n] ?: (0 to n.massExcessUncertainty)
                weight[n] = (w.first + sign) to w.second
            }
            add(target, 1); add(projectile, 1); add(ejectile.nuclide, -1); add(residual, -1)
            return sqrt(weight.values.sumOf { val s = it.first * it.second; s * s })
        }

    val usesEstimatedMasses: Boolean
        get() = target.isEstimated || projectile.isEstimated || residual.isEstimated || (ejectile.nuclide?.isEstimated ?: false)

    fun qValue(residualExcitation: Double): Double = qValue - residualExcitation

    /** Relativistic laboratory threshold of the projectile kinetic energy, keV (0 when exothermic). */
    fun threshold(residualExcitation: Double = 0.0): Double {
        val m1 = projectile.kinematicMass
        val m2 = target.kinematicMass
        val mf = ejectile.mass + residual.kinematicMass + residualExcitation
        return max(0.0, (mf * mf - (m1 + m2) * (m1 + m2)) / (2 * m2))
    }

    /** "¹²C(p,γ)¹³N" */
    val label: String get() = "${target.label}(${projectile.reactionLabel},${ejectile.reactionLabel})${residual.label}"

    /** "12C(p,g)13N" */
    val plainLabel: String
        get() = "${target.plainLabel}(${projectile.plainLight},${ejectile.nuclide?.plainLight ?: "g"})${residual.plainLabel}"

    /** The same channel with beam and target exchanged; null for identical particles. */
    val swappedBeamAndTarget: Reaction?
        get() = if (target == projectile) null else runCatching { Reaction(projectile, target, ejectile, residual) }.getOrNull()

    fun compoundNucleus(table: MassTable = MassTable.ame2020): Nuclide? =
        table.nuclide(target.z + projectile.z, target.a + projectile.a)

    companion object {
        /** Builds the reaction inferring the residual from conservation laws. */
        fun infer(target: Nuclide, projectile: Nuclide, ejectile: ReactionParticle, table: MassTable = MassTable.ame2020): Reaction {
            val z = target.z + projectile.z - ejectile.z
            val a = target.a + projectile.a - ejectile.a
            val residual = (if (z >= 0 && a >= 1) table.nuclide(z, a) else null)
                ?: throw ReactionException(ReactionException.Kind.NO_RESIDUAL)
            return Reaction(target, projectile, ejectile, residual)
        }

        /** Parses "12C(p,g)13N", "12C(p,γ)", "3He(a,g)7Be", "d(p,g)", "27Al(p,p')". */
        fun parse(notation: String, table: MassTable = MassTable.ame2020): Reaction {
            val s = notation.replace(" ", "")
            val open = s.indexOf('(')
            val close = s.indexOf(')')
            if (open < 0 || close < 0 || open >= close) throw ReactionException(ReactionException.Kind.MALFORMED)
            val targetText = s.substring(0, open)
            val inner = s.substring(open + 1, close).split(',')
            if (inner.size != 2 || targetText.isEmpty()) throw ReactionException(ReactionException.Kind.MALFORMED)
            val residualText = s.substring(close + 1)
            fun nuclide(text: String) = table.nuclide(named = text)
                ?: throw ReactionException(ReactionException.Kind.UNKNOWN_NUCLIDE, text)
            val target = nuclide(targetText)
            val projectile = nuclide(inner[0])
            // (p,p′): the prime only marks an excited residual.
            val ejText = inner[1].trim('\'', '’', '′')
            val ejectile = if (ejText.lowercase() in setOf("g", "γ", "gamma")) ReactionParticle.Photon
                else ReactionParticle.Ion(nuclide(ejText))
            return if (residualText.isEmpty()) infer(target, projectile, ejectile, table)
                else Reaction(target, projectile, ejectile, nuclide(residualText))
        }
    }
}
