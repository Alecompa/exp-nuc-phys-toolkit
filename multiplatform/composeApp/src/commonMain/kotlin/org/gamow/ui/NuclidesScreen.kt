package org.gamow.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import org.gamow.core.*
import org.gamow.core.exfor.ExforIndex

/** Separation energy of a particle (n, p, α…) from a nuclide, keV, from AME2020 atomic mass excesses; null if unbound data are missing. */
fun separationEnergy(n: Nuclide, particle: Nuclide, table: MassTable = MassTable.ame2020): Double? {
    val daughter = table.nuclide(n.z - particle.z, n.a - particle.a) ?: return null
    return daughter.massExcess + particle.massExcess - n.massExcess
}

/** Browse AME2020 and NUBASE2020: search, then a page per nuclide with reactions on it one tap away. */
@Composable
fun NuclidesScreen(wb: Workbench, onUseReaction: () -> Unit) {
    var query by remember { mutableStateOf("") }
    var selected by remember { mutableStateOf<Nuclide?>(wb.reaction?.target) }
    val table = MassTable.ame2020
    val results = remember(query) {
        val q = query.trim()
        if (q.isEmpty()) emptyList() else {
            table.nuclide(named = q)?.let { listOf(it) } ?: run {
                val digits = q.filter { it.isDigit() }; val letters = q.filter { it.isLetter() }
                val zs = (1..118).filter { z -> letters.isEmpty() || (Elements.symbol(z) ?: "").equals(letters, true) ||
                    (Elements.name(z) ?: "").startsWith(letters, true) }
                table.nuclides.filter { it.z in zs && (digits.isEmpty() || it.a.toString().startsWith(digits)) }.take(80)
            }
        }
    }
    SectionCard {
        OutlinedTextField(query, { query = it }, label = { Text("Search: 26Al, Mg, magnesium, 26") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        for (n in results) {
            val g = Nubase.nubase2020.groundState(n.z, n.a)
            Row(Modifier.fillMaxWidth().clickable { selected = n; query = "" }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(n.label, Modifier.width(70.dp), fontWeight = FontWeight.SemiBold)
                Text(n.elementName, Modifier.weight(1f))
                Text(g?.let { if (it.isStable) (it.abundance?.let { a -> "stable · ${Fmt.sig(a, 4)} %" } ?: "stable") else halfLifeText(it) } ?: "",
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
    selected?.let { NuclideDetail(it, wb, onUseReaction) }
}

@Composable
private fun NuclideDetail(n: Nuclide, wb: Workbench, onUseReaction: () -> Unit) {
    val table = MassTable.ame2020
    val states = Nubase.nubase2020.states(n.z, n.a)
    val g = states.firstOrNull { it.state == 0 }
    SectionCard {
        Text(n.label, style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold)
        Text("${n.elementName} · Z = ${n.z}, N = ${n.n}, A = ${n.a}", color = MaterialTheme.colorScheme.onSurfaceVariant)
        g?.let { s ->
            Text(when {
                s.isStable -> "Stable" + (s.abundance?.let { " · natural abundance ${Fmt.sig(it, 5)} %" } ?: "")
                else -> "T½ = ${halfLifeText(s)}" + if (s.decayModes.isNotEmpty()) " · " + s.decayModes.take(3).joinToString(", ") { it.text } else ""
            }, style = MaterialTheme.typography.titleMedium)
            if (s.spinParity.isNotEmpty()) Text("Jπ = ${s.spinParity}" + if (s.spinParityIsEstimated) " (systematics)" else "")
        }
    }
    SectionCard("Reactions on ${n.label} as target", footer = "Sets the shared reaction; the numbers in brackets are EXFOR tables in the bundled index.") {
        val index = ExforIndex.bundled
        @OptIn(ExperimentalLayoutApi::class)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            for (notation in listOf("(p,g)", "(a,g)", "(p,a)", "(p,n)", "(a,n)", "(a,p)", "(p,p)", "(d,p)")) {
                val r = runCatching { Reaction.parse(n.plainLabel + notation) }.getOrNull() ?: continue
                val count = runCatching { index.datasets(r).size }.getOrDefault(0)
                AssistChip(onClick = { wb.setReaction(r); onUseReaction() },
                    label = { Text(r.label + if (count > 0) "  [$count]" else "") })
            }
        }
    }
    ExforChannelsSection(n, wb, onUseReaction)
    SectionCard("Mass (AME2020)") {
        ValueRow("Mass excess Δ", "${Fmt.keV(n.massExcess)} ± ${Fmt.sig(n.massExcessUncertainty, 2)}", "keV",
            note = if (n.isEstimated) "Estimated from systematics (#)" else null)
        ValueRow("Atomic mass", Fmt.fixed(n.atomicMass / PhysicalConstants.ATOMIC_MASS_UNIT * 1e6, 3), "µu")
        ValueRow("Binding energy per nucleon", Fmt.fixed(n.bindingEnergyPerNucleon, 3), "keV")
        for ((label, particle) in listOf("Sₙ" to "n", "Sₚ" to "p", "S_α" to "a", "S_d" to "d")) {
            val p = table.nuclide(named = particle) ?: continue
            separationEnergy(n, p)?.let { ValueRow("$label (${p.reactionLabel} separation)", Fmt.keV(it), "keV",
                note = if (it < 0) "Unbound to ${p.reactionLabel} emission" else null) }
        }
    }
    val isomers = states.filter { it.state > 0 }
    if (isomers.isNotEmpty()) SectionCard("Isomers (NUBASE2020)") {
        for (s in isomers) ValueRow(s.label, halfLifeText(s), note = "Eₓ = ${Fmt.keV(s.excitation)} keV" +
            if (s.spinParity.isNotEmpty()) " · ${s.spinParity}" else "")
    }
    LevelsSection(n, wb)
}
