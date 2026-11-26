import NucPhysKit
import SwiftUI

/// Choose a radioactive nuclide (ground state or isomer) from NUBASE2020 instead of typing its name:
/// the lab's calibration sources first, common lab nuclides next, then every radioactive state by search.
struct NuclidePickerSheet: View {
    let title: String
    let selected: String
    let onPick: (NuclearState) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    /// Long-lived or frequently used nuclides in a nuclear-physics lab (sources, activation, background, decay chains).
    static let common = ["3H", "7Be", "14C", "22Na", "26Al", "40K", "54Mn", "56Co", "57Co", "60Co", "65Zn", "68Ge", "88Y",
                         "109Cd", "113Sn", "133Ba", "134Cs", "137Cs", "139Ce", "152Eu", "166mHo", "207Bi", "210Pb",
                         "226Ra", "228Th", "232Th", "238U", "241Am", "244Cm", "252Cf"]

    private static let radioactive: [NuclearState] = Nubase.nubase2020.states.filter {
        guard let t = $0.halfLife else { return false }
        return t.isFinite && t > 0
    }

    private var catalog: [NuclearState] { CalibrationSources.all.map(\.state) }
    private var commonStates: [NuclearState] {
        Self.common.compactMap { Nubase.nubase2020.state(named: $0) }.filter { s in !catalog.contains { $0.id == s.id } }
    }

    private var matches: [NuclearState] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        // "co" or "cobalt" → every Co state; "60co", "co60", "60" → by mass number too.
        let digits = String(q.filter(\.isNumber)), letters = q.filter(\.isLetter)
        return Self.radioactive.filter { s in
            let symbol = (Elements.symbol(z: s.z) ?? "").lowercased(), name = (Elements.name(z: s.z) ?? "").lowercased()
            let letterOK = letters.isEmpty || symbol == letters || name.hasPrefix(letters) || (letters.hasSuffix("m") && symbol == String(letters.dropLast()) && s.state > 0)
            let digitOK = digits.isEmpty || String(s.a).hasPrefix(digits)
            return letterOK && digitOK
        }
        .sorted { ($0.z, $0.a, $0.state) < ($1.z, $1.a, $1.state) }
        .prefix(200).map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section("Calibration sources") { ForEach(catalog) { row($0) } }
                    Section("Common in the lab") { ForEach(commonStates) { row($0) } }
                    Section {
                        Text("Search by element (Co, cobalt), mass number (60) or both (60Co, 26mAl).")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if matches.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    Section("\(matches.count == 200 ? "First 200" : "\(matches.count)") radioactive states") { ForEach(matches) { row($0) } }
                }
            }
            .searchable(text: $query, prompt: "Element, mass number or 60Co")
            .navigationTitle(title)
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func row(_ s: NuclearState) -> some View {
        Button {
            onPick(s)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.label).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(s.decayModes.prefix(2).map(\.text).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(s.halfLifeText.isEmpty ? Fmt.halfLife(s.halfLife ?? .nan) : s.halfLifeText)
                    .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                if s.plainLabel == selected { Image(systemName: "checkmark").foregroundStyle(Color.accent) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A form row showing the chosen nuclide; tapping it opens the picker.
struct NuclidePickerRow: View {
    let title: String
    @Binding var nuclide: String
    var disabled = false
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: {
            LabeledContent(title) {
                HStack(spacing: 6) {
                    Text(Nubase.nubase2020.state(named: nuclide)?.label ?? nuclide).foregroundStyle(.primary)
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .tint(.primary)
        .disabled(disabled)
        .sheet(isPresented: $picking) {
            NuclidePickerSheet(title: title, selected: nuclide) { nuclide = $0.plainLabel }
        }
    }
}
