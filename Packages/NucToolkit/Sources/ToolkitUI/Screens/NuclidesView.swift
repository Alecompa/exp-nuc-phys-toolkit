import NucPhysKit
import SwiftUI

struct NuclidesView: View {
    @Namespace private var zoom
    @State private var query = ""

    private var table: MassTable { .ame2020 }

    private var results: [Nuclide] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        if let exact = table.nuclide(named: q) { return [exact] }
        let lower = q.lowercased()
        if let z = Elements.z(forSymbol: q) ?? Elements.names.firstIndex(where: { $0.lowercased().hasPrefix(lower) }) {
            return table.isotopes(z: z)
        }
        if let a = Int(q) { return table.nuclides.filter { $0.a == a } }
        return []
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section("Light nuclei") {
                        ForEach(Self.featured, id: \.self) { name in
                            if let n = table.nuclide(named: name) { link(n) }
                        }
                    }
                } else {
                    ForEach(results) { link($0) }
                }
            }
            .groupedList()
            .overlay {
                if !query.isEmpty && results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Nuclides")
            .largeTitle()
            .alwaysVisibleSearch(text: $query, prompt: "13N, Carbon, Mg, 26…")
            .autocorrectionDisabled()
            .appDestinations(namespace: zoom)
        }
    }

    private func link(_ n: Nuclide) -> some View {
        NavigationLink(value: Route.nuclide(n)) {
            NuclideRow(nuclide: n)
        }
        .zoomSource(id: n.id, in: zoom)
    }

    static let featured = ["n", "p", "d", "t", "3He", "4He", "7Li", "7Be", "12C", "13C", "13N", "14N", "15N", "16O",
                           "17O", "18F", "20Ne", "22Ne", "25Mg", "26Al", "27Al"]
}

private struct NuclideRow: View {
    let nuclide: Nuclide

    var body: some View {
        HStack(spacing: 14) {
            NuclideTile(nuclide: nuclide, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(nuclide.elementName)-\(nuclide.a)")
                    .font(.body.weight(.medium))
                Text(["Z \(nuclide.z) · N \(nuclide.n)", nuclide.nubase.map { Fmt.halfLife($0.halfLife, digits: 4) }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.number(nuclide.massExcess, decimals: min(3, Fmt.decimals(forUncertainty: nuclide.massExcessUncertainty))))
                    .monospacedDigit()
                Text("Δ keV").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Periodic-table-style tile; the tint encodes the neutron excess but the text carries all information.
struct NuclideTile: View {
    let nuclide: Nuclide
    var size: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            Text(String(nuclide.a))
                .font(.system(size: size * 0.24, weight: .semibold, design: .rounded))
                .opacity(0.8)
            Text(nuclide.symbol)
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
        .accessibilityHidden(true)
    }

    private var tint: Color {
        let excess = nuclide.n - nuclide.z
        if nuclide.z == 0 { return .gray }
        if excess < 0 { return .pink }
        if excess == 0 { return .indigo }
        return excess <= 2 ? .blue : .teal
    }
}

struct NuclideDetailView: View {
    let nuclide: Nuclide
    @Environment(Workbench.self) private var workbench
    @State private var confirmation = 0

    private var table: MassTable { .ame2020 }

    var body: some View {
        let unit = workbench.energyUnit
        List {
            Section {
                HStack(spacing: 18) {
                    NuclideTile(nuclide: nuclide, size: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(nuclide.elementName)-\(nuclide.a)")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text("Z = \(nuclide.z)   N = \(nuclide.n)   A = \(nuclide.a)")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        if nuclide.isEstimated {
                            StatusBadge(text: "From systematics", symbol: "number", tint: .yellow)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                ValueRow(label: "Mass excess Δ",
                         value: Fmt.energy(nuclide.massExcess, unit: unit, uncertainty: nuclide.massExcessUncertainty),
                         uncertainty: Fmt.uncertainty(nuclide.massExcessUncertainty, unit: unit), unit: unit.label)
                ValueRow(label: "Atomic mass",
                         value: Fmt.number(nuclide.atomicMassMicroU, decimals: Fmt.decimals(forUncertainty: nuclide.massExcessUncertainty / PhysicalConstants.atomicMassUnit * 1e6)),
                         unit: "µu")
                ValueRow(label: "Binding energy / A",
                         value: Fmt.number(nuclide.bindingEnergyPerNucleon, decimals: 3), unit: "keV")
            } header: {
                Text("AME2020")
            }

            NubaseSection(nuclide: nuclide)

            Section {
                ForEach(Separation.allCases) { s in
                    if let value = s.energy(of: nuclide, in: table) {
                        ValueRow(label: s.title, value: Fmt.energy(value, unit: unit, decimals: unit == .keV ? 2 : 5), unit: unit.label)
                    }
                }
            } header: {
                Text("Separation energies")
            } footer: {
                Text("Equal to the Q value of capture on the daughter, e.g. Sₚ(¹³N) = Q of ¹²C(p,γ)¹³N.")
            }

            if nuclide.a > 1 {
                LevelSchemeSection(nuclide: nuclide)
            }

            if nuclide.z > 0 {
                ExforTargetSection(nuclide: nuclide)
            }

            if nuclide.a > 1 {
                Section {
                    Button {
                        workbench.reactionText = "\(nuclide.plainLabel)(p,g)"
                        confirmation += 1
                    } label: {
                        Label("Use as target in (p,γ)", systemImage: "scope")
                    }
                    Button {
                        workbench.reactionText = "\(nuclide.plainLabel)(a,g)"
                        confirmation += 1
                    } label: {
                        Label("Use as target in (α,γ)", systemImage: "scope")
                    }
                } footer: {
                    if let r = workbench.reaction, r.target == nuclide {
                        Label("Setup is now \(r.label)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .groupedList()
        .navigationTitle(nuclide.label)
        .inlineTitle()
        .sensoryFeedback(.success, trigger: confirmation)
        .animation(.smooth, value: workbench.reactionText)
    }
}

/// Nucleon and cluster separation energies computed from the mass table.
enum Separation: String, CaseIterable, Identifiable {
    case neutron, proton, alpha, twoNeutron, twoProton

    var id: String { rawValue }

    private var subscriptText: String {
        switch self {
        case .neutron: "n"
        case .proton: "p"
        case .alpha: "α"
        case .twoNeutron: "2n"
        case .twoProton: "2p"
        }
    }

    /// "S" with a true typographic subscript (Unicode has no subscript α).
    var title: Text {
        Text("S\(Text(subscriptText).font(.footnote).baselineOffset(-4))")
    }

    private var removed: (z: Int, a: Int, excess: Double) {
        switch self {
        case .neutron: (0, 1, 8071.31806)
        case .proton: (1, 1, 7288.971064)
        case .alpha: (2, 4, 2424.91587)
        case .twoNeutron: (0, 2, 2 * 8071.31806)
        case .twoProton: (2, 2, 2 * 7288.971064)
        }
    }

    func energy(of n: Nuclide, in table: MassTable) -> Double? {
        let r = removed
        guard n.a > r.a, let daughter = table.nuclide(z: n.z - r.z, a: n.a - r.a) else { return nil }
        return daughter.massExcess + r.excess - n.massExcess
    }
}
