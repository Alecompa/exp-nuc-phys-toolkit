import NucPhysKit
import SwiftUI

// MARK: - Constants

struct PhysicalConstant: Identifiable {
    let name: String
    let symbol: String
    let value: String
    let unit: String
    var note: String? = nil
    var id: String { name }
}

struct ConstantsView: View {
    @State private var search = ""

    static let groups: [(String, [PhysicalConstant])] = [
        ("Fundamental", [
            .init(name: "Speed of light", symbol: "c", value: "299 792 458", unit: "m/s", note: "Exact"),
            .init(name: "Planck constant (reduced)", symbol: "ħ", value: "6.582 119 569 × 10⁻¹⁶", unit: "eV s"),
            .init(name: "ħc", symbol: "ħc", value: "197.326 980 4", unit: "MeV fm"),
            .init(name: "Elementary charge", symbol: "e", value: "1.602 176 634 × 10⁻¹⁹", unit: "C", note: "Exact"),
            .init(name: "e²/(4πε₀)", symbol: "e²", value: "1.439 964 548", unit: "MeV fm"),
            .init(name: "Fine-structure constant", symbol: "α", value: "1/137.035 999 084", unit: ""),
            .init(name: "Boltzmann constant", symbol: "k", value: "8.617 333 262 × 10⁻⁵", unit: "eV/K", note: "kT = 86.173 keV × T₉"),
            .init(name: "Avogadro constant", symbol: "Nₐ", value: "6.022 140 76 × 10²³", unit: "mol⁻¹", note: "Exact"),
        ]),
        ("Masses", [
            .init(name: "Atomic mass unit", symbol: "u", value: "931.494 102 42", unit: "MeV/c²"),
            .init(name: "Electron mass", symbol: "mₑ", value: "0.510 998 950 00", unit: "MeV/c²"),
            .init(name: "Proton mass", symbol: "mₚ", value: "938.272 088 16", unit: "MeV/c²"),
            .init(name: "Neutron mass", symbol: "mₙ", value: "939.565 420 52", unit: "MeV/c²"),
            .init(name: "Deuteron mass", symbol: "m_d", value: "1875.612 942 57", unit: "MeV/c²"),
            .init(name: "α-particle mass", symbol: "m_α", value: "3727.379 4066", unit: "MeV/c²"),
            .init(name: "Neutron–hydrogen mass difference", symbol: "Δ", value: "782.347", unit: "keV"),
        ]),
        ("Nuclear and atomic", [
            .init(name: "Bohr radius", symbol: "a₀", value: "0.529 177 210 90", unit: "Å"),
            .init(name: "Classical electron radius", symbol: "rₑ", value: "2.817 940 3262", unit: "fm"),
            .init(name: "Barn", symbol: "b", value: "10⁻²⁴", unit: "cm²", note: "= 100 fm²"),
            .init(name: "Nuclear radius parameter", symbol: "r₀", value: "1.2–1.4", unit: "fm", note: "R = r₀ A¹ᐟ³ (convention dependent)"),
            .init(name: "Nuclear magneton", symbol: "μ_N", value: "3.152 451 258 × 10⁻¹⁴", unit: "MeV/T"),
            .init(name: "Ge pair-creation energy", symbol: "w", value: "2.96", unit: "eV", note: "At 77 K"),
            .init(name: "Si pair-creation energy", symbol: "w", value: "3.62", unit: "eV", note: "At 300 K"),
        ]),
        ("Astrophysics", [
            .init(name: "Solar mass", symbol: "M☉", value: "1.988 47 × 10³⁰", unit: "kg"),
            .init(name: "Solar luminosity", symbol: "L☉", value: "3.828 × 10²⁶", unit: "W", note: "IAU nominal"),
            .init(name: "Year (Julian)", symbol: "yr", value: "3.155 76 × 10⁷", unit: "s"),
            .init(name: "Gamow energy prefactor", symbol: "E_G", value: "0.9791 Z₁²Z₂² μ", unit: "MeV", note: "μ in u; E_G = 2μc²(παZ₁Z₂)²"),
            .init(name: "Rate prefactor", symbol: "", value: "3.7318 × 10¹⁰ / T₉³ᐟ²", unit: "", note: "Nₐ⟨σv⟩ = prefactor μ⁻¹ᐟ² ∫ σE e^(−11.605E/T₉) dE, E in MeV, σ in b"),
        ]),
    ]

