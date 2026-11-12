import NucPhysKit
import SwiftUI

/// "¹H in Carbon" header used by the stopping tools; tapping edits the target material.
struct StoppingHeader: View {
    let ion: StoppingIon
    let ionLabel: String
    let target: StoppingTarget
    let isReactionTarget: Bool
    let editTarget: () -> Void

    var body: some View {
        Button(action: editTarget) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("\(ionLabel) \(Text("in").foregroundStyle(.secondary)) \(target.name)")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.interpolate)
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                Text(TargetSummary.line(target, reaction: isReactionTarget))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit the target material")
    }
}

enum TargetSummary {
    static func line(_ t: StoppingTarget, reaction: Bool) -> String {
        var parts = [composition(t), "\(Fmt.significant(t.density)) g/cm³", t.isGas ? "gas" : "solid"]
        if t.compoundCorrection != 1 { parts.append("Bragg × \(Fmt.significant(t.compoundCorrection, digits: 3))") }
        if reaction { parts.append("reaction target") }
        return parts.joined(separator: " · ")
    }

    /// A formula ("Ta₂N₃") when it adds to the name and the stoichiometries are short, atom percentages otherwise.
    static func composition(_ t: StoppingTarget) -> String {
        let formula = t.formulaLabel()
        let simple = formula.count <= 24 && !formula.contains(".")
        return simple && formula != t.name ? formula : t.compositionLabel
    }
}

/// Plain numeric entry with a unit suffix.
struct NumberField: View {
    let title: String
    @Binding var value: Double
    var unit: String? = nil
    var range: ClosedRange<Double> = 0...Double.greatestFiniteMagnitude

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) }),
                          format: .number.precision(.significantDigits(1...7)).grouping(.never))
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .decimalKeyboard()
                if let unit { Text(unit).foregroundStyle(.secondary) }
            }
        }
    }
}

/// Thickness entry stored in Å, shown in a selectable unit (which may depend on the material).
struct ThicknessField: View {
    var title = "Thickness"
    @Binding var angstrom: Double
    let target: StoppingTarget
    @Binding var unit: ThicknessUnit

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: Binding(
                    get: { unit.fromAngstrom(angstrom, target: target) },
                    set: { angstrom = max(1e-3, unit.toAngstrom($0, target: target)) }
                ), format: .number.precision(.significantDigits(1...6)).grouping(.never))
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .decimalKeyboard()
                Menu {
                    Picker("Unit", selection: $unit) {
                        ForEach(ThicknessUnit.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(unit.rawValue)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                }
                .accessibilityLabel("Thickness unit, \(unit.rawValue)")
            }
        }
    }
}

/// Edits the reaction's target material (used by Stopping Power and as the target layer of Energy Loss).
struct TargetSheet: View {
    @Environment(Workbench.self) private var workbench
    let initial: StoppingTarget

    var body: some View {
        TargetEditor(title: "Target", initial: initial, thickness: nil,
                     reactionTarget: workbench.reactionTargetMaterial) { target, _ in
            workbench.customTarget = target == workbench.reactionTargetMaterial ? nil : target
        }
    }
}

/// Material editor: library choice, chemical formula with arbitrary stoichiometry, per-element
/// stoichiometry, density (or gas pressure), phase and Bragg correction; optionally a layer thickness.
struct TargetEditor: View {
    @Environment(Workbench.self) private var workbench
    @Environment(\.dismiss) private var dismiss

    let title: String
    /// Offered as "Use reaction target" when different from the draft.
    let reactionTarget: StoppingTarget?
    let showsThickness: Bool
    var onDelete: (() -> Void)? = nil
    let onSave: (StoppingTarget, Double) -> Void

    @State private var draft: StoppingTarget
    @State private var thickness: Double
    @State private var formulaText: String
    @State private var formulaError: String?
    @State private var temperature: Double = 293.15
    @State private var atomsPerMolecule: Double
    /// The composition changed but the density is still the previous material's.
    @State private var densityNeedsReview = false
    @FocusState private var formulaFocused: Bool

    init(title: String, initial: StoppingTarget, thickness: Double?, reactionTarget: StoppingTarget? = nil,
         onDelete: (() -> Void)? = nil, onSave: @escaping (StoppingTarget, Double) -> Void) {
        self.title = title
        self.reactionTarget = reactionTarget
        self.showsThickness = thickness != nil
        self.onDelete = onDelete
        self.onSave = onSave
        _draft = State(initialValue: initial)
        _thickness = State(initialValue: thickness ?? 0)
        _formulaText = State(initialValue: initial.formulaText())
        _atomsPerMolecule = State(initialValue: GasTarget.defaultAtomsPerMolecule(initial))
    }

