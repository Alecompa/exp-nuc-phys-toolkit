package org.gamow.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.gamow.core.*
import kotlin.math.*

// MARK: Setup

@Composable
fun SetupScreen(wb: Workbench, onDone: () -> Unit) {
    var text by remember { mutableStateOf(wb.reactionText) }
    val parsed = remember(text) { runCatching { Reaction.parse(text) } }
    val r = parsed.getOrNull()
    SectionCard("Reaction", footer = "Light ions p d t h a n, photon g; ¹²C or 12C; leave the residual empty to infer it; inverse kinematics such as p(7Be,g)8B.") {
        OutlinedTextField(text, { text = it }, label = { Text("Notation, e.g. 14N(p,g)15O") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        if (r != null) {
            ValueRow(r.label, "Q = ${Fmt.keV(r.qValue)} ± ${Fmt.sig(r.qValueUncertainty, 2)}", "keV")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { wb.setReaction(r); onDone() }) { Text("Use this reaction") }
                OutlinedButton(onClick = { wb.toggleSaved(r) }) { Text(if (wb.isSaved(r)) "★ Saved" else "☆ Save") }
            }
        } else {
            Text(parsed.exceptionOrNull()?.message ?: "", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
        }
    }
    SectionCard("Energies") {
        NumberField("Beam energy (lab)", wb.beamEnergy, "keV", range = 0.0..1e7) { wb.updateBeam(it) }
        NumberField("Residual excitation", wb.residualExcitation, "keV", range = 0.0..1e6) { wb.updateExcitation(it) }
    }
    val pick: (Reaction) -> Unit = { text = it.plainLabel; wb.setReaction(it) }
    if (wb.saved.isNotEmpty()) SectionCard("My reactions") { ReactionChips(wb.saved, wb.reaction?.plainLabel, pick) }
    val recent = wb.recent.filter { it !in wb.saved }.take(8)
    if (recent.isNotEmpty()) SectionCard("Recent") { ReactionChips(recent, wb.reaction?.plainLabel, pick) }
    for ((title, items) in Workbench.presets) SectionCard(title) { ReactionChips(items, wb.reaction?.plainLabel, pick) }
}

// MARK: Q value

@Composable
fun QValueScreen(wb: Workbench, onEdit: () -> Unit) {
    val r = wb.reaction ?: return NoReaction(onEdit)
    SectionCard {
        ReactionHeader(wb, onEdit)
        HeroNumber("${Fmt.keV(r.qValue)} ± ${Fmt.sig(r.qValueUncertainty, 2)}", "keV", "Q value (ground state)")
        if (r.usesEstimatedMasses) Text("Uses AME2020 masses estimated from systematics (#).", color = MaterialTheme.colorScheme.tertiary)
    }
    SectionCard("Energetics") {
        ValueRow("Threshold (lab)", Fmt.keV(r.threshold(wb.residualExcitation)), "keV", note = if (r.qValue(wb.residualExcitation) >= 0) "Exothermic" else null)
        if (wb.residualExcitation > 0) ValueRow("Q to Eₓ = ${Fmt.keV(wb.residualExcitation)} keV", Fmt.keV(r.qValue(wb.residualExcitation)), "keV")
        wb.ecm?.let { ValueRow("E c.m. at the beam energy", Fmt.keV(it), "keV") }
        r.compoundNucleus()?.let { cn ->
            val s = r.target.massExcess + r.projectile.massExcess - cn.massExcess
            ValueRow("Compound ${cn.label}: Eₓ", Fmt.keV((wb.ecm ?: 0.0) + s), "keV", note = "Separation energy ${Fmt.keV(s)} keV")
        }
    }
    SaveToNotebook("Q value", r.label) { listOf("Q" to "${Fmt.keV(r.qValue)} ± ${Fmt.sig(r.qValueUncertainty, 2)} keV",
        "Threshold" to "${Fmt.keV(r.threshold(wb.residualExcitation))} keV", "Residual Eₓ" to "${Fmt.keV(wb.residualExcitation)} keV") }
    SectionCard("Masses (AME2020)", footer = "Mass excesses Δ = M − A·u. Uncertainties added in quadrature; AME correlations neglected.") {
        for (n in listOfNotNull(r.target, r.projectile, r.ejectile.nuclide, r.residual).distinct()) {
            ValueRow(n.label, "${Fmt.keV(n.massExcess)} ± ${Fmt.sig(n.massExcessUncertainty, 2)}", "keV",
                note = "B/A = ${Fmt.fixed(n.bindingEnergyPerNucleon, 3)} keV")
        }
    }
}

// MARK: Kinematics

@Composable
fun KinematicsScreen(wb: Workbench, onEdit: () -> Unit) {
    val r = wb.reaction ?: return NoReaction(onEdit)
    var angle by remember { mutableStateOf(Prefs.get("angle")?.toDoubleOrNull() ?: 45.0) }
    val k = remember(r, wb.beamEnergy, wb.residualExcitation) { TwoBodyKinematics(r, wb.beamEnergy, wb.residualExcitation) }
    if (!k.isOpen) {
        SectionCard { ReactionHeader(wb, onEdit); Text("Closed: the beam energy is below the threshold of ${Fmt.keV(r.threshold(wb.residualExcitation))} keV.") }
        return
    }
    val sols = k.solutions(angle.radians)
    val name = r.ejectile.nuclide?.reactionLabel ?: "γ"
    SectionCard {
        ReactionHeader(wb, onEdit)
        HeroNumber(sols.firstOrNull()?.let { Fmt.keV(it.ejectileEnergy) } ?: "—", "keV", "$name energy at ${Fmt.fixed(angle, 1)}°")
        if (sols.size > 1) Text("Second branch: ${Fmt.keV(sols[1].ejectileEnergy)} keV", color = MaterialTheme.colorScheme.primary)
        k.maxEjectileAngle?.let { Text("Maximum lab angle ${Fmt.fixed(it.degrees, 2)}°", style = MaterialTheme.typography.bodyMedium) }
    }
    SectionCard("$name energy vs lab angle", footer = "Drag on the plot or use the slider. Relativistic two-body kinematics with ion masses.") {
        val curve = k.curve(361).map { it.ejectileAngle.degrees to it.ejectileEnergy }
        Plot(listOf(PlotSeries(curve, MaterialTheme.colorScheme.primary)), xLabel = "θ lab (°)", yLabel = "E (keV)", cursor = angle,
            onPointer = { angle = it.coerceIn(0.0, 180.0); Prefs.put("angle", "$angle") })
        Slider(angle.toFloat(), { angle = (it * 2).roundToInt() / 2.0; Prefs.put("angle", "$angle") }, valueRange = 0f..180f)
    }
    sols.forEachIndexed { i, s ->
        SectionCard(if (sols.size > 1) (if (i == 0) "High-energy branch" else "Low-energy branch") else "At ${Fmt.fixed(angle, 1)}°") {
            ValueRow("$name energy", Fmt.keV(s.ejectileEnergy), "keV")
            ValueRow("c.m. angle θ*", Fmt.fixed(s.thetaCM.degrees, 2), "°")
            ValueRow("${r.residual.label} energy", Fmt.keV(s.residualEnergy), "keV")
            ValueRow("${r.residual.label} angle", Fmt.fixed(s.residualAngle.degrees, 2), "°")
            ValueRow("dΩ*/dΩ", Fmt.sig(s.jacobian, 5), note = "σ(lab) = (dΩ*/dΩ) σ(c.m.)")
            ValueRow("dE/dθ", Fmt.sig(s.energySlope * PI / 180, 4), "keV/°")
        }
    }
    val exportKin = rememberTextExporter()
    TextButton(onClick = {
        exportKin("kinematics_${r.plainLabel.filter { it.isLetterOrDigit() }}.csv",
            "# ${r.plainLabel} at ${wb.beamEnergy} keV, residual Ex ${wb.residualExcitation} keV\n" +
            "theta_cm_deg,theta_lab_deg,ejectile_keV,residual_theta_deg,residual_keV,jacobian\n" +
            k.curve(181).joinToString("\n") { s -> listOf(s.thetaCM.degrees, s.ejectileAngle.degrees, s.ejectileEnergy, s.residualAngle.degrees,
                s.residualEnergy, s.jacobian).joinToString(",") { formatSignificant(it, 8) } })
    }) { Text("Export kinematics table (CSV)") }
    SectionCard("Centre of mass") {
        ValueRow("E c.m.", Fmt.keV(k.centerOfMassEnergy), "keV")
        ValueRow("β c.m.", Fmt.sig(k.beta, 5))
    }
    SaveToNotebook("Kinematics", "${r.label} at ${Fmt.sig(wb.beamEnergy, 5)} keV, θ = ${Fmt.fixed(angle, 1)}°") {
        sols.mapIndexed { i, s -> "$name energy${if (sols.size > 1) " (branch ${i + 1})" else ""}" to "${Fmt.keV(s.ejectileEnergy)} keV" } +
            listOf("Residual Eₓ" to "${Fmt.keV(wb.residualExcitation)} keV", "E c.m." to "${Fmt.keV(k.centerOfMassEnergy)} keV")
    }
}

// MARK: Gamow window

@Composable
fun GamowScreen(wb: Workbench, onEdit: () -> Unit) {
    val r = wb.reaction ?: return NoReaction(onEdit)
    val c = wb.entrance ?: return Message("The entrance channel ${r.label} has no Coulomb barrier.")
    val w = c.gamowWindow(wb.t9)
    SectionCard {
        ReactionHeader(wb, onEdit, showBeam = false)
        HeroNumber("${Fmt.sig(w.peak, 4)} ± ${Fmt.sig(w.width / 2, 3)}", "keV", "Gamow peak E₀ ± Δ/2 (c.m.) at T₉ = ${Fmt.sig(wb.t9, 3)}")
        Text("Laboratory: ${Fmt.sig(c.labEnergy(w.peak), 4)} keV", style = MaterialTheme.typography.bodyMedium)
    }
    SectionCard("Temperature") {
        val logT = log10(wb.t9)
        Slider(logT.toFloat(), { wb.updateT9(10.0.pow(it.toDouble()).let { t -> (t * 1000).roundToInt() / 1000.0 }) }, valueRange = -2f..1f)
        @OptIn(ExperimentalLayoutApi::class)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for ((label, t) in listOf("Sun 0.0157" to 0.0157, "H burning 0.06" to 0.06, "CNO 0.1" to 0.1, "He burning 0.2" to 0.2,
                "Novae 0.3" to 0.3, "C burning 0.9" to 0.9, "BBN 0.8" to 0.8)) {
                AssistChip(onClick = { wb.updateT9(t) }, label = { Text(label) })
            }
        }
        NumberField("T₉", wb.t9, "GK", range = 1e-4..100.0) { wb.updateT9(it) }
    }
    SectionCard("Gamow integrand exp(−E/kT − √(E_G/E))", footer = "Constant S; the band is E₀ ± Δ/2. Energies c.m.") {
        val hi = w.peak + 3 * w.width
        val pts = (1..300).map { val e = hi * it / 300; e to c.gamowIntegrand(e, wb.t9) }
        val peak = pts.maxOf { it.second }
        Plot(listOf(PlotSeries(pts.map { it.first to it.second / peak }, MaterialTheme.colorScheme.primary)),
            band = w.lower..w.upper, xLabel = "E c.m. (keV)", yLabel = "relative")
    }
    SaveToNotebook("Gamow window", "${r.label} at T₉ = ${Fmt.sig(wb.t9, 3)}") {
        listOf("E₀" to "${Fmt.sig(w.peak, 4)} keV", "Δ" to "${Fmt.sig(w.width, 4)} keV", "E₀ lab" to "${Fmt.sig(c.labEnergy(w.peak), 4)} keV")
    }
    SectionCard("Values") {
        ValueRow("Width Δ (1/e)", Fmt.sig(w.width, 4), "keV")
        ValueRow("kT", Fmt.sig(w.kT, 4), "keV")
        ValueRow("τ = 3E₀/kT", Fmt.sig(w.tau, 4))
        ValueRow("Gamow energy E_G", Fmt.sig(c.gamowEnergy, 5), "keV")
        ValueRow("η at E₀", Fmt.sig(c.sommerfeld(w.peak), 4))
        ValueRow("Coulomb barrier (r₀ = 1.25 fm)", Fmt.sig(c.coulombBarrier(c.radius(1.25)), 4), "keV")
    }
}

