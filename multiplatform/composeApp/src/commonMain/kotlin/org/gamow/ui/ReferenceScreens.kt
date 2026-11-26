package org.gamow.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import org.gamow.core.HalfLifeFormat
import org.gamow.core.Prefs

// Port of ToolkitUI/Screens/Reference/ReferenceViews.swift: constants, unit converter, formula sheet.

// MARK: Constants

data class PhysicalConstant(val name: String, val symbol: String, val value: String, val unit: String, val note: String? = null)

object ReferenceConstants {
    val groups: List<Pair<String, List<PhysicalConstant>>> = listOf(
        "Fundamental" to listOf(
            PhysicalConstant("Speed of light", "c", "299 792 458", "m/s", "Exact"),
            PhysicalConstant("Planck constant (reduced)", "ħ", "6.582 119 569 × 10⁻¹⁶", "eV s"),
            PhysicalConstant("ħc", "ħc", "197.326 980 4", "MeV fm"),
            PhysicalConstant("Elementary charge", "e", "1.602 176 634 × 10⁻¹⁹", "C", "Exact"),
            PhysicalConstant("e²/(4πε₀)", "e²", "1.439 964 548", "MeV fm"),
            PhysicalConstant("Fine-structure constant", "α", "1/137.035 999 084", ""),
            PhysicalConstant("Boltzmann constant", "k", "8.617 333 262 × 10⁻⁵", "eV/K", "kT = 86.173 keV × T₉"),
            PhysicalConstant("Avogadro constant", "Nₐ", "6.022 140 76 × 10²³", "mol⁻¹", "Exact"),
        ),
        "Masses" to listOf(
            PhysicalConstant("Atomic mass unit", "u", "931.494 102 42", "MeV/c²"),
            PhysicalConstant("Electron mass", "mₑ", "0.510 998 950 00", "MeV/c²"),
            PhysicalConstant("Proton mass", "mₚ", "938.272 088 16", "MeV/c²"),
            PhysicalConstant("Neutron mass", "mₙ", "939.565 420 52", "MeV/c²"),
            PhysicalConstant("Deuteron mass", "m_d", "1875.612 942 57", "MeV/c²"),
            PhysicalConstant("α-particle mass", "m_α", "3727.379 4066", "MeV/c²"),
            PhysicalConstant("Neutron–hydrogen mass difference", "Δ", "782.347", "keV"),
        ),
        "Nuclear and atomic" to listOf(
            PhysicalConstant("Bohr radius", "a₀", "0.529 177 210 90", "Å"),
            PhysicalConstant("Classical electron radius", "rₑ", "2.817 940 3262", "fm"),
            PhysicalConstant("Barn", "b", "10⁻²⁴", "cm²", "= 100 fm²"),
            PhysicalConstant("Nuclear radius parameter", "r₀", "1.2–1.4", "fm", "R = r₀ A¹ᐟ³ (convention dependent)"),
            PhysicalConstant("Nuclear magneton", "μ_N", "3.152 451 258 × 10⁻¹⁴", "MeV/T"),
            PhysicalConstant("Ge pair-creation energy", "w", "2.96", "eV", "At 77 K"),
            PhysicalConstant("Si pair-creation energy", "w", "3.62", "eV", "At 300 K"),
        ),
        "Astrophysics" to listOf(
            PhysicalConstant("Solar mass", "M☉", "1.988 47 × 10³⁰", "kg"),
            PhysicalConstant("Solar luminosity", "L☉", "3.828 × 10²⁶", "W", "IAU nominal"),
            PhysicalConstant("Year (Julian)", "yr", "3.155 76 × 10⁷", "s"),
            PhysicalConstant("Gamow energy prefactor", "E_G", "0.9791 Z₁²Z₂² μ", "MeV", "μ in u; E_G = 2μc²(παZ₁Z₂)²"),
            PhysicalConstant("Rate prefactor", "", "3.7318 × 10¹⁰ / T₉³ᐟ²", "",
                "Nₐ⟨σv⟩ = prefactor μ⁻¹ᐟ² ∫ σE e^(−11.605E/T₉) dE, E in MeV, σ in b"),
        ),
    )

    private val superscripts = mapOf('⁰' to '0', '¹' to '1', '²' to '2', '³' to '3', '⁴' to '4', '⁵' to '5', '⁶' to '6',
        '⁷' to '7', '⁸' to '8', '⁹' to '9', '⁻' to '-')

