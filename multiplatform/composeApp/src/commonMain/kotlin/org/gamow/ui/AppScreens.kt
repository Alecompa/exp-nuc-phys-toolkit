package org.gamow.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import org.gamow.core.*
import org.gamow.core.astro.NarrowResonance
import org.gamow.core.astro.SFactorModel
import org.gamow.core.exfor.ExforClient
import org.gamow.core.exfor.ExforIndex
import org.gamow.core.spectra.LiveChartClient

// MARK: Experiments

/** A run of an experiment: label, collected charge and live time. */
data class RunRecord(val date: Double, val label: String, val charge: Double, val liveTime: Double, val note: String)

/**
 * A named snapshot of the setup. The JSON uses the keys of the iOS `ExperimentSetup` for the fields both apps share
 * (reaction, energies, target thickness and tilt, T₉, S(E), resonances, screening, abundance, beam), so iOS exports
 * can be imported here; target material and detector settings are platform specific and not exchanged.
 */
data class Experiment(val id: String, val name: String, val created: Double, val setup: Map<String, Any?>, val runs: List<RunRecord>)

object ExperimentStore {
    private const val RS = '\u001E'
    var experiments by mutableStateOf(load())
        private set

    private fun load(): List<Experiment> = (Prefs.get("experiments") ?: "").split(RS).mapNotNull { fromJson(it) }
    private fun save() = Prefs.put("experiments", experiments.joinToString(RS.toString()) { toJson(it) })

    fun add(e: Experiment) { experiments = listOf(e) + experiments; save() }
    fun update(e: Experiment) { experiments = experiments.map { if (it.id == e.id) e else it }; save() }
    fun remove(id: String) { experiments = experiments.filter { it.id != id }; save() }

    /** The shared setup fields, keyed as in the iOS ExperimentSetup. */
    fun snapshot(wb: Workbench): Map<String, Any?> {
        val p = wb.run.profile()
        return linkedMapOf(
            "version" to 1, "reactionText" to wb.reactionText, "beamEnergy" to wb.beamEnergy,
            "residualExcitation" to wb.residualExcitation, "layerThickness" to wb.run.thickness, "layerAngle" to wb.run.tilt,
            "temperatureT9" to wb.t9, "screeningPotential" to p.screening, "isotopicAbundance" to p.abundance,
            "beamCurrent" to wb.run.current, "chargeState" to wb.run.chargeState, "channelRadiusR0" to 1.25,
            "sFactorModel" to linkedMapOf("kind" to p.model.kind.name.lowercase(), "s0" to p.model.s0, "s1" to p.model.s1, "s2" to p.model.s2,
                "table" to p.model.table.map { linkedMapOf("energy" to it.energy, "s" to it.s) }),
            "resonances" to p.resonances.map { linkedMapOf("energy" to it.energy, "strength" to it.strength) },
        )
    }

    /** Applies a snapshot (iOS or Android) to the setup; returns an error text or null. */
    @Suppress("UNCHECKED_CAST")
    fun restore(setup: Map<String, Any?>, wb: Workbench): String? {
        val text = setup["reactionText"] as? String ?: return "No reaction in this setup."
        val r = runCatching { Reaction.parse(text) }.getOrElse { return it.message ?: "Invalid reaction “$text”." }
        fun d(k: String) = (setup[k] as? Double)
        wb.setReaction(r)
        d("beamEnergy")?.let { wb.updateBeam(it) }
        d("residualExcitation")?.let { wb.updateExcitation(it) }
        d("temperatureT9")?.let { wb.updateT9(it) }
        d("layerThickness")?.let { wb.run.updateThickness(it) }
        d("layerAngle")?.let { wb.run.updateTilt(it) }
        d("beamCurrent")?.let { wb.run.updateCurrent(it) }
        d("chargeState")?.let { wb.run.updateCharge(it.toInt()) }
        val p = wb.run.profile(r)
        val m = setup["sFactorModel"] as? Map<String, Any?>
        val model = m?.let {
            SFactorModel(if ((it["kind"] as? String) == "table") SFactorModel.Kind.TABLE else SFactorModel.Kind.POLYNOMIAL,
                it["s0"] as? Double ?: 1.0, it["s1"] as? Double ?: 0.0, it["s2"] as? Double ?: 0.0,
                (it["table"] as? List<Map<String, Any?>>)?.mapNotNull { pt -> (pt["energy"] as? Double)?.let { e -> (pt["s"] as? Double)?.let { SFactorModel.Point(e, it) } } } ?: emptyList())
        }
        val res = (setup["resonances"] as? List<Map<String, Any?>>)?.mapNotNull { x ->
            (x["energy"] as? Double)?.let { e -> (x["strength"] as? Double)?.let { NarrowResonance(e, it) } } }
        wb.run.update(p.copy(model = model ?: p.model, resonances = res ?: p.resonances, screening = d("screeningPotential") ?: p.screening,
            abundance = d("isotopicAbundance") ?: p.abundance, placeholder = if (model != null) false else p.placeholder))
        return null
    }

