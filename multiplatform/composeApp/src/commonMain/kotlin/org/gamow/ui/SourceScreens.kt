package org.gamow.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import org.gamow.core.*
import kotlin.math.pow

val activityUnits = listOf(1.0 to "Bq", 1e3 to "kBq", 1e6 to "MBq", 1e9 to "GBq", 3.7e4 to "µCi", 3.7e7 to "mCi")
val timeUnits = listOf(1.0 to "s", 60.0 to "min", 3600.0 to "h", 86400.0 to "d", HalfLifeFormat.YEAR to "y")

fun activityText(bq: Double): String {
    val u = activityUnits.take(4).lastOrNull { bq >= it.first } ?: activityUnits.first()
    return "${Fmt.sig(bq / u.first, 4)} ${u.second}"
}

// MARK: Decay calculator

@Composable
fun DecayScreen() {
    var nuclide by remember { mutableStateOf(Prefs.get("decay.nuclide") ?: "60Co") }
    var picking by remember { mutableStateOf(false) }
    var a0 by remember { mutableStateOf(Prefs.get("decay.a0")?.toDoubleOrNull() ?: 1e4) }
    var a0Unit by remember { mutableStateOf(1e3) }
    var t by remember { mutableStateOf(Prefs.get("decay.t")?.toDoubleOrNull() ?: HalfLifeFormat.YEAR) }
    var tUnit by remember { mutableStateOf(HalfLifeFormat.YEAR) }
    var custom by remember { mutableStateOf<Double?>(null) }
    val state = Nubase.nubase2020.state(nuclide)
    val h = custom ?: state?.halfLife
    if (picking) NuclidePickerDialog(nuclide, { picking = false }) { nuclide = it.plainLabel; Prefs.put("decay.nuclide", nuclide); picking = false }

    SectionCard {
        if (h != null && h.isFinite() && h > 0) {
            HeroNumber(activityText(RadioactiveDecay.activity(a0, t, h)).substringBefore(' '),
                activityText(RadioactiveDecay.activity(a0, t, h)).substringAfter(' '),
                "${state?.label ?: "Custom"} after ${Fmt.sig(t / tUnit, 4)} ${timeUnits.first { it.first == tUnit }.second}")
            Text("${Fmt.sig(100 * 0.5.pow(t / h), 3)} % left · T½ ${formatHalfLife(h)}", style = MaterialTheme.typography.bodyMedium)
        } else Text("Choose a radioactive nuclide.")
    }
    SectionCard("Inputs") {
        PickerField("Nuclide", state?.let { "${it.label}   ·   T½ ${halfLifeText(it)}" } ?: nuclide) { picking = true }
        ValueWithUnit("Activity at the start", a0, a0Unit, activityUnits.take(4), { it }) { v, u -> a0 = v; a0Unit = u; Prefs.put("decay.a0", "$v") }
        ValueWithUnit("Elapsed time", t, tUnit, timeUnits, { it }) { v, u -> t = v; tUnit = u; Prefs.put("decay.t", "$v") }
        MoreOptions("Custom half-life", summary = if (custom == null) "NUBASE2020" else formatHalfLife(custom!!)) {
            var on by remember { mutableStateOf(custom != null) }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Switch(on, { on = it; custom = if (it) (state?.halfLife ?: 3600.0) else null })
                Text("  Use my own half-life")
            }
            if (on) ValueWithUnit("Half-life", custom ?: 3600.0, 3600.0, timeUnits, { it }) { v, _ -> custom = v }
        }
    }
    if (h != null && h.isFinite() && h > 0) {
        val molar = state?.let { s -> MassTable.ame2020.nuclide(s.z, s.a)?.atomicMass?.div(PhysicalConstants.ATOMIC_MASS_UNIT) }
        SectionCard("Results") {
            val atoms = RadioactiveDecay.atoms(a0, h)
            ValueRow("Atoms at the start", Fmt.sig(atoms, 4))
            molar?.let { ValueRow("Mass at the start", Fmt.sig(RadioactiveDecay.mass(atoms, it), 4), "g") }
            ValueRow("Time to 10 %", formatHalfLife(RadioactiveDecay.timeToFraction(0.1, h)))
            ValueRow("Time to 1 %", formatHalfLife(RadioactiveDecay.timeToFraction(0.01, h)))
            state?.let { s -> if (s.decayModes.isNotEmpty()) ValueRow("Decay", s.decayModes.take(3).joinToString(", ") { it.text }) }
        }
    }
}

// MARK: Calibration sources

/** The lab's sources, stored as lines "id;nuclide;name;activityBq;relUnc;referenceDate". */
object LabSources {
    fun load(): List<SourceCertificate> = (Prefs.get("sources") ?: "").lines().mapNotNull { l ->
        val f = l.split(';')
        if (f.size < 6) null else runCatching {
            SourceCertificate(f[0], f[1], f[2], f[3].toDouble(), f[4].toDouble(), f[5].toDouble())
        }.getOrNull()
    }
    fun save(list: List<SourceCertificate>) = Prefs.put("sources", list.joinToString("\n") {
        listOf(it.id, it.nuclide, it.name.replace(";", ","), "${it.activity}", "${it.relativeUncertainty}", "${it.referenceDate}").joinToString(";")
    })
}

