package org.gamow.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.gamow.core.*
import org.gamow.core.spectra.*
import org.gamow.core.stopping.StoppingTarget
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.pow
import kotlin.math.roundToInt

/**
 * Settings of the detector-spectrum tool, kept between launches (contaminants, sources, window, geometry, escape model,
 * particle detector). Foils are kept for the session only.
 */
private object SpectrumState {
    private const val RS = '\u001E'; private const val FS = '\u001F'
    var setup by mutableStateOf(loadSetup())
    var reactions by mutableStateOf(Prefs.get("spec.reactions")?.toDoubleOrNull() ?: 1e4)
    var particle by mutableStateOf(loadParticle())

    /** Saves after every change; called from the screen's LaunchedEffect. */
    fun save() {
        val s = setup; val g = s.geometry; val e = s.escape
        Prefs.put("spec.setup", listOf(
            "${s.maximumEnergy}", "${s.channels}", "${s.continuumRatio}", "${s.background}",
            "${g.angle}", "${g.halfOpening}", "${g.recoilsStop}", "${g.stoppingTime}",
            "${e.enabled}", e.crystal.name, "${e.singleAtReference}", "${e.doubleAtReference}",
            s.backgrounds.joinToString(";") { "${it.id}:${it.counts}:${it.enabled}" },
            s.lines.joinToString(";") { "${it.name.replace(":", " ").replace(";", " ")}:${it.energy}:${it.counts}:${it.enabled}" },
        ).joinToString(FS.toString()))
        Prefs.put("spec.reactions", "$reactions")
        val p = particle
        Prefs.put("spec.particle", "${p.angle}$FS${p.resolution}$FS${p.halfOpening}$FS${p.showElastic}")
    }

    private fun loadSetup(): SpectrumSetup = Prefs.get("spec.setup")?.let { str -> runCatching {
        val f = str.split(FS)
        fun pairs(t: String) = t.split(';').filter { it.isNotEmpty() }.map { it.split(':') }
        SpectrumSetup(
            maximumEnergy = f[0].toDouble(), channels = f[1].toInt(), continuumRatio = f[2].toDouble(), background = f[3].toDouble(),
            geometry = GammaGeometry(f[4].toDouble(), f[5].toDouble(), f[6].toBoolean(), f[7].toDouble()),
            escape = EscapeModel(enabled = f[8].toBoolean(), crystal = DetectorCrystal.valueOf(f[9]),
                singleAtReference = f[10].toDouble(), doubleAtReference = f[11].toDouble()),
            backgrounds = pairs(f[12]).map { BackgroundEntry(it[0], it[1].toDouble(), it[2].toBoolean()) },
            lines = pairs(f[13]).map { SpectrumLine(it[0], it[1].toDouble(), it[2].toDouble(), it[3].toBoolean()) },
        )
    }.getOrNull() } ?: SpectrumSetup(maximumEnergy = 3000.0)

    private fun loadParticle(): ParticleDetectorSetup = Prefs.get("spec.particle")?.let { str -> runCatching {
        val f = str.split(FS)
        ParticleDetectorSetup(angle = f[0].toDouble(), resolution = f[1].toDouble(), halfOpening = f[2].toDouble(), showElastic = f[3].toBoolean())
    }.getOrNull() } ?: ParticleDetectorSetup()
}

/**
 * Expected detector spectrum for the setup: γ rays (reaction lines with recoil and Doppler, contaminants, sources)
 * in an HPGe or scintillator, or charged particles at a silicon detector behind foils.
 */
@Composable
fun SpectrumScreen(wb: Workbench, onEdit: () -> Unit) {
    val r = wb.reaction ?: return NoReaction(onEdit)
    val charged = (r.ejectile.nuclide?.z ?: 0) > 0
    var particles by remember(r) { mutableStateOf(charged && wb.residualExcitation == 0.0) }
    SectionCard {
        ReactionHeader(wb, onEdit)
        Choice(listOf(false to "γ rays", true to "Particles"), particles) { particles = it }
    }
    LaunchedEffect(SpectrumState.setup, SpectrumState.particle, SpectrumState.reactions) { SpectrumState.save() }
    if (particles) ParticleSection(wb, r) else GammaSection(wb, r)
}