    fun toJson(e: Experiment): String = json(linkedMapOf("id" to e.id, "name" to e.name, "created" to e.created, "setup" to e.setup,
        "runs" to e.runs.map { linkedMapOf("date" to it.date, "label" to it.label, "charge" to it.charge, "liveTime" to it.liveTime, "note" to it.note) }))

    @Suppress("UNCHECKED_CAST")
    fun fromJson(text: String): Experiment? = runCatching {
        val o = MiniJson.parse(text) as Map<String, Any?>
        // An iOS export is the bare setup; an Android one wraps it with a name and runs.
        val setup = (o["setup"] as? Map<String, Any?>) ?: o.takeIf { "reactionText" in it } ?: return null
        Experiment(o["id"] as? String ?: "e" + (nowEpochSeconds() * 1000).toLong(), o["name"] as? String ?: (setup["reactionText"] as String),
            o["created"] as? Double ?: nowEpochSeconds(), setup,
            (o["runs"] as? List<Map<String, Any?>>)?.map { RunRecord(it["date"] as? Double ?: 0.0, it["label"] as? String ?: "",
                it["charge"] as? Double ?: 0.0, it["liveTime"] as? Double ?: 0.0, it["note"] as? String ?: "") } ?: emptyList())
    }.getOrNull()

    private fun json(v: Any?): String = when (v) {
        null -> "null"
        is String -> buildString {
            append('"')
            for (c in v) when {
                c == '"' -> append("\\\"")
                c == '\\' -> append("\\\\")
                c == '\n' -> append("\\n")
                c.code < 0x20 -> append("\\u").append(c.code.toString(16).padStart(4, '0'))   // all control characters, incl. our separators
                else -> append(c)
            }
            append('"')
        }
        is Double -> if (v.isFinite()) v.toString() else "null"
        is Number, is Boolean -> v.toString()
        is Map<*, *> -> v.entries.joinToString(",", "{", "}") { (k, x) -> json(k.toString()) + ":" + json(x) }
        is List<*> -> v.joinToString(",", "[", "]") { json(it) }
        else -> json(v.toString())
    }
}

@Composable
fun ExperimentsScreen(wb: Workbench, onRestored: () -> Unit) {
    val export = rememberTextExporter()
    var name by remember { mutableStateOf("") }
    var message by remember { mutableStateOf<String?>(null) }
    var open by remember { mutableStateOf<String?>(null) }
    val pick = rememberFilePicker { fileName, bytes ->
        val e = ExperimentStore.fromJson(bytes.decodeToString())
        if (e == null) message = "$fileName is not a Gamow setup." else { ExperimentStore.add(e.copy(id = "e" + (nowEpochSeconds() * 1000).toLong())); message = "Imported ${e.name}." }
    }
    SectionCard("Save the current setup", footer = "A setup keeps the reaction, energies, target thickness and tilt, T₉, S(E), resonances, screening, abundance and beam. Import reads Gamow setups from this app or exported by the iOS app.") {
        Text("${wb.reaction?.label ?: wb.reactionText} · ${Fmt.fixed(wb.beamEnergy, 1)} keV", style = MaterialTheme.typography.bodyMedium)
        OutlinedTextField(name, { name = it }, label = { Text("Name, e.g. 14N(p,γ) week 47") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = {
                val now = nowEpochSeconds()
                ExperimentStore.add(Experiment("e" + (now * 1000).toLong(), name.ifBlank { wb.reaction?.label ?: wb.reactionText }, now, ExperimentStore.snapshot(wb), emptyList()))
                name = ""; message = "Saved."
            }) { Text("Save setup") }
            OutlinedButton(onClick = pick) { Text("Import JSON") }
        }
        message?.let { Text(it, color = MaterialTheme.colorScheme.primary) }
    }
    for (e in ExperimentStore.experiments) {
        SectionCard {
            Row(Modifier.fillMaxWidth().clickable { open = if (open == e.id) null else e.id }, verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(e.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text("${e.setup["reactionText"]} · ${(e.setup["beamEnergy"] as? Double)?.let { Fmt.fixed(it, 1) } ?: "—"} keV · ${formatDate(e.created)}",
                        style = MaterialTheme.typography.bodySmall)
                }
                Text(if (open == e.id) "▾" else "▸", color = MaterialTheme.colorScheme.primary)
            }
            val totalQ = e.runs.sumOf { it.charge }; val totalT = e.runs.sumOf { it.liveTime }
            if (e.runs.isNotEmpty()) Text("${e.runs.size} run(s) · ${Fmt.sig(totalQ, 4)} C · ${durationText(totalT).let { "${it.first} ${it.second}" }} live",
                style = MaterialTheme.typography.bodyMedium)
            if (open == e.id) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { message = ExperimentStore.restore(e.setup, wb) ?: "Restored ${e.name}."; if (message!!.startsWith("Restored")) onRestored() }) { Text("Restore") }
                    OutlinedButton(onClick = { export("${e.name.filter { it.isLetterOrDigit() || it == '_' }.ifEmpty { "gamow_setup" }}.json", ExperimentStore.toJson(e)) }) { Text("Export") }
                    TextButton(onClick = { ExperimentStore.remove(e.id) }) { Text("Delete") }
                }
                Text("Runs", style = MaterialTheme.typography.labelLarge)
                for (run in e.runs) ValueRow(run.label.ifBlank { formatDate(run.date) }, "${Fmt.sig(run.charge, 4)} C · ${Fmt.sig(run.liveTime, 4)} s", note = run.note.ifBlank { null })
                var label by remember(e.id) { mutableStateOf("") }
                var q by remember(e.id) { mutableStateOf(0.0) }
                var t by remember(e.id) { mutableStateOf(0.0) }
                var note by remember(e.id) { mutableStateOf("") }
                MoreOptions("Add a run", summary = "label, charge, live time") {
                    OutlinedTextField(label, { label = it }, label = { Text("Run (e.g. run 1234)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    NumberField("Charge", q, "C", range = 0.0..1e6) { q = it }
                    NumberField("Live time", t, "s", range = 0.0..1e9) { t = it }
                    OutlinedTextField(note, { note = it }, label = { Text("Note") }, modifier = Modifier.fillMaxWidth())
                    Button(onClick = { ExperimentStore.update(e.copy(runs = e.runs + RunRecord(nowEpochSeconds(), label, q, t, note))); label = ""; q = 0.0; t = 0.0; note = "" }) { Text("Add run") }
                }
            }
        }
    }
}