    var body: some View {
        @Bindable var workbench = workbench
        NavigationStack {
            List {
                materialSection
                compositionSection
                propertiesSection
                if draft.isGas { gasSection }
                if showsThickness {
                    Section {
                        ThicknessField(angstrom: $thickness, target: draft, unit: $workbench.thicknessUnit)
                    } header: {
                        Text("Layer")
                    } footer: {
                        Text(Self.equivalents(draft, thickness, current: workbench.thicknessUnit)).monospacedDigit()
                    }
                }
                Section {
                    LabeledContent("Atomic density") {
                        Text("\(Fmt.significant(draft.atomDensity)) cm⁻³").monospacedDigit()
                    }
                    LabeledContent("Mean Z₂ / M₂") {
                        Text("\(Fmt.significant(draft.meanZ, digits: 3)) / \(Fmt.significant(draft.meanMass, digits: 5)) u")
                            .monospacedDigit()
                    }
                }
                if let onDelete {
                    Section {
                        Button("Remove Layer", systemImage: "trash", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .groupedList()
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .navigationTitle(title)
            .inlineTitle()
            .onChange(of: draft) { old, new in
                // Keep the thickness fixed in the unit the user works in (e.g. µg/cm²) when the material changes.
                let u = workbench.thicknessUnit
                if showsThickness, old.density > 0, new.density > 0, old != new {
                    thickness = u.toAngstrom(u.fromAngstrom(thickness, target: old), target: new)
                }
                if old.density != new.density { densityNeedsReview = false }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", role: .confirm) {
                        onSave(draft, thickness)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        draft.density > 0 && !draft.components.isEmpty && formulaError == nil && (!showsThickness || thickness > 0)
    }

    // MARK: Sections

    private var materialSection: some View {
        Section {
            NavigationLink {
                MaterialLibrary { picked in apply(picked) }
            } label: {
                Label("Choose from Library", systemImage: "books.vertical")
            }
            if let r = reactionTarget, r != draft {
                Button {
                    withAnimation(.smooth) { apply(r) }
                } label: {
                    Label("Use Reaction Target (\(r.name))", systemImage: "arrow.uturn.backward")
                }
            }
            LabeledContent("Name") {
                TextField("Name", text: $draft.name)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Material")
        } footer: {
            Text("Elements Z = 1–92 and the 356 materials of SRIM's compound dictionary, or any composition below.")
        }
    }

    private var compositionSection: some View {
        Section {
            HStack {
                Text("Formula")
                TextField("e.g. Ta2N3, TiD2, Ca(OH)2", text: $formulaText)
                    .multilineTextAlignment(.trailing)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    .notationInput()
                    .focused($formulaFocused)
                    .onChange(of: formulaText) { _, new in parseFormula(new) }
                    .onSubmit { parseFormula(formulaText) }
            }
            ForEach(Array(draft.components.enumerated()), id: \.offset) { index, c in
                ComponentRow(component: c, fraction: draft.fractions[index], stoichiometry: Binding(
                    get: { c.stoichiometry },
                    set: { updateComponent(index, stoichiometry: $0) }
                ))
            }
            .onDelete { offsets in
                guard draft.components.count - offsets.count >= 1 else { return }
                var comps = draft.components
                comps.remove(atOffsets: offsets)
                setComponents(comps)
            }
            NavigationLink {
                MaterialLibrary(elementsOnly: true) { picked in
                    guard let z = picked.components.first?.z else { return }
                    var comps = draft.components
                    if let k = comps.firstIndex(where: { $0.z == z && $0.isotopeMassNumber == picked.components[0].isotopeMassNumber && abs($0.mass - picked.components[0].mass) < 0.5 }) {
                        comps[k] = .init(z: z, stoichiometry: comps[k].stoichiometry + 1, mass: comps[k].mass, massNumber: comps[k].massNumber)
                    } else {
                        comps.append(.init(z: z, stoichiometry: 1, mass: picked.components[0].mass))
                    }
                    setComponents(comps)
                }
            } label: {
                Label("Add Element", systemImage: "plus")
            }
        } header: {
            Text("Composition")
        } footer: {
            if let formulaError {
                Text(formulaError).foregroundStyle(.red)
            } else if let match = dictionaryMatch, abs(match.density - draft.density) > 1e-6 {
                Button {
                    withAnimation(.smooth) { draft.density = match.density; draft.isGas = match.gas; densityNeedsReview = false }
                } label: {
                    Text("SRIM dictionary: \(match.displayName), \(Fmt.significant(match.density)) g/cm³. \(Text("Use this density").foregroundStyle(Color.accent))")
                }
                .buttonStyle(.plain)
            } else {
                Text("Any stoichiometry, also fractional (Ti0.5Al0.5N). D and T for deuterium and tritium, [17O] for an isotope. Stopping follows Bragg's rule; set the density below.")
            }
        }
    }

    private var propertiesSection: some View {
        Section {
            NumberField(title: "Density", value: $draft.density, unit: "g/cm³", range: 1e-12...30)
            if densityNeedsReview {
                Label("Still the density of the previous material. Set the density of \(draft.name).",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Toggle("Gas target", isOn: $draft.isGas.animation(.smooth))
            NumberField(title: "Bragg correction", value: $draft.compoundCorrection, unit: "×", range: 0.5...1.5)
        } header: {
            Text("Properties")
        } footer: {
            Text("The gas phase changes SRIM's phase correction and the mean ionisation potential. The Bragg correction multiplies the compound stopping at low velocity and fades out at high velocity; 1 means none.")
        }
    }

    private var gasSection: some View {
        Section {
            NumberField(title: "Pressure", value: pressure, unit: "mbar", range: 1e-9...1e6)
            NumberField(title: "Temperature", value: Binding(
                get: { temperature },
                set: { t in let p = pressure.wrappedValue; temperature = t; pressure.wrappedValue = p }
            ), unit: "K", range: 1...5000)
            NumberField(title: "Atoms per molecule", value: Binding(
                get: { atomsPerMolecule },
                set: { a in let p = pressure.wrappedValue; atomsPerMolecule = a; pressure.wrappedValue = p }
            ), range: 1...100)
            LabeledContent("Areal density per cm") {
                Text("\(Fmt.significant(draft.atomDensity)) at/cm²").monospacedDigit()
            }
        } header: {
            Text("Gas")
        } footer: {
            Text("Ideal gas: n = p/(kT) molecules per cm³. Editing the pressure, temperature or molecule size sets the density; a gas cell's length is the layer thickness.")
        }
    }

    /// Pressure (mbar) equivalent to the draft density at `temperature`; setting it sets the density.
    private var pressure: Binding<Double> {
        Binding(
            get: {
                let n = draft.atomDensity / atomsPerMolecule
                return n * 1e6 * 1.380_649e-23 * temperature / 100
            },
            set: { p in
                draft.density = GasTarget.density(of: draft, pressure: p, temperature: temperature,
                                                  atomsPerMolecule: atomsPerMolecule)
            }
        )
    }

    // MARK: Editing

    private var dictionaryMatch: SRIMCompound? {
        let fr = draft.fractions
        guard draft.components.count > 1 else { return nil }
        return SRIMData.shared.compounds.first { c in
            c.elements.count == draft.components.count &&
            zip(draft.components, fr).allSatisfy { comp, f in
                c.elements.contains { Int($0[0]) == comp.z && abs($0[1] - f) < 2e-3 }
            }
        }
    }

    private func apply(_ t: StoppingTarget) {
        draft = t
        formulaText = t.formulaText()
        formulaError = nil
        densityNeedsReview = false
        atomsPerMolecule = GasTarget.defaultAtomsPerMolecule(t)
    }

    private func parseFormula(_ text: String) {
        guard formulaFocused || text != draft.formulaText() else { return }
        do {
            let f = try ChemicalFormula(text)
            let new = StoppingTarget.formula(f, density: draft.density, gas: draft.isGas)
            formulaError = nil
            guard new.components != draft.components else { return }
            withAnimation(.smooth) {
                draft.components = new.components
                draft.name = new.name
                atomsPerMolecule = GasTarget.defaultAtomsPerMolecule(draft)
                densityNeedsReview = true
            }
        } catch {
            formulaError = (error as? LocalizedError)?.errorDescription ?? "Invalid formula."
        }
    }

    private func setComponents(_ comps: [StoppingTarget.Component]) {
        withAnimation(.smooth) {
            draft.components = comps
            draft.name = draft.formulaLabel()
            formulaText = draft.formulaText()
            formulaError = nil
            densityNeedsReview = true
        }
    }

    private func updateComponent(_ index: Int, stoichiometry: Double) {
        var comps = draft.components
        guard comps.indices.contains(index), stoichiometry > 0 else { return }
        comps[index] = .init(z: comps[index].z, stoichiometry: stoichiometry, mass: comps[index].mass, massNumber: comps[index].massNumber)
        setComponents(comps)
    }

    static func equivalents(_ target: StoppingTarget, _ angstrom: Double, current: ThicknessUnit) -> String {
        let shown: [ThicknessUnit] = [.nanometre, .microgramCm2, .atoms1e15].filter { $0 != current }
        let parts = shown.map { u in
            let v = Fmt.significant(u.fromAngstrom(angstrom, target: target))
            return u == .atoms1e15 ? "\(v)×\(u.rawValue)" : "\(v) \(u.rawValue)"
        }
        return "= " + parts.joined(separator: " = ")
    }
}

/// One element of a composition: symbol tile, stoichiometry field, atom percentage.
private struct ComponentRow: View {
    let component: StoppingTarget.Component
    let fraction: Double
    @Binding var stoichiometry: Double

    var body: some View {
        let natural = SRIMData.shared.element(component.z).naturalMass
        let isotope = abs(component.mass - natural) > 0.5
        HStack(spacing: 12) {
            Text(isotope ? StoppingTarget(name: "", components: [component], density: 1).formulaLabel() : (Elements.symbol(z: component.z) ?? "?"))
                .font(.system(.body, design: .rounded, weight: .bold))
                .frame(minWidth: 34, minHeight: 34)
                .padding(.horizontal, isotope ? 4 : 0)
                .background(Color.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .foregroundStyle(Color.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(Elements.name(z: component.z) ?? "")
                Text("\(Fmt.significant(fraction * 100, digits: 3)) at.% · \(Fmt.significant(component.mass, digits: 5)) u")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            TextField("Stoichiometry", value: $stoichiometry,
                      format: .number.precision(.significantDigits(1...6)).grouping(.never))
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .decimalKeyboard()
                .frame(maxWidth: 90)
                .accessibilityLabel("\(Elements.name(z: component.z) ?? "") stoichiometry")
        }
    }
}

/// Searchable list of elements and SRIM compounds.
struct MaterialLibrary: View {
    enum Kind: String, CaseIterable, Identifiable {
        case elements = "Elements", compounds = "Compounds"
        var id: String { rawValue }
    }

    var elementsOnly = false
    let pick: (StoppingTarget) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind = .elements
    @State private var query = ""

    private var compounds: [String: [SRIMCompound]] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = SRIMData.shared.compounds.filter {
            q.isEmpty || $0.displayName.lowercased().contains(q) || $0.title.lowercased().contains(q)
        }
        return Dictionary(grouping: all, by: \.category)
    }

    private static let categoryOrder: [String] = {
        var seen = Set<String>()
        return SRIMData.shared.compounds.map(\.category).filter { seen.insert($0).inserted }
    }()

    private var elements: [SRIMElement] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return SRIMData.shared.elements.filter {
            q.isEmpty || $0.symbol.lowercased() == q || (Elements.name(z: $0.z) ?? "").lowercased().contains(q) || "\($0.z)" == q
        }
    }

    var body: some View {
        List {
            if elementsOnly || kind == .elements {
                Section {
                    ForEach(elements, id: \.z) { e in
                        Button {
                            choose(.element(e.z))
                        } label: {
                            HStack(spacing: 12) {
                                Text(e.symbol)
                                    .font(.system(.body, design: .rounded, weight: .bold))
                                    .frame(width: 34, height: 34)
                                    .background(Color.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .foregroundStyle(Color.accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(Elements.name(z: e.z) ?? e.symbol).foregroundStyle(.primary)
                                    Text("Z = \(e.z) · \(Fmt.significant(SRIMStopping.isNaturalGas(e.z) ? e.gasDensity : e.density)) g/cm³")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                        .tint(.primary)
                    }
                }
            } else {
                // SRIM's own order: nuclear-physics and common target materials first.
                ForEach(Self.categoryOrder.filter { compounds[$0] != nil }, id: \.self) { cat in
                    Section(cat) {
                        ForEach(compounds[cat] ?? []) { c in
                            Button {
                                choose(.compound(c))
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.displayName).foregroundStyle(.primary)
                                    Text("\(c.compositionSummary) · \(Fmt.significant(c.density)) g/cm³\(c.gas ? " · gas" : "")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }
            }
        }
        .groupedList()
        .safeAreaBar(edge: .top) {
            if !elementsOnly {
                Picker("Library", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .alwaysVisibleSearch(text: $query, prompt: elementsOnly || kind == .elements ? "Element, symbol or Z" : "Mylar, Kapton, water…")
        .navigationTitle(elementsOnly ? "Add Element" : "Library")
        .inlineTitle()
        .sensoryFeedback(.selection, trigger: kind)
    }

    private func choose(_ t: StoppingTarget) {
        pick(t)
        dismiss()
    }
}
