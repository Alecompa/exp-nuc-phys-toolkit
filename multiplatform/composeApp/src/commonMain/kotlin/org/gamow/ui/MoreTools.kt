package org.gamow.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import org.gamow.core.*
import org.gamow.core.astro.RutherfordScattering
import org.gamow.core.runplanning.Beam
import org.gamow.core.spectra.*
import kotlin.math.*

/** Detector choice and the user's efficiency curve, shared by Detector response, Detector spectrum and Yield. */
object DetectorSettings {
    var preset by mutableStateOf(Prefs.get("det.preset")?.toIntOrNull()?.coerceIn(0, ResolutionModel.presets.size - 1) ?: 0)
        private set
    var curve by mutableStateOf(load())
        private set

    fun choosePreset(i: Int) { preset = i; Prefs.put("det.preset", "$i") }
    fun saveCurve(c: EfficiencyCurve) {
        curve = c
        Prefs.put("det.eff", c.order.toString() + "|" + c.points.joinToString(";") { "${it.energy}:${it.efficiency}:${it.relativeUncertainty}" })
    }
    /** True while the curve is still the bundled example, not the user's own points. */
    val isExample: Boolean get() = Prefs.get("det.eff").isNullOrEmpty()
    fun resetToExample() { curve = EfficiencyCurve.example; Prefs.put("det.eff", "") }

    private fun load(): EfficiencyCurve = Prefs.get("det.eff")?.let { s -> runCatching {
        val (order, pts) = s.split('|', limit = 2)
        EfficiencyCurve(pts.split(';').filter { it.isNotEmpty() }.map { p -> p.split(':').let { EfficiencyCurve.Point(it[0].toDouble(), it[1].toDouble(), it[2].toDouble()) } }, order.toInt())
    }.getOrNull() } ?: EfficiencyCurve.example

    val model: ResolutionModel get() = ResolutionModel.presets[preset].model
}

// MARK: Rutherford

@Composable
fun RutherfordScreen(wb: Workbench, onEdit: () -> Unit) {
    val r = wb.reaction ?: return NoReaction(onEdit)
    if (r.projectile.z == 0 || r.target.z == 0) return Message("Rutherford scattering needs a charged beam and target.")
    var angle by remember { mutableStateOf(Prefs.get("ruth.angle")?.toDoubleOrNull() ?: 135.0) }
    var omega by remember { mutableStateOf(1.0) }     // msr
    val ruth = remember(r, wb.beamEnergy) { RutherfordScattering(r.projectile, r.target, wb.beamEnergy) }
    val sols = ruth.at(angle.radians)
    SectionCard {
        ReactionHeader(wb, onEdit)
        Text("Elastic ${r.projectile.reactionLabel} on ${r.target.label}", style = MaterialTheme.typography.bodyMedium)
        sols.firstOrNull()?.let { HeroNumber(Fmt.sig(it.crossSectionLab, 4), "b/sr", "dσ/dΩ (lab) at ${Fmt.fixed(angle, 1)}°") }
            ?: Text("No elastic ${r.projectile.reactionLabel} at ${Fmt.fixed(angle, 1)}° (beyond the maximum angle).")
        Slider(angle.toFloat(), { angle = (it * 2).roundToInt() / 2.0; Prefs.put("ruth.angle", "$angle") }, valueRange = 1f..179f)
    }
    sols.forEachIndexed { i, p ->
        SectionCard(if (sols.size > 1) (if (i == 0) "High-energy branch" else "Low-energy branch") else "At ${Fmt.fixed(angle, 1)}°") {
            ValueRow("Scattered energy", Fmt.keV(p.energy), "keV")
            ValueRow("dσ/dΩ (lab)", Fmt.sig(p.crossSectionLab, 4), "b/sr")
            ValueRow("dσ/dΩ (c.m.)", Fmt.sig(p.crossSectionCM, 4), "b/sr")
            ValueRow("θ c.m.", Fmt.fixed(p.thetaCM.degrees, 2), "°")
        }
    }
    sols.firstOrNull()?.let { first ->
        SectionCard("Monitor counts", footer = "N = dσ/dΩ · ΔΩ · N_t · Q/(qe), thin target. Point-charge scattering: valid well below the Coulomb barrier.") {
            NumberField("Detector solid angle", omega, "msr", range = 1e-6..4000.0) { omega = it }
            val target = wb.run.target()
            val p = wb.run.profile()
            val areal = target?.activeArealDensity(r.target.z, r.target.a, p.abundance / 100, wb.run.thickness, wb.run.tilt)
            if (areal != null) {
                ValueRow("${r.target.label} areal density", Fmt.sig(areal / 1e15, 4), "10¹⁵ at/cm²", note = "Target of Stopping & Yield")
                val perMicroC = first.crossSectionLab * 1e-24 * omega * 1e-3 * areal * 1e-6 / (wb.run.chargeState * 1.602_176_634e-19)
                ValueRow("Counts per µC", Fmt.sig(perMicroC, 4), note = "Charge state ${wb.run.chargeState}+")
            } else Text("The target material contains no ${r.target.label}.", color = MaterialTheme.colorScheme.error)
        }
    }
    SectionCard("dσ/dΩ (lab) vs angle") {
        val pts = (2..178).flatMap { a -> ruth.at(a.toDouble().radians).take(1).map { a.toDouble() to it.crossSectionLab } }
        Plot(listOf(PlotSeries(pts, MaterialTheme.colorScheme.primary)), yLog = true, cursor = angle, xLabel = "θ lab (°)", yLabel = "b/sr",
            onPointer = { angle = it.coerceIn(1.0, 179.0) })
    }
}