// MARK: Settings and about

@Composable
fun SettingsScreen() {
    val uri = LocalUriHandler.current
    var exfor by remember { mutableStateOf(ExforClient.shared.cacheUsage()) }
    var levels by remember { mutableStateOf(LiveChartClient.shared.cacheUsage()) }
    fun mb(b: Long) = Fmt.sig(b / 1e6, 3) + " MB"
    SectionCard("Downloaded data", footer = "EXFOR tables (GitHub mirror of the IAEA tables, pinned snapshot ${ExforIndex.bundled.date}) and ENSDF level schemes (IAEA LiveChart, refreshed after 30 days) are cached for offline use.") {
        ValueRow("EXFOR tables", "${exfor.second} files · ${mb(exfor.first)}")
        TextButton(onClick = { ExforClient.shared.clearCache(); exfor = ExforClient.shared.cacheUsage() }) { Text("Clear EXFOR cache") }
        ValueRow("ENSDF level schemes", "${levels.second} files · ${mb(levels.first)}")
        TextButton(onClick = { LiveChartClient.shared.clearCache(); levels = LiveChartClient.shared.cacheUsage() }) { Text("Clear level-scheme cache") }
    }
    SectionCard("About Gamow", footer = "Results are meant for planning and teaching: check numbers that matter for an experiment, a safety assessment or a publication against the primary references.") {
        Text("A pocket toolkit for experimental nuclear astrophysics. Free and open source (MIT licence); no account, tracking or ads.")
        TextButton(onClick = { uri.openUri("https://github.com/Alecompa/exp-nuc-phys-toolkit") }) { Text("Source code on GitHub") }
    }
    SectionCard("Data and licences") {
        for ((what, ref) in listOf(
            "Atomic masses" to "AME2020, M. Wang et al., Chin. Phys. C 45, 030003 (2021)",
            "Half-lives, Jπ, isomers" to "NUBASE2020, F. G. Kondev et al., Chin. Phys. C 45, 030001 (2021)",
            "Levels, γ rays, decay radiation" to "ENSDF via the IAEA LiveChart of Nuclides",
            "Measured cross sections" to "EXFOR (N. Otuka et al., NDS 120, 272 (2014)) via IAEA-NDS/exfortables_py — CC BY-SA 4.0",
            "Stopping powers" to "SRIM-2013 (J. F. Ziegler et al., NIM B 268, 1818 (2010)) — non-commercial use only",
            "Stopping code" to "LunaSRIM by J. Skowronski (MIT)",
            "Photon attenuation, pair production" to "NIST XCOM and NISTIR 5632 (public domain)",
            "Constants" to "CODATA 2018",
        )) ValueRow(what, "", note = ref)
        Text("Because the SRIM data may only be used non-commercially, Gamow is and will stay free.", style = MaterialTheme.typography.bodySmall)
    }
}