    /** Text to paste: "6.582 119 569 × 10⁻¹⁶" → "6.582119569e-16", "10⁻²⁴" → "1e-24"; expressions are copied as shown. */
    fun clipboardText(value: String): String {
        val s = value.replace(" ", "").replace(" ", "")
        Regex("^([0-9.]+)×10([⁻⁰¹²³⁴⁵⁶⁷⁸⁹]+)$").matchEntire(s)?.let { m ->
            return m.groupValues[1] + "e" + m.groupValues[2].map { superscripts[it] }.joinToString("")
        }
        Regex("^10([⁻⁰¹²³⁴⁵⁶⁷⁸⁹]+)$").matchEntire(s)?.let { m ->
            return "1e" + m.groupValues[1].map { superscripts[it] }.joinToString("")
        }
        return if (Regex("^[0-9./]+$").matches(s)) s else value
    }
}

@Composable
private fun SearchField(query: String, placeholder: String, onChange: (String) -> Unit) {
    OutlinedTextField(query, onChange, placeholder = { Text(placeholder) }, singleLine = true,
        trailingIcon = { if (query.isNotEmpty()) TextButton(onClick = { onChange("") }) { Text("✕", Modifier.semantics { contentDescription = "Remove" }) } },
        modifier = Modifier.fillMaxWidth())
}

@Composable
fun ConstantsScreen() {
    var search by remember { mutableStateOf("") }
    var copied by remember { mutableStateOf<String?>(null) }
    val clipboard = LocalClipboardManager.current
    LaunchedEffect(copied) { if (copied != null) { delay(1500); copied = null } }

    SearchField(search, "Search constants") { search = it }
    copied?.let {
        Text("Copied $it", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(start = 4.dp, top = 6.dp))
    }
    val q = search.trim()
    var any = false
    for ((title, items) in ReferenceConstants.groups) {
        val shown = items.filter { q.isEmpty() || it.name.contains(q, ignoreCase = true) || it.symbol.contains(q, ignoreCase = true) }
        if (shown.isEmpty()) continue
        any = true
        SectionCard(title) {
            for (c in shown) {
                Box(Modifier.fillMaxWidth().clickable {
                    val text = ReferenceConstants.clipboardText(c.value)
                    clipboard.setText(AnnotatedString(text))
                    copied = text
                }) {
                    ValueRow(if (c.symbol.isEmpty()) c.name else "${c.name} ${c.symbol}", c.value, c.unit, c.note)
                }
            }
        }
    }
    if (!any) Text("No constant matches “$search”.", Modifier.padding(8.dp))
    Text("CODATA 2018 recommended values (physics.nist.gov/constants). Tap a value to copy it.",
        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(4.dp))
}

// MARK: Unit converter

/** Unit categories with each unit's size in the category's base unit (same factors as the Swift UnitConverterView). */
enum class UnitQuantity(val title: String, val units: List<Pair<String, Double>>) {
    ENERGY("Energy", listOf("eV" to 1.0, "keV" to 1e3, "MeV" to 1e6, "GeV" to 1e9, "J" to 1 / 1.602_176_634e-19,
        "erg" to 1e-7 / 1.602_176_634e-19, "u c²" to 931.494_102_42e6)),
    TEMPERATURE("Temperature", listOf("T₉" to 1.0, "K" to 1e-9, "kT (keV)" to 1 / 86.173_332_62, "kT (MeV)" to 1000 / 86.173_332_62)),
    CROSS_SECTION("Cross section", listOf("b" to 1.0, "mb" to 1e-3, "µb" to 1e-6, "nb" to 1e-9, "pb" to 1e-12, "fb" to 1e-15,
        "fm²" to 1e-2, "cm²" to 1e24)),
    LENGTH("Length", listOf("fm" to 1.0, "Å" to 1e5, "nm" to 1e6, "µm" to 1e9, "mm" to 1e12, "cm" to 1e13, "m" to 1e15)),
    AREAL_DENSITY("Areal density", listOf("at/cm²" to 1.0, "10¹⁵ at/cm²" to 1e15, "10¹⁸ at/cm²" to 1e18)),
    ACTIVITY("Activity", listOf("Bq" to 1.0, "kBq" to 1e3, "MBq" to 1e6, "GBq" to 1e9, "µCi" to 3.7e4, "mCi" to 3.7e7, "Ci" to 3.7e10)),
    TIME("Time", listOf("s" to 1.0, "min" to 60.0, "h" to 3600.0, "d" to 86400.0, "y" to HalfLifeFormat.YEAR, "ms" to 1e-3,
        "µs" to 1e-6, "ns" to 1e-9, "ps" to 1e-12, "fs" to 1e-15)),
    CHARGE("Charge", listOf("C" to 1.0, "mC" to 1e-3, "µC" to 1e-6, "nC" to 1e-9, "e" to 1.602_176_634e-19));