// MARK: S factor ↔ σ

@Composable
fun SFactorScreen(wb: Workbench, onEdit: () -> Unit) {
    val r = wb.reaction ?: return NoReaction(onEdit)
    val c = wb.entrance ?: return Message("The entrance channel ${r.label} has no Coulomb barrier.")
    var energy by remember { mutableStateOf(((wb.ecm ?: 100.0) * 1000).roundToInt() / 1000.0) }
    var s by remember { mutableStateOf(1.0) }
    var ue by remember { mutableStateOf(0.0) }
    val sigma = c.crossSection(s, energy)
    val f = c.screeningFactor(energy, ue)
    val (sv, su) = Fmt.crossSection(sigma)
    SectionCard {
        ReactionHeader(wb, onEdit)
        HeroNumber(sv, su, "Bare cross section at ${Fmt.sig(energy, 5)} keV (c.m.)")
        Text("η = ${Fmt.sig(c.sommerfeld(energy), 4)} · exp(−2πη) = ${Fmt.sig(c.gamowFactor(energy), 3)}", style = MaterialTheme.typography.bodyMedium)
    }
    SectionCard("Input") {
        NumberField("Energy (c.m.)", energy, "keV", range = 1e-3..1e6) { energy = it }
        wb.ecm?.let { TextButton(onClick = { energy = (it * 1000).roundToInt() / 1000.0 }) { Text("Use the beam energy: ${Fmt.keV(it)} keV c.m.") } }
        NumberField("S factor", s, "keV b", range = 0.0..1e12) { s = it }
        NumberField("Screening U_e", ue, "eV", range = 0.0..1e5) { ue = it }
        if (ue > 0) {
            val (scv, scu) = Fmt.crossSection(sigma * f)
            ValueRow("Screened σ (×${Fmt.sig(f, 4)})", scv, scu)
        }
    }
    SectionCard("σ(E) for this S", footer = "σ = S/E · exp(−2πη): the cross section falls by many decades below the barrier; S stays smooth. Log scale.") {
        val lo = energy / 5; val hi = energy * 5
        val pts = (0..200).map { val e = lo * (hi / lo).pow(it / 200.0); e to c.crossSection(s, e) }
        Plot(listOf(PlotSeries(pts, MaterialTheme.colorScheme.primary)), xLog = true, yLog = true, cursor = energy,
            xLabel = "E c.m. (keV)", yLabel = "σ (b)")
    }
}

@Composable
fun NoReaction(onEdit: () -> Unit) {
    SectionCard { Text("No valid reaction set."); Button(onClick = onEdit) { Text("Edit setup") } }
}

@Composable
fun Message(text: String) { SectionCard { Text(text) } }