@Composable
fun SourcesScreen() {
    var mine by remember { mutableStateOf(LabSources.load()) }
    var editing by remember { mutableStateOf<SourceCertificate?>(null) }
    var open by remember { mutableStateOf<String?>(null) }
    val now = nowEpochSeconds()

    SectionCard("My sources", footer = "Activity today from the certificate and the NUBASE2020 half-life; uncertainties of certificate and half-life combined.") {
        if (mine.isEmpty()) Text("No sources yet. Add the sources of your lab with their certificate activity and date.",
            color = MaterialTheme.colorScheme.onSurfaceVariant)
        for (c in mine) {
            val n = c.activityAt(now)
            Row(Modifier.fillMaxWidth().clickable { open = if (open == c.id) null else c.id }.padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(c.name.ifEmpty { c.state?.label ?: c.nuclide }, fontWeight = FontWeight.Medium)
                    Text("${c.state?.label ?: c.nuclide} · reference ${formatDate(c.referenceDate)}", style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (n != null) Column(horizontalAlignment = Alignment.End) {
                    Text(activityText(n.activity), fontWeight = FontWeight.Medium)
                    Text("± ${Fmt.sig(100 * n.relativeUncertainty, 2)} %", style = MaterialTheme.typography.bodySmall)
                }
            }
            if (open == c.id) {
                CalibrationSources.source(c.nuclide)?.let { SourceLines(it, n?.activity) }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { editing = c }) { Text("Edit") }
                    TextButton(onClick = { mine = mine.filter { it.id != c.id }; LabSources.save(mine) }) { Text("Remove") }
                }
            }
            HorizontalDivider()
        }
        Button(onClick = { editing = SourceCertificate("src" + (now * 1000).toLong(), "137Cs", "", 1e4, 0.015, now) }) { Text("Add source") }
    }
    SectionCard("Catalog", footer = "γ-ray energies and intensities from ENSDF (IAEA LiveChart); half-lives from NUBASE2020. Tap a source for its lines.") {
        for (s in CalibrationSources.all) {
            Row(Modifier.fillMaxWidth().clickable { open = if (open == s.id) null else s.id }.padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(s.label, fontWeight = FontWeight.Medium)
                    Text(s.prominentLines(5.0).filter { it.kind != "xray" }.take(3).joinToString(", ") { Fmt.keV(it.energy) } + " keV",
                        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text(halfLifeText(s.state), style = MaterialTheme.typography.bodyMedium)
            }
            if (open == s.id) SourceLines(s, null)
        }
    }
    editing?.let { c ->
        CertificateDialog(c, onDismiss = { editing = null }) { saved ->
            mine = if (mine.any { it.id == saved.id }) mine.map { if (it.id == saved.id) saved else it } else mine + saved
            LabSources.save(mine); editing = null
        }
    }
}

@Composable
private fun SourceLines(s: CalibrationSource, activity: Double?) {
    Column(Modifier.padding(start = 8.dp, bottom = 6.dp)) {
        var distance by remember { mutableStateOf(1.0) }
        val k = AirKerma.rateConstant(s.lines)
        if (activity != null) {
            NumberField("Distance", distance, "m", range = 0.01..1e3) { distance = it }
            ValueRow("Dose rate (air kerma)", Fmt.sig(AirKerma.rate(s.lines, activity, distance), 3), "µGy/h",
                note = "Unshielded point source, photons above 20 keV")
        } else ValueRow("Air-kerma rate constant", Fmt.sig(k, 3), "µGy m² MBq⁻¹ h⁻¹")
        for (l in s.prominentLines(1.0)) {
            Row {
                Text("${Fmt.keV(l.energy)} keV" + if (l.kind == "xray") " (X)" else if (l.kind == "annihilation") " (β⁺)" else "",
                    Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                Text("${Fmt.sig(l.intensity, 4)} %", style = MaterialTheme.typography.bodyMedium)
                if (activity != null) Text("   ${Fmt.sig(activity * l.intensity / 100, 3)} /s", style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CertificateDialog(initial: SourceCertificate, onDismiss: () -> Unit, onSave: (SourceCertificate) -> Unit) {
    var c by remember { mutableStateOf(initial) }
    var picking by remember { mutableStateOf(false) }
    var datePicking by remember { mutableStateOf(false) }
    var unit by remember { mutableStateOf(1e3) }
    if (picking) NuclidePickerDialog(c.nuclide, { picking = false }) { c = c.copy(nuclide = it.plainLabel); picking = false }
    if (datePicking) {
        val st = rememberDatePickerState(initialSelectedDateMillis = (c.referenceDate * 1000).toLong())
        DatePickerDialog(onDismissRequest = { datePicking = false }, confirmButton = {
            TextButton(onClick = { st.selectedDateMillis?.let { c = c.copy(referenceDate = it / 1000.0) }; datePicking = false }) { Text("OK") }
        }) { DatePicker(st) }
    }
    Dialog(onDismissRequest = onDismiss) {
        Card {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Source certificate", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                PickerField("Nuclide", c.state?.let { "${it.label}   ·   T½ ${halfLifeText(it)}" } ?: c.nuclide) { picking = true }
                OutlinedTextField(c.name, { c = c.copy(name = it) }, label = { Text("Name (e.g. certificate number)") }, singleLine = true,
                    modifier = Modifier.fillMaxWidth())
                ValueWithUnit("Activity on the reference date", c.activity, unit, activityUnits, { it }) { v, u -> c = c.copy(activity = v); unit = u }
                NumberField("Uncertainty", c.relativeUncertainty * 100, "%", range = 0.0..100.0) { c = c.copy(relativeUncertainty = it / 100) }
                PickerField("Reference date", formatDate(c.referenceDate)) { datePicking = true }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = onDismiss) { Text("Cancel") }
                    Button(onClick = { onSave(c) }, enabled = c.activity > 0 && c.state?.isRadioactive == true) { Text("Save") }
                }
            }
        }
    }
}
