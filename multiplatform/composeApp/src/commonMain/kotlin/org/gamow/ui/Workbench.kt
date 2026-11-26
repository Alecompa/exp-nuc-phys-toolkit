package org.gamow.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.gamow.core.*

/** The shared setup every tool reads: reaction, beam energy, residual level, temperature; recent and saved reactions. */
class Workbench {
    var reactionText by mutableStateOf(Prefs.get("reaction") ?: "12C(p,g)13N")
        private set
    var beamEnergy by mutableStateOf(Prefs.get("beam")?.toDoubleOrNull() ?: 400.0)
        private set
    var residualExcitation by mutableStateOf(Prefs.get("ex")?.toDoubleOrNull() ?: 0.0)
        private set
    var t9 by mutableStateOf(Prefs.get("t9")?.toDoubleOrNull() ?: 0.1)
        private set
    var recent by mutableStateOf(Prefs.get("recent")?.split("|")?.filter { it.isNotEmpty() } ?: emptyList())
        private set
    var saved by mutableStateOf(Prefs.get("saved")?.split("|")?.filter { it.isNotEmpty() } ?: emptyList())
        private set

    val reaction: Reaction? get() = runCatching { Reaction.parse(reactionText) }.getOrNull()

    fun setReaction(r: Reaction) {
        if (r.plainLabel != reaction?.plainLabel) residualExcitation = 0.0
        reactionText = r.plainLabel
        recent = (listOf(r.plainLabel) + recent.filter { it != r.plainLabel }).take(10)
        Prefs.put("reaction", reactionText); Prefs.put("recent", recent.joinToString("|")); Prefs.put("ex", "$residualExcitation")
    }

    fun updateBeam(e: Double) { if (e.isFinite() && e >= 0) { beamEnergy = e; Prefs.put("beam", "$e") } }
    fun updateExcitation(e: Double) { if (e.isFinite() && e >= 0) { residualExcitation = e; Prefs.put("ex", "$e") } }
    fun updateT9(t: Double) { if (t.isFinite() && t > 0) { t9 = t; Prefs.put("t9", "$t") } }

    fun isSaved(r: Reaction) = r.plainLabel in saved
    fun toggleSaved(r: Reaction) {
        saved = if (isSaved(r)) saved - r.plainLabel else saved + r.plainLabel
        Prefs.put("saved", saved.joinToString("|"))
    }

    /** Target, beam and per-reaction S(E) inputs (Stopping, Yield, Rate). */
    val run = RunState(this)

    val entrance: ChargedChannel? get() = reaction?.let { ChargedChannel.entrance(it) }?.takeIf { it.isCharged }
    val ecm: Double? get() = reaction?.let { TwoBodyKinematics(it, beamEnergy).centerOfMassEnergy }

    companion object {
        val presets = listOf(
            "Hydrogen burning" to listOf("d(p,g)", "3He(a,g)", "7Be(p,g)", "12C(p,g)", "13C(p,g)", "14N(p,g)", "15N(p,a)",
                "17O(p,g)", "17O(p,a)", "18O(p,g)", "19F(p,a)", "22Ne(p,g)", "23Na(p,g)", "25Mg(p,g)"),
            "Helium & carbon burning" to listOf("12C(a,g)", "14N(a,g)", "13C(a,n)", "22Ne(a,n)", "22Ne(a,g)", "12C(12C,a)", "12C(12C,p)"),
            "BBN & light elements" to listOf("d(a,g)", "d(d,n)", "d(d,p)", "7Li(p,a)", "6Li(p,g)", "10B(p,a)", "11B(p,a)"),
            "Calibration & neutrons" to listOf("27Al(p,g)", "7Li(p,n)", "t(d,n)", "197Au(p,p)", "197Au(a,a)"),
        )
    }
}