// MARK: Gamma Doppler

@Composable
fun DopplerScreen(wb: Workbench, onEdit: () -> Unit) {
    val r = wb.reaction ?: return NoReaction(onEdit)
    val k = TwoBodyKinematics(r, wb.beamEnergy, wb.residualExcitation)
    var angle by remember { mutableStateOf(Prefs.get("dop.angle")?.toDoubleOrNull() ?: 55.0) }
    var distance by remember { mutableStateOf(5.0) }
    var radius by remember { mutableStateOf(3.5) }
    val primary = InBeamGamma.primary(r, wb.beamEnergy, wb.residualExcitation)
    val levelGamma = if (wb.residualExcitation > 0) GammaDoppler.recoilCorrected(wb.residualExcitation, r.residual.kinematicMass) else null
    var e0 by remember(r, wb.residualExcitation) { mutableStateOf(primary?.restEnergy ?: levelGamma ?: 1000.0) }
    val beta = k.beta
    val theta = angle.radians
    val half = Geometry.halfOpeningAngle(radius, distance)
    val e = GammaDoppler.energy(e0, beta, theta)
    val range = GammaDoppler.range(e0, beta, theta, half)
    SectionCard {
        ReactionHeader(wb, onEdit)
        HeroNumber(Fmt.keV(e), "keV", "γ at ${Fmt.fixed(angle, 1)}° (emitted at ${Fmt.keV(e0)} keV)")
        Text("Shift ${if (e >= e0) "+" else ""}${Fmt.sig(e - e0, 3)} keV · β c.m. = ${Fmt.sig(beta, 3)}", style = MaterialTheme.typography.bodyMedium)
        Slider(angle.toFloat(), { angle = (it * 2).roundToInt() / 2.0; Prefs.put("dop.angle", "$angle") }, valueRange = 0f..180f)
    }
    SectionCard("γ ray") {
        NumberField("Energy at rest", e0, "keV", range = 0.0..1e5) { e0 = it }
        primary?.let { p -> TextButton(onClick = { e0 = p.restEnergy }) { Text("Primary capture γ (c.m.): ${Fmt.keV(p.restEnergy)} keV") } }
        levelGamma?.let { g -> TextButton(onClick = { e0 = g }) { Text("${r.residual.label} level → ground state: ${Fmt.keV(g)} keV") } }
        Text("Emitter moving with the c.m. velocity, no slowing down before decay (lifetime ≪ stopping time).", style = MaterialTheme.typography.bodySmall)
    }
    SectionCard("Detector opening", footer = "E = E₀ √(1−β²)/(1 − β cos θ), averaged over a uniformly illuminated detector face.") {
        NumberField("Distance to the face", distance, "cm", range = 0.0..1e4) { distance = it }
        NumberField("Crystal radius", radius, "cm", range = 0.0..100.0) { radius = it }
        ValueRow("Range over the face", "${Fmt.keV(range.start)} – ${Fmt.keV(range.endInclusive)}", "keV")
        ValueRow("Broadening (full)", Fmt.sig(range.endInclusive - range.start, 3), "keV")
        ValueRow("Mean over the face", Fmt.keV(GammaDoppler.meanOverCone(e0, beta, theta, half, 30)), "keV")
        ValueRow("Solid angle", Fmt.sig(Geometry.diskSolidAngle(radius, distance) / (4 * PI) * 100, 3), "% of 4π")
    }
    SectionCard("Energy vs angle") {
        Plot(listOf(PlotSeries((0..180 step 2).map { a -> a.toDouble() to GammaDoppler.energy(e0, beta, a.toDouble().radians) }, MaterialTheme.colorScheme.primary)),
            cursor = angle, xLabel = "θ (°)", yLabel = "E (keV)", onPointer = { angle = it.coerceIn(0.0, 180.0) })
    }
}

// MARK: Beam current

