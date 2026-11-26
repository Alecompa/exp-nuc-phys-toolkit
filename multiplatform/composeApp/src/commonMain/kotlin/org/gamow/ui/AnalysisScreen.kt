package org.gamow.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.gamow.core.*
import org.gamow.core.spectra.*
import kotlin.math.abs
import kotlin.math.max

internal object AnalysisState {
    var spectrum by mutableStateOf<MeasuredSpectrum?>(null)
    var calibration by mutableStateOf<EnergyCalibration?>(null)
    var result by mutableStateOf<CalibrationResult?>(null)
    var fwhm by mutableStateOf(6.0)
    var threshold by mutableStateOf(5.0)
    var sources by mutableStateOf(setOf("60Co", "137Cs", "152Eu"))
}

/** Import a measured spectrum, find its peaks, calibrate it against known lines and name the peaks. */
@Composable
fun AnalysisScreen(wb: Workbench) {
    val st = AnalysisState
    var error by remember { mutableStateOf<String?>(null) }
    val pick = rememberFilePicker { name, bytes ->
        runCatching { MeasuredSpectrum.read(bytes, name) }
            .onSuccess { st.spectrum = it; st.calibration = it.fileCalibration; st.result = null; error = null }
            .onFailure { error = it.message ?: "Could not read the file." }
    }
    val s = st.spectrum
    if (s == null) {
        SectionCard {
            Text("No spectrum", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
            Text("Open an ORTEC .Spe or .Chn file, or text/CSV with counts, (channel, counts) or (energy, counts).")
            Button(onClick = pick) { Text("Open spectrum") }
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        }
        return
    }
    var peaks by remember(s) { mutableStateOf<List<FoundPeak>>(emptyList()) }
    LaunchedEffect(s, st.fwhm, st.threshold) {
        delay(150)
        peaks = withContext(Dispatchers.Default) { PeakSearch.find(s.counts, st.fwhm, st.threshold) }
    }
    val cal = st.calibration
    fun x(ch: Double) = cal?.energy(ch) ?: ch
    var logY by remember { mutableStateOf(true) }
    var probe by remember { mutableStateOf<Double?>(null) }

    SectionCard(s.name) {
        val pts = s.counts.withIndex().map { (i, c) -> x(i.toDouble()) to if (logY) max(0.5, c) else c }
        val reduced = if (pts.size > 3000) pts.chunked((pts.size + 1499) / 1500).flatMap { ch -> listOf(ch.minBy { it.second }, ch.maxBy { it.second }).sortedBy { it.first } } else pts
        Plot(listOf(PlotSeries(reduced, MaterialTheme.colorScheme.primary),
            PlotSeries(peaks.map { x(it.centroid) to (if (logY) max(1.0, s.counts.getOrElse(it.centroid.toInt()) { 1.0 }) * 1.6 else s.counts.getOrElse(it.centroid.toInt()) { 0.0 }) },
                MaterialTheme.colorScheme.tertiary, line = false)),
            yLog = logY, xLabel = if (cal == null) "Channel" else "Energy (keV)", yLabel = "counts", cursor = probe, onPointer = { probe = it }, height = 300.dp)
        probe?.let { p ->
            val ch = cal?.channel(p) ?: p
            val i = ch.toInt().coerceIn(0, s.counts.size - 1)
            Text((if (cal == null) "ch $i" else "${Fmt.keV(p)} keV (ch $i)") + " · ${Fmt.sig(s.counts[i], 6)} counts", style = MaterialTheme.typography.bodySmall)
        }
        Text("${s.counts.size} channels · ${Fmt.sig(s.counts.sum(), 4)} counts" + (s.liveTime?.let { " · live ${Fmt.sig(it, 5)} s" } ?: ""),
            style = MaterialTheme.typography.bodySmall)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Switch(logY, { logY = it }); Text("  Logarithmic counts  ")
            TextButton(onClick = pick) { Text("Open another") }
        }
    }
    SectionCard("Peak search", footer = "Second-derivative filter matched to the FWHM; areas above a SNIP background. Set the FWHM to the width of a clean peak.") {
        NumberField("Peak FWHM (guess)", st.fwhm, "channels", range = 1.0..500.0) { st.fwhm = it }
        MoreOptions("Threshold", summary = "${Fmt.sig(st.threshold, 2)} σ") { NumberField("Threshold", st.threshold, "σ", range = 2.0..50.0) { st.threshold = it } }
        ValueRow("Peaks found", "${peaks.size}")
    }
    SectionCard("Energy calibration", footer = "Pairs of strong peaks are tried against pairs of reference lines; the gain and offset that put most lines on peaks win, then a weighted fit refines them. Check the residuals.") {
        Text("Reference sources", style = MaterialTheme.typography.labelLarge)
        @OptIn(ExperimentalLayoutApi::class)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (src in CalibrationSources.all) FilterChip(src.id in st.sources, { st.sources = if (src.id in st.sources) st.sources - src.id else st.sources + src.id },
                label = { Text(src.label) })
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = {
                val lines = AutoCalibration.lines(CalibrationSources.all.filter { it.id in st.sources }) +
                    BackgroundLibrary.room.filter { it.id != "511" }.flatMap { b -> b.lines(0.0, GammaGeometry()).map { CalibrationLine(it.restEnergy, 30 * it.intensity, b.name) } }
                val r = AutoCalibration.calibrate(peaks, lines)
                if (r != null) { st.result = r; st.calibration = r.calibration; error = null } else error = "No consistent gain found. Check the FWHM and the sources."
            }, enabled = peaks.size >= 2) { Text("Auto-calibrate") }
            s.fileCalibration?.let { fc -> OutlinedButton(onClick = { st.calibration = fc; st.result = null }) { Text("Use file calibration") } }
        }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        cal?.let {
            ValueRow("Gain", Fmt.sig(it.gain, 6), "keV/ch")
            ValueRow("Offset", Fmt.sig(it.energy(0.0), 5), "keV")
        }
        st.result?.let { r ->
            ValueRow("Matched lines", "${r.matches.size}", note = "RMS ${Fmt.sig(r.rms, 2)} keV")
            for (m in r.matches) ValueRow("${Fmt.keV(m.line.energy)} keV  ${m.line.label}", "${if (m.residual >= 0) "+" else ""}${Fmt.sig(m.residual, 2)} keV",
                note = "ch ${Fmt.fixed(m.peak.centroid, 2)}")
        }
    }
    SectionCard("Peaks", footer = "Areas are net counts within ±1.5 FWHM above the SNIP background: for orientation, not final yields.") {
        val clipboard = LocalClipboardManager.current
        TextButton(onClick = {
            clipboard.setText(AnnotatedString("channel,energy_keV,fwhm_ch,area,d_area,identification\n" + peaks.joinToString("\n") { p ->
                "${Fmt.fixed(p.centroid, 3)},${cal?.let { Fmt.fixed(it.energy(p.centroid), 3) } ?: ""},${Fmt.fixed(p.fwhm, 2)},${Fmt.fixed(p.area, 1)},${Fmt.fixed(p.areaUncertainty, 1)},${identify(p, cal) ?: ""}" }))
        }) { Text("Copy peak list (CSV)") }
        for (p in peaks) Row(Modifier.fillMaxWidth().clickable { probe = x(p.centroid) }.padding(vertical = 3.dp)) {
            Column(Modifier.weight(1f)) {
                Text(cal?.let { "${Fmt.keV(it.energy(p.centroid))} keV" } ?: "ch ${Fmt.fixed(p.centroid, 2)}", fontWeight = FontWeight.Medium)
                identify(p, cal)?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary) }
            }
            Text("${Fmt.sig(p.area, 4)} ± ${Fmt.sig(p.areaUncertainty, 2)}")
        }
    }
}

/** Nearest known line (sources, room background, escape peaks) within 1.5 FWHM. */
private fun identify(p: FoundPeak, cal: EnergyCalibration?): String? {
    cal ?: return null
    val e = cal.energy(p.centroid)
    val tol = max(1.0, 1.5 * p.fwhm * cal.gain)
    val base = CalibrationSources.all.flatMap { s -> s.prominentLines(2.0).map { it.energy to s.label } } +
        BackgroundLibrary.room.flatMap { b -> b.lines(0.0, GammaGeometry()).map { it.restEnergy to b.name } }
    val all = base + base.filter { it.first > 1500 }.flatMap { (en, l) -> listOf(en - 510.999 to "$l SE", en - 1021.998 to "$l DE") }
    val best = all.filter { abs(it.first - e) <= tol }.minByOrNull { abs(it.first - e) } ?: return null
    return "${best.second} ${Fmt.keV(best.first)} keV"
}