    /** [value] in unit [from] expressed in unit [to] (indices into [units]). */
    fun convert(value: Double, from: Int, to: Int): Double = value * units[from].second / units[to].second

    fun index(unit: String): Int = units.indexOfFirst { it.first == unit }

    companion object {
        const val AVOGADRO = 6.022_140_76e23
        /** Mass thickness in µg/cm² of [atomsPerCm2] atoms (or formula units) per cm² with molar mass [molarMass] g/mol. */
        fun massThickness(atomsPerCm2: Double, molarMass: Double) = atomsPerCm2 * molarMass / AVOGADRO * 1e6
    }
}

@Composable
fun UnitsScreen() {
    var quantity by remember { mutableStateOf(Prefs.get("units.quantity")?.let { n -> UnitQuantity.entries.firstOrNull { it.name == n } } ?: UnitQuantity.ENERGY) }
    var value by remember { mutableStateOf(Prefs.get("units.value")?.toDoubleOrNull() ?: 1.0) }
    var from by remember { mutableStateOf(Prefs.get("units.from")?.toIntOrNull() ?: 0) }
    var molarMass by remember { mutableStateOf(Prefs.get("units.molarMass")?.toDoubleOrNull() ?: 12.0) }
    var quantityMenu by remember { mutableStateOf(false) }
    var unitMenu by remember { mutableStateOf(false) }
    val units = quantity.units
    val fromIndex = from.coerceIn(0, units.size - 1)
    val base = value * units[fromIndex].second

    SectionCard {
        Box {
            PickerField("Quantity", quantity.title) { quantityMenu = true }
            DropdownMenu(quantityMenu, { quantityMenu = false }) {
                for (q in UnitQuantity.entries) DropdownMenuItem(text = { Text((if (q == quantity) "✓ " else "   ") + q.title) }, onClick = {
                    quantity = q; from = 0; quantityMenu = false
                    Prefs.put("units.quantity", q.name); Prefs.put("units.from", "0")
                })
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            NumberField("Value", value, "", Modifier.weight(1f)) { value = it; Prefs.put("units.value", "$it") }
            Box {
                TextButton(onClick = { unitMenu = true }) { Text(units[fromIndex].first + " ⌄") }
                DropdownMenu(unitMenu, { unitMenu = false }) {
                    units.forEachIndexed { i, (name, _) ->
                        DropdownMenuItem(text = { Text(name) }, onClick = { from = i; unitMenu = false; Prefs.put("units.from", "$i") })
                    }
                }
            }
        }
    }
    SectionCard("Equals") {
        for (i in units.indices) if (i != fromIndex) ValueRow(units[i].first, Fmt.sig(base / units[i].second, 6))
    }
    if (quantity == UnitQuantity.AREAL_DENSITY) {
        SectionCard(footer = "For a compound, use the molar mass per formula unit and count formula units, not atoms.") {
            NumberField("Molar mass", molarMass, "g/mol", range = 1e-3..1e4) { molarMass = it; Prefs.put("units.molarMass", "$it") }
            ValueRow("Mass thickness", Fmt.sig(UnitQuantity.massThickness(base, molarMass), 6), "µg/cm²")
        }
    }
    if (quantity == UnitQuantity.TEMPERATURE) {
        Text("kT = 86.173 keV × T₉. T₉ = 0.015 is the solar core; 0.05–0.1 hydrostatic He burning; 0.1–0.4 novae; 1–3 explosive burning.",
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(4.dp))
    }
}

// MARK: Formula sheet

data class Formula(val title: String, val formula: String, val note: String? = null)

object ReferenceFormulas {
    val groups: List<Pair<String, List<Formula>>> = listOf(
        "Reactions" to listOf(
            Formula("Q value", "Q = (m₁ + m₂ − m₃ − m₄) c² = Δ₁ + Δ₂ − Δ₃ − Δ₄", "Δ = mass excess; atomic masses cancel electrons"),
            Formula("Threshold", "E_th = −Q (m₁ + m₂ + m₃ + m₄) / (2 m₂)", "Relativistic; ≈ −Q (1 + m₁/m₂)"),
            Formula("Centre-of-mass energy", "E_cm = E_lab m₂ / (m₁ + m₂)", "Non-relativistic"),
            Formula("Compound excitation", "Eₓ = E_cm + S_p (or S_α …)"),
            Formula("Rutherford (c.m.)", "dσ/dΩ = (Z₁Z₂e² / 4E_cm)² / sin⁴(θ/2)", "1.296 (Z₁Z₂/E_MeV)² mb/sr / sin⁴(θ/2)"),
            Formula("γ Doppler shift", "E = E₀ √(1 − β²) / (1 − β cos θ)"),
            Formula("Recoil correction", "E_γ = Eₓ − Eₓ² / (2 M c²)"),
        ),
        "Nuclear astrophysics" to listOf(
            Formula("Sommerfeld parameter", "2πη = 31.29 Z₁Z₂ √(μ/E)", "μ in u, E in keV (c.m.)"),
            Formula("S factor", "σ(E) = S(E) e^(−2πη) / E"),
            Formula("Gamow peak", "E₀ = 0.1220 (Z₁²Z₂² μ T₉²)¹ᐟ³ MeV"),
            Formula("Gamow width", "Δ = 0.2368 (Z₁²Z₂² μ T₉⁵)¹ᐟ⁶ MeV"),
            Formula("Screening enhancement", "f = σ_s/σ_b ≈ exp(πη U_e / E)"),
            Formula("Resonance strength", "ωγ = (2J+1)/((2j₁+1)(2j₂+1)) Γ_a Γ_b / Γ"),
            Formula("Thick-target yield", "Y = (λ²/2) (ωγ) (m₁+m₂)/m₂ / ε_eff", "λ at E_R (c.m.), ε_eff per active nucleus (lab)"),
            Formula("Narrow resonance rate", "Nₐ⟨σv⟩ = 1.5399×10¹¹ (μT₉)⁻³ᐟ² ωγ e^(−11.605 E_R/T₉)", "ωγ, E_R in MeV; cm³ mol⁻¹ s⁻¹"),
            Formula("Wigner limit", "γ²_W = 3ħ²/(2μa²);  θ² = γ²/γ²_W", "Γ = 2P_ℓ γ²"),
        ),
        "Stopping and targets" to listOf(
            Formula("Energy loss", "ΔE = ∫ ε(E) n dx;  ε in eV cm²/atom"),
            Formula("Bragg's rule", "ε_compound = Σ νᵢ εᵢ"),
            Formula("Bohr straggling", "σ²_B = 4π Z₁² e⁴ Z₂ n Δx"),
            Formula("Effective stopping", "ε_eff = ε_X + Σ (N_Y/N_X) ε_Y", "Per active nucleus X"),
        ),
        "Decay and counting" to listOf(
            Formula("Activity", "A(t) = A₀ e^(−λt);  λ = ln 2 / T½"),
            Formula("Specific activity", "a = λ Nₐ / M"),
            Formula("Counting statistics", "t = (S + kB) / (S² u²)", "S, B rates; u target relative uncertainty; k = t_bg ratio"),
            Formula("Currie limit", "L_D = 2.71 + 4.65 √B (paired blank), 2.71 + 3.29 √B (known background)"),
            Formula("Point-source air kerma", "K̇ = Γ_δ A / d²"),
        ),
        "Detectors" to listOf(
            Formula("Ge resolution", "FWHM² = a² + 2.355² F w E + (cE)²"),
            Formula("Efficiency curve", "ln ε = Σ aᵢ (ln E/E₀)ⁱ"),
            Formula("Disk solid angle", "Ω = 2π (1 − d/√(d² + r²))"),
            Formula("Beam current", "pps = I / (q e);  1 pµA = 6.2415×10¹² s⁻¹"),
        ),
    )
}

@Composable
fun FormulasScreen() {
    var search by remember { mutableStateOf("") }
    var copied by remember { mutableStateOf<String?>(null) }
    val clipboard = LocalClipboardManager.current
    LaunchedEffect(copied) { if (copied != null) { delay(1500); copied = null } }

    SearchField(search, "Search formulas") { search = it }
    copied?.let {
        Text("Copied “$it”", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.padding(start = 4.dp, top = 6.dp))
    }
    val q = search.trim()
    var any = false
    for ((title, items) in ReferenceFormulas.groups) {
        val shown = items.filter { q.isEmpty() || it.title.contains(q, ignoreCase = true) || it.formula.contains(q, ignoreCase = true) ||
            title.contains(q, ignoreCase = true) }
        if (shown.isEmpty()) continue
        any = true
        SectionCard(title) {
            for (f in shown) {
                Column(Modifier.fillMaxWidth().clickable { clipboard.setText(AnnotatedString(f.formula)); copied = f.title }
                    .padding(vertical = 2.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(f.title, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(f.formula, style = MaterialTheme.typography.bodyLarge, fontFamily = FontFamily.Serif)
                    f.note?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
            }
        }
    }
    if (!any) Text("No formula matches “$search”.", Modifier.padding(8.dp))
    Text("Numerical prefactors follow C. Iliadis, Nuclear Physics of Stars (2nd ed., Wiley 2015) and C. E. Rolfs & W. S. Rodney, " +
        "Cauldrons in the Cosmos. Tap a formula to copy it.",
        style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(4.dp))
}