@Composable
fun BeamScreen(wb: Workbench, onEdit: () -> Unit) {
    val r = wb.reaction
    var q by remember { mutableStateOf(wb.run.chargeState) }
    var current by remember { mutableStateOf(wb.run.current) }     // µA
    var charge by remember { mutableStateOf(1.0) }                 // C
    val pps = Beam.particlesPerSecond(current * 1e-6, q)
    SectionCard {
        r?.let { ReactionHeader(wb, onEdit) }
        HeroNumber(Fmt.sig(pps, 4), "particles/s", "${Fmt.sig(current, 4)} µA of ${r?.projectile?.reactionLabel ?: "ions"} in charge state $q+")
    }
    SectionCard("Beam") {
        NumberField("Electrical current", current, "µA", range = 0.0..1e7) { current = it; wb.run.updateCurrent(it) }
        Choice((1..min(6, max(1, r?.projectile?.z ?: 6))).map { it to "$it+" }, q) { q = it; wb.run.updateCharge(it) }
        ValueRow("Particle current", Fmt.sig(current / q, 4), "pµA")
        ValueRow("Power on target at ${Fmt.sig(wb.beamEnergy, 4)} keV", Fmt.sig(Beam.power(pps, wb.beamEnergy), 4), "W", note = "Full energy deposited")
    }
    SectionCard("Integrated charge") {
        NumberField("Charge", charge, "C", range = 0.0..1e6) { charge = it }
        ValueRow("Particles", Fmt.sig(Beam.particles(charge, q), 4))
        if (current > 0) ValueRow("Time at this current", durationText(charge / (current * 1e-6)).let { "${it.first} ${it.second}" })
    }
}

// MARK: Detector response

@Composable
fun DetectorScreen() {
    val ds = DetectorSettings
    val model = ds.model
    val curve = ds.curve
    val fit = curve.fit()
    SectionCard {
        var menu by remember { mutableStateOf(false) }
        Box {
            PickerField("Detector", ResolutionModel.presets[ds.preset].name) { menu = true }
            DropdownMenu(menu, { menu = false }) {
                ResolutionModel.presets.forEachIndexed { i, p -> DropdownMenuItem(text = { Text(p.name) }, onClick = { ds.choosePreset(i); menu = false }) }
            }
        }
        HeroNumber(Fmt.sig(model.fwhm(1332.5), 3), "keV", "FWHM at 1332 keV")
        Text("122 keV: ${Fmt.sig(model.fwhm(122.0), 3)} · 662 keV: ${Fmt.sig(model.fwhm(661.7), 3)} · 6 MeV: ${Fmt.sig(model.fwhm(6000.0), 3)} keV",
            style = MaterialTheme.typography.bodyMedium)
    }
    SectionCard("Full-energy efficiency", footer = "Weighted fit of ln ε as a polynomial in ln E. Used by Yield & beam time and Detector spectrum. Points: your calibration (absolute efficiency, %).") {
        if (ds.isExample) Text("Showing an example HPGe curve. Enter your own calibration points below.", color = MaterialTheme.colorScheme.tertiary)
        fit?.let { f ->
            val es = curve.points.map { it.energy }
            val lo = (es.minOrNull() ?: 100.0) / 1.5; val hi = (es.maxOrNull() ?: 3000.0) * 1.5
            Plot(listOf(
                PlotSeries((0..100).map { val e = lo * (hi / lo).pow(it / 100.0); e to 100 * f.efficiency(e) }, MaterialTheme.colorScheme.primary),
                PlotSeries(curve.points.map { it.energy to 100 * it.efficiency }, Color(0xFF64B5F6), line = false),
            ), xLog = true, yLog = true, xLabel = "E (keV)", yLabel = "ε (%)")
            ValueRow("χ²/ν", if (f.degreesOfFreedom > 0) Fmt.sig(f.chiSquared / f.degreesOfFreedom, 3) else "—", note = "${curve.points.size} points, order ${curve.order}")
        } ?: Text("Need at least ${curve.order + 1} points for order ${curve.order}.", color = MaterialTheme.colorScheme.error)
        curve.points.forEachIndexed { i, p ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                NumberField("E", p.energy, "keV", Modifier.weight(1f), range = 1.0..1e5) { v -> ds.saveCurve(curve.copy(points = curve.points.mapIndexed { j, x -> if (j == i) x.copy(energy = v) else x })) }
                Spacer(Modifier.width(6.dp))
                NumberField("ε", 100 * p.efficiency, "%", Modifier.weight(1f), range = 0.0..100.0) { v -> ds.saveCurve(curve.copy(points = curve.points.mapIndexed { j, x -> if (j == i) x.copy(efficiency = v / 100) else x })) }
                TextButton(onClick = { ds.saveCurve(curve.copy(points = curve.points.filterIndexed { j, _ -> j != i })) }) { Text("✕") }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { ds.saveCurve(curve.copy(points = curve.points + EfficiencyCurve.Point(1000.0, 0.005))) }) { Text("Add point") }
            if (!ds.isExample) TextButton(onClick = { ds.resetToExample() }) { Text("Reset to example") }
        }
        MoreOptions("Fit order", summary = "${curve.order}") {
            Choice((1..4).map { it to "$it" }, curve.order) { ds.saveCurve(curve.copy(order = it)) }
        }
    }
}