    var body: some View {
        List {
            ForEach(Self.groups, id: \.0) { title, items in
                let shown = items.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.symbol.localizedCaseInsensitiveContains(search) }
                if !shown.isEmpty {
                    Section(title) {
                        ForEach(shown) { c in
                            ValueRow(label: c.symbol.isEmpty ? c.name : "\(c.name) \(c.symbol)", value: c.value,
                                     unit: c.unit.isEmpty ? nil : c.unit, note: c.note)
                        }
                    }
                }
            }
            Section {
                Text("CODATA 2018 recommended values (physics.nist.gov/constants). Touch and hold a value to copy it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .groupedList()
        .searchable(text: $search, prompt: "Search constants")
        .navigationTitle("Constants")
        .inlineTitle()
    }
}

// MARK: - Unit converter

struct UnitConverterView: View {
    enum Quantity: String, CaseIterable, Identifiable {
        case energy = "Energy", temperature = "Temperature", crossSection = "Cross section", length = "Length",
             arealDensity = "Areal density", activity = "Activity", time = "Time", charge = "Charge"
        var id: String { rawValue }

        /// Unit names and their size in the base unit.
        var units: [(String, Double)] {
            switch self {
            case .energy: [("eV", 1), ("keV", 1e3), ("MeV", 1e6), ("GeV", 1e9), ("J", 1 / 1.602_176_634e-19), ("erg", 1e-7 / 1.602_176_634e-19), ("u c²", 931.494_102_42e6)]
            case .temperature: [("T₉", 1), ("K", 1e-9), ("kT (keV)", 1 / 86.173_332_62), ("kT (MeV)", 1000 / 86.173_332_62)]
            case .crossSection: [("b", 1), ("mb", 1e-3), ("µb", 1e-6), ("nb", 1e-9), ("pb", 1e-12), ("fb", 1e-15), ("fm²", 1e-2), ("cm²", 1e24)]
            case .length: [("fm", 1), ("Å", 1e5), ("nm", 1e6), ("µm", 1e9), ("mm", 1e12), ("cm", 1e13), ("m", 1e15)]
            case .arealDensity: [("at/cm²", 1), ("10¹⁵ at/cm²", 1e15), ("10¹⁸ at/cm²", 1e18)]
            case .activity: [("Bq", 1), ("kBq", 1e3), ("MBq", 1e6), ("GBq", 1e9), ("µCi", 3.7e4), ("mCi", 3.7e7), ("Ci", 3.7e10)]
            case .time: [("s", 1), ("min", 60), ("h", 3600), ("d", 86400), ("y", HalfLifeFormat.year), ("ms", 1e-3), ("µs", 1e-6), ("ns", 1e-9), ("ps", 1e-12), ("fs", 1e-15)]
            case .charge: [("C", 1), ("mC", 1e-3), ("µC", 1e-6), ("nC", 1e-9), ("e", 1.602_176_634e-19)]
            }
        }
    }

    @AppStorage("units.quantity") private var quantity = Quantity.energy
    @AppStorage("units.value") private var value = 1.0
    @AppStorage("units.from") private var from = 1
    @AppStorage("units.molarMass") private var molarMass = 12.0

    var body: some View {
        let units = quantity.units
        let fromIndex = min(from, units.count - 1)
        let base = value * units[fromIndex].1

        List {
            Section {
                Picker("Quantity", selection: Binding(get: { quantity }, set: { quantity = $0; from = 0 })) {
                    ForEach(Quantity.allCases) { Text($0.rawValue).tag($0) }
                }
                LabeledContent("Value") {
                    HStack(spacing: 6) {
                        ScientificTextField(title: "Value", value: $value, allowsNegative: true)
                        Picker("Unit", selection: $from) {
                            ForEach(units.indices, id: \.self) { Text(units[$0].0).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                    }
                }
            }
            Section {
                ForEach(units.indices.filter { $0 != fromIndex }, id: \.self) { i in
                    ValueRow(label: units[i].0, value: Fmt.significant(base / units[i].1, digits: 6))
                }
            } header: {
                Text("Equals")
            }
            if quantity == .arealDensity {
                Section {
                    NumberField(title: "Molar mass", value: $molarMass, unit: "g/mol", range: 1e-3...1e4)
                    ValueRow(label: "Mass thickness", value: Fmt.significant(base * molarMass / RadioactiveDecay.avogadro * 1e6, digits: 6), unit: "µg/cm²")
                } footer: {
                    Text("For a compound, use the molar mass per formula unit and count formula units, not atoms.")
                }
            }
            if quantity == .temperature {
                Section {
                    Text("kT = 86.173 keV × T₉. T₉ = 0.015 is the solar core; 0.05–0.1 hydrostatic He burning; 0.1–0.4 novae; 1–3 explosive burning.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .groupedList()
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .navigationTitle("Unit Converter")
        .inlineTitle()
    }
}


// MARK: - Formula sheet

struct FormulaSheetView: View {
    struct Formula: Identifiable {
        let title: String
        let formula: String
        var note: String? = nil
        var id: String { title }
    }

    static let groups: [(String, [Formula])] = [
        ("Reactions", [
            .init(title: "Q value", formula: "Q = (m₁ + m₂ − m₃ − m₄) c² = Δ₁ + Δ₂ − Δ₃ − Δ₄", note: "Δ = mass excess; atomic masses cancel electrons"),
            .init(title: "Threshold", formula: "E_th = −Q (m₁ + m₂ + m₃ + m₄) / (2 m₂)", note: "Relativistic; ≈ −Q (1 + m₁/m₂)"),
            .init(title: "Centre-of-mass energy", formula: "E_cm = E_lab m₂ / (m₁ + m₂)", note: "Non-relativistic"),
            .init(title: "Compound excitation", formula: "Eₓ = E_cm + S_p (or S_α …)"),
            .init(title: "Rutherford (c.m.)", formula: "dσ/dΩ = (Z₁Z₂e² / 4E_cm)² / sin⁴(θ/2)", note: "1.296 (Z₁Z₂/E_MeV)² mb/sr / sin⁴(θ/2)"),
            .init(title: "γ Doppler shift", formula: "E = E₀ √(1 − β²) / (1 − β cos θ)"),
            .init(title: "Recoil correction", formula: "E_γ = Eₓ − Eₓ² / (2 M c²)"),
        ]),
        ("Nuclear astrophysics", [
            .init(title: "Sommerfeld parameter", formula: "2πη = 31.29 Z₁Z₂ √(μ/E)", note: "μ in u, E in keV (c.m.)"),
            .init(title: "S factor", formula: "σ(E) = S(E) e^(−2πη) / E"),
            .init(title: "Gamow peak", formula: "E₀ = 0.1220 (Z₁²Z₂² μ T₉²)¹ᐟ³ MeV"),
            .init(title: "Gamow width", formula: "Δ = 0.2368 (Z₁²Z₂² μ T₉⁵)¹ᐟ⁶ MeV"),
            .init(title: "Screening enhancement", formula: "f = σ_s/σ_b ≈ exp(πη U_e / E)"),
            .init(title: "Resonance strength", formula: "ωγ = (2J+1)/((2j₁+1)(2j₂+1)) Γ_a Γ_b / Γ"),
            .init(title: "Thick-target yield", formula: "Y = (λ²/2) (ωγ) (m₁+m₂)/m₂ / ε_eff", note: "λ at E_R (c.m.), ε_eff per active nucleus (lab)"),
            .init(title: "Narrow resonance rate", formula: "Nₐ⟨σv⟩ = 1.5399×10¹¹ (μT₉)⁻³ᐟ² ωγ e^(−11.605 E_R/T₉)", note: "ωγ, E_R in MeV; cm³ mol⁻¹ s⁻¹"),
            .init(title: "Wigner limit", formula: "γ²_W = 3ħ²/(2μa²);  θ² = γ²/γ²_W", note: "Γ = 2P_ℓ γ²"),
        ]),
        ("Stopping and targets", [
            .init(title: "Energy loss", formula: "ΔE = ∫ ε(E) n dx;  ε in eV cm²/atom"),
            .init(title: "Bragg's rule", formula: "ε_compound = Σ νᵢ εᵢ"),
            .init(title: "Bohr straggling", formula: "σ²_B = 4π Z₁² e⁴ Z₂ n Δx"),
            .init(title: "Effective stopping", formula: "ε_eff = ε_X + Σ (N_Y/N_X) ε_Y", note: "Per active nucleus X"),
        ]),
        ("Decay and counting", [
            .init(title: "Activity", formula: "A(t) = A₀ e^(−λt);  λ = ln 2 / T½"),
            .init(title: "Specific activity", formula: "a = λ Nₐ / M"),
            .init(title: "Counting statistics", formula: "t = (S + kB) / (S² u²)", note: "S, B rates; u target relative uncertainty; k = t_bg ratio"),
            .init(title: "Currie limit", formula: "L_D = 2.71 + 4.65 √B (counts)"),
            .init(title: "Point-source air kerma", formula: "K̇ = Γ_δ A / d²"),
        ]),
        ("Detectors", [
            .init(title: "Ge resolution", formula: "FWHM² = a² + 2.355² F w E + (cE)²"),
            .init(title: "Efficiency curve", formula: "ln ε = Σ aᵢ (ln E/E₀)ⁱ"),
            .init(title: "Disk solid angle", formula: "Ω = 2π (1 − d/√(d² + r²))"),
            .init(title: "Beam current", formula: "pps = I / (q e);  1 pµA = 6.2415×10¹² s⁻¹"),
        ]),
    ]

    var body: some View {
        List {
            ForEach(Self.groups, id: \.0) { title, items in
                Section(title) {
                    ForEach(items) { f in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(f.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            Text(f.formula).font(.system(.body, design: .serif)).textSelection(.enabled)
                            if let note = f.note {
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .contextMenu {
                            Button("Copy Formula", systemImage: "doc.on.doc") { Pasteboard.copy(f.formula) }
                        }
                    }
                }
            }
            Section {
                Text("Numerical prefactors follow C. Iliadis, Nuclear Physics of Stars (2nd ed., Wiley 2015) and C. E. Rolfs & W. S. Rodney, Cauldrons in the Cosmos.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .groupedList()
        .navigationTitle("Formula Sheet")
        .inlineTitle()
    }
}
