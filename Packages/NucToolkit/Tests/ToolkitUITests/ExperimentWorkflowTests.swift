import Foundation
import SwiftData
import Testing
import NucPhysKit
@testable import ToolkitUI

@Suite("Experiment workflow regressions") @MainActor
struct ExperimentWorkflowTests {
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "gamow.tests.\(UUID().uuidString)")!
    }

    @Test func snapshotRoundTripRestoresIndependentSetup() throws {
        let workbench = Workbench(defaults: isolatedDefaults())
        workbench.reactionText = "17O(p,g)18F"
        workbench.customTarget = .formula(try ChemicalFormula("Ta2[17O]5"), density: 8.2)
        workbench.beamEnergy = 500; workbench.layerAngle = 60
        workbench.spectrumSetup.foils = [.init(material: .element(29), thickness: 1000)]
        let snapshot = ExperimentSetup(workbench)
        let decoded = try JSONDecoder().decode(ExperimentSetup.self, from: JSONEncoder().encode(snapshot))
        workbench.reactionText = "12C(p,g)"; workbench.spectrumSetup.foils = []
        try decoded.restore(to: workbench)
        #expect(ExperimentSetup(workbench) == snapshot)
        var unsupported = decoded; unsupported.version = 999
        #expect(throws: ExperimentError.self) { try unsupported.restore(to: workbench) }
        #expect(ExperimentSetup(workbench) == snapshot)
    }

    @Test func savedZeroAndIsotopeFractions() throws {
        let defaults = isolatedDefaults()
        let workbench = Workbench(defaults: defaults)
        workbench.beamCurrent = 0; workbench.beamEnergy = 0
        let reloaded = Workbench(defaults: defaults)
        #expect(reloaded.beamCurrent == 0 && reloaded.beamEnergy == 0)
        workbench.reactionText = "16O(p,g)"
        workbench.customTarget = .formula(try ChemicalFormula("Ta2[17O]5"), density: 8.2)
        #expect(workbench.activeAtomFraction == nil && workbench.effectiveStopping(at: 500) == nil)
        workbench.reactionText = "17O(p,g)"
        #expect(abs((workbench.activeAtomFraction ?? 0) - 5.0 / 7) < 1e-12)
    }

    @Test func storedRunAndNotebookCoexist() throws {
        let schema = Schema([NotebookEntry.self, ExperimentRecord.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let setup = ExperimentSetup(Workbench(defaults: isolatedDefaults()))
        let record = try ExperimentRecord(title: "Run 42", note: "Target A\nStable beam", charge: 120, seconds: 60, setup: setup)
        context.insert(record)
        context.insert(NotebookEntry(tool: .qValue, title: "Calculation", subtitle: "", items: []))
        try context.save()
        let runs = try context.fetch(FetchDescriptor<ExperimentRecord>())
        #expect(runs.count == 1 && runs[0].setup == setup && runs[0].chargeMicroCoulomb == 120)
        #expect(try context.fetchCount(FetchDescriptor<NotebookEntry>()) == 1)
        #expect(NotebookEntry.csvField("two\nlines") == "\"two\nlines\"")
    }
}
