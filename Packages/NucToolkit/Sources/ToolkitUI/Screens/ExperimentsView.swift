import NucPhysKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@Model final class ExperimentRecord {
    var title: String = ""
    var date: Date = Date()
    var note: String = ""
    var chargeMicroCoulomb: Double = 0
    var elapsedSeconds: Double = 0
    var setupData: Data = Data()

    init(title: String, note: String, charge: Double, seconds: Double, setup: ExperimentSetup) throws {
        self.title = title; self.note = note; chargeMicroCoulomb = charge; elapsedSeconds = seconds
        setupData = try JSONEncoder().encode(setup)
    }
    var setup: ExperimentSetup? { try? JSONDecoder().decode(ExperimentSetup.self, from: setupData) }
}

private struct ExperimentExport: Codable, Transferable {
    var title: String
    var date: Date
    var note: String
    var chargeMicroCoulomb: Double
    var elapsedSeconds: Double
    var setup: ExperimentSetup
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { value in
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(value)
        }.suggestedFileName("experiment.json")
    }
}

struct ExperimentsView: View {
    @Environment(Workbench.self) private var workbench
    @Environment(\.modelContext) private var context
    @Query(sort: \ExperimentRecord.date, order: .reverse) private var records: [ExperimentRecord]
    @State private var adding = false
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Save current setup / log a run", systemImage: "plus.circle.fill") { adding = true }
                    Text("Saves the current setup with run notes.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(records.filter { query.isEmpty || ($0.title + $0.note + ($0.setup?.reactionText ?? "")).localizedCaseInsensitiveContains(query) }) { record in
                    NavigationLink {
                        ExperimentDetail(record: record)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.title).font(.headline)
                            Text(record.setup?.reactionText ?? "Unreadable setup").font(.subheadline)
                            Text(record.date, format: .dateTime.day().month().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if records.isEmpty {
                    ContentUnavailableView("No saved experiments", systemImage: "flask", description: Text("Save the current setup to keep it for a run."))
                }
            }
            .navigationTitle("Experiments")
            .searchable(text: $query, prompt: "Run, reaction or notes")
            .sheet(isPresented: $adding) { NewExperimentSheet() }
        }
    }
}

private struct NewExperimentSheet: View {
    var record: ExperimentRecord? = nil
    @Environment(Workbench.self) private var workbench
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var note = ""
    @State private var charge = 0.0
    @State private var seconds = 0.0
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Run / setup") {
                    TextField("Name or run number", text: $title)
                    Text(record?.setup?.reactionText ?? workbench.reactionText).font(.headline)
                    TextField("Target ID, detector position, observations…", text: $note, axis: .vertical)
                        .lineLimit(4...10)
                }
                Section {
                    NumberField(title: "Integrated charge", value: $charge, unit: "µC", range: 0...1e15)
                    NumberField(title: "Elapsed time", value: $seconds, unit: "s", range: 0...1e12)
                } header: { Text("Measured run totals (optional)") } footer: {
                    Text("Measured totals; leave zero if not measured.")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(record == nil ? "Save experiment" : "Edit run notes")
            .onAppear {
                if let record {
                    title = record.title; note = record.note
                    charge = record.chargeMicroCoulomb; seconds = record.elapsedSeconds
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (record == nil && workbench.reaction == nil))
                }
            }
        }
    }
    private func save() {
        if let record {
            let old = (record.title, record.note, record.chargeMicroCoulomb, record.elapsedSeconds)
            record.title = title; record.note = note; record.chargeMicroCoulomb = charge; record.elapsedSeconds = seconds
            do { try context.save(); dismiss() }
            catch {
                (record.title, record.note, record.chargeMicroCoulomb, record.elapsedSeconds) = old
                self.error = error.localizedDescription
            }
            return
        }
        var inserted: ExperimentRecord?
        do {
            let record = try ExperimentRecord(title: title, note: note, charge: charge, seconds: seconds, setup: ExperimentSetup(workbench))
            context.insert(record); inserted = record
            try context.save(); dismiss()
        } catch {
            if let inserted { context.delete(inserted) }
            self.error = error.localizedDescription
        }
    }
}

private struct ExperimentDetail: View {
    @Environment(Workbench.self) private var workbench
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let record: ExperimentRecord
    @State private var restoring = false
    @State private var deleting = false
    @State private var error: String?
    @State private var restored = false
    @State private var editing = false
    var body: some View {
        List {
            Section("Run record") {
                Text(record.title).font(.headline)
                Text(record.date, format: .dateTime)
                if !record.note.isEmpty { Text(record.note) }
                Button("Edit run notes & measured totals", systemImage: "square.and.pencil") { editing = true }
                ValueRow(label: "Integrated charge", value: Fmt.significant(record.chargeMicroCoulomb), unit: "µC")
                ValueRow(label: "Elapsed time", value: Fmt.significant(record.elapsedSeconds), unit: "s")
                if record.elapsedSeconds > 0, record.chargeMicroCoulomb > 0 {
                    ValueRow(label: "Mean electrical current", value: Fmt.significant(record.chargeMicroCoulomb / record.elapsedSeconds), unit: "µA")
                }
            }
            if let setup = record.setup {
                Section("Saved setup") {
                    Text(setup.reactionText).font(.headline)
                    ValueRow(label: "Beam energy", value: Fmt.keV(setup.beamEnergy), unit: "keV")
                    Text("Target: \(setup.customTarget?.name ?? "reaction element")")
                    Text("\(setup.layersBefore.count) entrance layers · \(setup.layersAfter.count) backing layers")
                    Text("\(setup.spectrumSetup.lines.count) gamma lines · \(setup.spectrumSetup.foils.count) detector foils")
                    if record.chargeMicroCoulomb > 0 {
                        ValueRow(label: "Incident ions", value: Fmt.significant(Beam.particles(charge: record.chargeMicroCoulomb * 1e-6, chargeState: setup.chargeState)))
                    }
                    Button(restored ? "Restored — open Tools to calculate" : "Restore this setup", systemImage: "arrow.uturn.backward") { restoring = true }
                    ShareLink(item: ExperimentExport(title: record.title, date: record.date, note: record.note,
                        chargeMicroCoulomb: record.chargeMicroCoulomb, elapsedSeconds: record.elapsedSeconds, setup: setup),
                              preview: SharePreview(record.title)) { Label("Export run & setup JSON", systemImage: "square.and.arrow.up") }
                }
            } else {
                Text("The saved setup could not be read; the notes are kept.").foregroundStyle(.orange)
            }
            if let error { Text(error).foregroundStyle(.red) }
            Button("Delete record", role: .destructive) { deleting = true }
        }
        .navigationTitle(record.title)
        .sheet(isPresented: $editing) { NewExperimentSheet(record: record) }
        .confirmationDialog("Replace the current shared setup? Save it first if you need it for another run.", isPresented: $restoring, titleVisibility: .visible) {
            Button("Restore setup") {
                do { try record.setup?.restore(to: workbench); restored = true }
                catch { self.error = error.localizedDescription }
            }
        }
        .confirmationDialog("Delete this saved run and setup?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(record)
                do { try context.save(); dismiss() }
                catch { context.rollback(); self.error = error.localizedDescription }
            }
        }
    }
}