@Composable
private fun GammaSection(wb: Workbench, r: Reaction) {
    val s = SpectrumState
    val setup = s.setup
    val model = DetectorSettings.model
    val geo = setup.geometry
    // Level scheme of the residual from ENSDF (IAEA LiveChart, cached on the device); null until loaded or offline.
    var scheme by remember(r.residual) { mutableStateOf(LiveChartClient.shared.cached(r.residual.z, r.residual.a)) }
    LaunchedEffect(r.residual) { if (scheme == null) scheme = runCatching { LiveChartClient.shared.levelScheme(r.residual.z, r.residual.a) }.getOrNull() }
    var cascadeNote = ""
    // Reaction γ rays: the capture primary, then the cascade of the residual level from the ENSDF branching ratios,
    // each line Doppler-shifted with the in-flight fraction from the level lifetimes (feeding included).
    val reactionLines = buildList {
        InBeamGamma.primary(r, wb.beamEnergy, wb.residualExcitation, geo)?.let { add(it) }
        val ex = wb.residualExcitation
        if (ex > 1) {
            val sch = scheme
            val c = sch?.let { GammaCascade.from(ex, it) }
            if (sch != null && c != null && c.lines.isNotEmpty()) {
                val times = GammaCascade.meanDecayTimes(c.lines) { lv -> sch.levels.firstOrNull { kotlin.math.abs(it.energy - lv) < 0.5 }?.halfLifeSeconds?.let { it / kotlin.math.ln(2.0) } }
                for (g in c.lines) InBeamGamma.residualLevel(r, wb.beamEnergy, c.startLevel ?: ex, g.energy, g.finalLevel, times[g.initialLevel],
                    g.intensity, geo, "${r.residual.label} ${Fmt.keV(g.initialLevel)} → ${Fmt.keV(g.finalLevel)}")?.let { add(it) }
                cascadeNote = "Cascade from ENSDF branching ratios and lifetimes" + if (c.unresolved > 0.01) "; ${Fmt.sig(100 * c.unresolved, 2)} % reaches levels without γ data." else "."
            } else {
                InBeamGamma.residualLevel(r, wb.beamEnergy, ex, meanLife = null, geometry = geo)?.let { add(it) }
                cascadeNote = if (sch == null) "No level scheme loaded (offline?): direct decay to the ground state." else "Eₓ is not an ENSDF level: direct decay to the ground state."
            }
        } else cascadeNote = ""
    }
    val all = reactionLines.flatMap { it.spectrumLines(s.reactions * it.intensity) } + setup.backgroundLines(wb.beamEnergy) + setup.lines
    val top = all.maxOfOrNull { it.energy } ?: 0.0
    LaunchedEffect(top) { if (top > setup.maximumEnergy * 0.95) s.setup = setup.copy(maximumEnergy = minOf(20000.0, ((top * 1.1 / 500).roundToInt() + 1) * 500.0)) }
    val input = setup.copy(lines = all)
    var bins by remember { mutableStateOf<List<SpectrumBin>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(input, model) {
        delay(150)
        val result = withContext(Dispatchers.Default) { runCatching { GammaSpectrum.simulate(input, model) } }
        result.onSuccess { bins = it; error = null }.onFailure { error = it.message }
    }
    var logY by remember { mutableStateOf(true) }
    var probe by remember { mutableStateOf<Double?>(null) }

    SectionCard("Spectrum") {
        when {
            all.none { it.enabled } -> Text("No γ lines: ${r.label} to the ground state emits none. Set a residual level, add a contaminant or a source, or switch to Particles.")
            error != null -> Text(error!!, color = MaterialTheme.colorScheme.error)
            bins.isEmpty() -> Text("Calculating…")
            else -> {
                val env = SpectrumPlotSampling.envelope(bins)
                Plot(listOf(PlotSeries(env.map { it.energy to if (logY) max(0.5, it.total) else it.total }, MaterialTheme.colorScheme.primary)),
                    yLog = logY, xLabel = "Energy (keV)", yLabel = "counts/channel", cursor = probe, onPointer = { probe = it }, height = 280.dp)
                probe?.let { e ->
                    val b = bins.minByOrNull { kotlin.math.abs(it.energy - e) }
                    if (b != null) Text("${Fmt.keV(b.energy)} keV · ${Fmt.sig(b.total, 4)} counts (peaks ${Fmt.sig(b.photopeak + b.escape, 3)}, continuum ${Fmt.sig(b.compton, 3)})",
                        style = MaterialTheme.typography.bodySmall)
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Switch(logY, { logY = it }); Text("  Logarithmic counts  ")
                    val export = rememberTextExporter()
                    TextButton(onClick = { export("gamma_spectrum.csv", GammaSpectrum.csv(bins)) }) { Text("Export CSV") }
                }
                var roiLo by remember { mutableStateOf(0.0) }
                var roiHi by remember { mutableStateOf(setup.maximumEnergy) }
                MoreOptions("Region of interest", summary = "${Fmt.sig(roiLo, 4)}–${Fmt.sig(roiHi, 4)} keV") {
                    Row {
                        NumberField("From", roiLo, "keV", Modifier.weight(1f), range = 0.0..20000.0) { roiLo = it }
                        Spacer(Modifier.width(6.dp))
                        NumberField("To", roiHi, "keV", Modifier.weight(1f), range = 0.0..20000.0) { roiHi = it }
                    }
                    if (roiHi > roiLo) {
                        val roi = SpectrumRegion.integrate(bins, setup.maximumEnergy / setup.channels, roiLo, roiHi)
                        ValueRow("Total", Fmt.sig(roi.total, 6)); ValueRow("Photopeaks", Fmt.sig(roi.photopeak, 6))
                        ValueRow("Compton", Fmt.sig(roi.compton, 6)); ValueRow("Escape", Fmt.sig(roi.escape, 6))
                        ValueRow("Flat background", Fmt.sig(roi.background, 6))
                        TextButton(onClick = { probe?.let { p -> roiLo = p - 10; roiHi = p + 10 } }) { Text("Centre ±10 keV on the cursor") }
                    } else Text("The upper limit must exceed the lower one.", color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
    SectionCard("In the spectrum") {
        MoreOptions("Reaction γ rays", summary = if (reactionLines.isEmpty()) "none for this final state" else "${reactionLines.size} line(s)", initiallyOpen = true) {
            NumberField("Reactions", s.reactions, "", range = 0.0..1e15) { s.reactions = it }
            for (g in reactionLines) ValueRow("${Fmt.keV(g.meanEnergy)} keV", Fmt.sig(100 * g.intensity, 3) + " %", note = g.label +
                if (g.halfWidth > 0.05 && g.fractionInFlight > 0.01) " · Doppler ±${Fmt.sig(g.halfWidth, 3)} keV" else "")
            Text("Energies at ${Fmt.fixed(geo.angle, 1)}° with recoil and Doppler corrections. $cascadeNote", style = MaterialTheme.typography.bodySmall)
        }
        val on = setup.backgrounds.count { it.enabled }
        MoreOptions("Contaminants & background", summary = if (on == 0) "none" else "$on on") {
            for (entry in setup.backgrounds) {
                val src = BackgroundLibrary.source(entry.id) ?: continue
                val lines = src.lines(wb.beamEnergy, geo)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(src.name, fontWeight = FontWeight.Medium)
                        Text(if (lines.isEmpty()) "Closed at this beam energy" else lines.joinToString(", ") { Fmt.keV(it.meanEnergy) } + " keV",
                            style = MaterialTheme.typography.bodySmall)
                    }
                    TextButton(onClick = { s.setup = setup.copy(backgrounds = setup.backgrounds - entry) }) { Text("✕", Modifier.semantics { contentDescription = "Remove" }) }
                }
                NumberField(if (src.notation == null) "Counts, strongest line" else "Counts per γ ray", entry.counts, "", range = 0.0..1e12) { v ->
                    s.setup = setup.copy(backgrounds = setup.backgrounds.map { if (it.id == entry.id) it.copy(counts = v) else it })
                }
            }
            var menu by remember { mutableStateOf(false) }
            Box {
                OutlinedButton(onClick = { menu = true }) { Text("Add contaminant or background") }
                DropdownMenu(menu, { menu = false }) {
                    val avail = BackgroundLibrary.beamInduced.filter { b -> setup.backgrounds.none { it.id == b.id } && b.applies(r.projectile, wb.beamEnergy) }
                    if (avail.isEmpty()) DropdownMenuItem(text = { Text("No beam-induced lines for this beam") }, onClick = {}, enabled = false)
                    for (b in avail) DropdownMenuItem(text = { Text(b.name) }, onClick = { s.setup = setup.copy(backgrounds = setup.backgrounds + BackgroundEntry(b.id)); menu = false })
                    HorizontalDivider()
                    for (b in BackgroundLibrary.room.filter { b -> setup.backgrounds.none { it.id == b.id } })
                        DropdownMenuItem(text = { Text("Room: ${b.name}") }, onClick = { s.setup = setup.copy(backgrounds = setup.backgrounds + BackgroundEntry(b.id, 300.0)); menu = false })
                }
            }
            Text("Only reactions open for this beam are offered; energies follow the beam energy and the detector angle.", style = MaterialTheme.typography.bodySmall)
        }
        MoreOptions("Calibration sources & custom lines", summary = if (setup.lines.isEmpty()) "none" else "${setup.lines.size} line(s)") {
            for (line in setup.lines) Row(verticalAlignment = Alignment.CenterVertically) {
                Text("${line.name} · ${Fmt.keV(line.energy)} keV · ${Fmt.sig(line.counts, 3)}", Modifier.weight(1f))
                TextButton(onClick = { s.setup = setup.copy(lines = setup.lines - line) }) { Text("✕", Modifier.semantics { contentDescription = "Remove" }) }
            }
            var menu by remember { mutableStateOf(false) }
            Box {
                OutlinedButton(onClick = { menu = true }) { Text("Add calibration source") }
                DropdownMenu(menu, { menu = false }) {
                    for (src in CalibrationSources.all) DropdownMenuItem(text = { Text(src.label) }, onClick = {
                        val lines = src.prominentLines(1.0).filter { it.energy in 1.0..20000.0 }
                        val strongest = lines.maxOfOrNull { it.intensity } ?: 1.0
                        s.setup = setup.copy(lines = setup.lines + lines.map { SpectrumLine(src.id, it.energy, 1000 * it.intensity / strongest) })
                        menu = false
                    })
                }
            }
        }
    }
    SectionCard("Detector", footer = "Deterministic response: Gaussian photopeaks, single-scatter Compton continuum, escape peaks scaled with the NIST XCOM pair fraction. No summing or pile-up.") {
        var menu by remember { mutableStateOf(false) }
        Box {
            PickerField("Detector", ResolutionModel.presets[DetectorSettings.preset].name) { menu = true }
            DropdownMenu(menu, { menu = false }) {
                ResolutionModel.presets.forEachIndexed { i, p -> DropdownMenuItem(text = { Text(p.name) }, onClick = {
                    DetectorSettings.choosePreset(i); menu = false
                    DetectorCrystal.matching(p.name)?.let { c -> s.setup = setup.copy(escape = setup.escape.copy(crystal = c,
                        singleAtReference = c.typicalEscape.first, doubleAtReference = c.typicalEscape.second)) }
                }) }
            }
        }
        ValueRow("FWHM at 1332 keV", Fmt.sig(model.fwhm(1332.5), 3), "keV")
        Text("Angle to beam ${Fmt.fixed(geo.angle, 1)}°")
        Slider(geo.angle.toFloat(), { s.setup = setup.copy(geometry = geo.copy(angle = (it * 2).roundToInt() / 2.0)) }, valueRange = 0f..180f)
        MoreOptions("More detector settings", summary = "escape peaks ${if (setup.escape.enabled) "on" else "off"} · recoils ${if (geo.recoilsStop) "stop" else "fly"}") {
            NumberField("Half-opening", geo.halfOpening, "°", range = 0.0..90.0) { s.setup = setup.copy(geometry = geo.copy(halfOpening = it)) }
            Row(verticalAlignment = Alignment.CenterVertically) { Switch(geo.recoilsStop, { s.setup = setup.copy(geometry = geo.copy(recoilsStop = it)) }); Text("  Recoils stop in the target (solid)") }
            if (geo.recoilsStop) NumberField("Stopping time", geo.stoppingTime * 1e12, "ps", range = 0.01..100.0) { s.setup = setup.copy(geometry = geo.copy(stoppingTime = it * 1e-12)) }
            Row(verticalAlignment = Alignment.CenterVertically) { Switch(setup.escape.enabled, { s.setup = setup.copy(escape = setup.escape.copy(enabled = it)) }); Text("  Single and double escape peaks") }
            if (setup.escape.enabled) {
                NumberField("SE / peak at 6 MeV", setup.escape.singleAtReference, "", range = 0.0..20.0) { s.setup = setup.copy(escape = setup.escape.copy(singleAtReference = it)) }
                NumberField("DE / peak at 6 MeV", setup.escape.doubleAtReference, "", range = 0.0..20.0) { s.setup = setup.copy(escape = setup.escape.copy(doubleAtReference = it)) }
            }
        }
    }
    SectionCard {
        MoreOptions("Energy window and continuum", summary = "${Fmt.sig(setup.maximumEnergy, 4)} keV · ${setup.channels} ch") {
            NumberField("Maximum energy", setup.maximumEnergy, "keV", range = 1.0..20000.0) { s.setup = setup.copy(maximumEnergy = it) }
            Choice(listOf(1024 to "1024", 2048 to "2048", 4096 to "4096", 8192 to "8192"), setup.channels) { s.setup = setup.copy(channels = it) }
            NumberField("Flat background", setup.background, "counts/keV", range = 0.0..1e8) { s.setup = setup.copy(background = it) }
            NumberField("Compton / peak", setup.continuumRatio, "", range = 0.0..100.0) { s.setup = setup.copy(continuumRatio = it) }
        }
    }
}

@Composable
private fun ParticleSection(wb: Workbench, r: Reaction) {
    val s = SpectrumState
    val det = s.particle
    val material: StoppingTarget? = wb.run.target()
    val groups = remember(r, wb.beamEnergy, wb.residualExcitation, material, det) {
        runCatching { ParticleSpectrum.groups(r, wb.beamEnergy, wb.residualExcitation, material, det) }.getOrDefault(emptyList())
    }
    val seen = groups.filter { it.detected != null && !it.neutral }
    val maxR = seen.mapNotNull { it.rutherford }.maxOrNull() ?: 1.0
    SectionCard("At the detector", footer = "Reaction peaks have unit area; elastic peaks are scaled among themselves by the Rutherford cross section per target atom. Energy loss in the target is not included.") {
        if (seen.isNotEmpty()) {
            val top = seen.maxOf { it.detected!! + 3 * it.fwhm } * 1.05
            val colors = listOf(MaterialTheme.colorScheme.primary, Color(0xFF9E9E9E))
            Plot(seen.map { g ->
                val e = g.detected!!; val sg = max(g.fwhm, 0.5) / 2.3548
                val area = g.rutherford?.let { it / maxR } ?: 1.0
                PlotSeries((0..80).map { i -> val x = e - 4 * sg + 8 * sg * i / 80; x to area * exp(-0.5 * ((x - e) / sg).pow(2)) / sg },
                    if (g.kind == ParticleGroup.Kind.REACTION) colors[0] else colors[1])
            } + PlotSeries(listOf(0.0 to 0.0, top to 0.0), Color.Transparent), xLabel = "Energy (keV)", yLabel = "relative")
        } else if (groups.isEmpty()) Text("No particles at this angle.")
        for (g in groups) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("${g.particle}  ${g.origin}", fontWeight = FontWeight.Medium)
                    if (g.detected?.let { kotlin.math.abs(it - g.emitted) > 0.05 } != false) Text("${Fmt.keV(g.emitted)} keV before foils", style = MaterialTheme.typography.bodySmall)
                    g.rutherford?.let { Text("Rutherford ${Fmt.sig(it, 3)} b/sr per target atom", style = MaterialTheme.typography.bodySmall) }
                }
                Text(when {
                    g.neutral -> "neutral"
                    g.detected != null -> "${Fmt.keV(g.detected!!)} keV\nFWHM ${Fmt.sig(g.fwhm, 3)}"
                    else -> "stopped in foil ${(g.stoppedIn ?: 0) + 1}"
                }, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
    SectionCard("Detector") {
        Text("Angle ${Fmt.fixed(det.angle, 1)}°")
        Slider(det.angle.toFloat(), { s.particle = det.copy(angle = (it * 2).roundToInt() / 2.0) }, valueRange = 1f..179f)
        NumberField("Resolution", det.resolution, "keV FWHM", range = 0.1..1000.0) { s.particle = det.copy(resolution = it) }
        MoreOptions("Foils, opening, elastic", summary = "${det.foils.size} foil(s) · elastic ${if (det.showElastic) "on" else "off"}") {
            NumberField("Half-opening", det.halfOpening, "°", range = 0.0..45.0) { s.particle = det.copy(halfOpening = it) }
            Row(verticalAlignment = Alignment.CenterVertically) { Switch(det.showElastic, { s.particle = det.copy(showElastic = it) }); Text("  Elastic scattering on the target") }
            det.foils.forEachIndexed { i, f ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("${f.material.name}", Modifier.weight(1f))
                    NumberField("Thickness", f.thickness / 1e4, "µm", Modifier.weight(1f), range = 0.0..1e6) { v ->
                        s.particle = det.copy(foils = det.foils.mapIndexed { j, x -> if (j == i) x.copy(thickness = v * 1e4) else x }) }
                    TextButton(onClick = { s.particle = det.copy(foils = det.foils.filterIndexed { j, _ -> j != i }) }) { Text("✕", Modifier.semantics { contentDescription = "Remove" }) }
                }
            }
            var picking by remember { mutableStateOf(false) }
            if (picking) MaterialPickerDialog(onDismiss = { picking = false }) { t, _ -> s.particle = det.copy(foils = det.foils + DetectorFoil(t, 1e4)); picking = false }
            OutlinedButton(onClick = { picking = true }) { Text("Add absorber foil") }
        }
    }
}
