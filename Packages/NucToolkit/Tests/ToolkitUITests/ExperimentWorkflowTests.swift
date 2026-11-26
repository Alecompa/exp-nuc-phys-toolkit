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

    @Test func freshInstallUsesReactionDefaults() {
        let workbench = Workbench(defaults: isolatedDefaults())        // nothing saved
        #expect(workbench.sFactorIsPlaceholder)
        #expect(workbench.sFactorModel.s0 == 1)
        #expect(abs(workbench.isotopicAbundance - 98.94) < 1e-9)         // natural ¹²C (nubase2020.csv)
    }

    /// Writes `Shared/sample_ios_experiment.json`, an iOS ExperimentSetup export the Kotlin app must import.
    @Test func sharedIOSExperimentSample() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Shared/sample_ios_experiment.json")
        let workbench = Workbench(defaults: isolatedDefaults())
        workbench.reactionText = "14N(p,g)15O"
        workbench.beamEnergy = 380; workbench.residualExcitation = 6176.3; workbench.temperatureT9 = 0.06
        workbench.layerThickness = 1500; workbench.layerAngle = 55; workbench.beamCurrent = 250; workbench.chargeState = 1
        workbench.sFactorModel = SFactorModel(kind: .table, table: [.init(energy: 100, s: 1.7), .init(energy: 300, s: 1.9)])
        workbench.resonances = [NarrowResonance(energy: 259.0, strength: 0.0127)]
        workbench.screeningPotential = 600; workbench.isotopicAbundance = 99.6
        let data = try JSONEncoder().encode(ExperimentSetup(workbench))
        if ProcessInfo.processInfo.environment["GAMOW_WRITE_REFERENCE"] == "1" { try data.write(to: url) }
        let stored = try JSONDecoder().decode(ExperimentSetup.self, from: Data(contentsOf: url))
        #expect(stored.reactionText == "14N(p,g)15O" && stored.beamEnergy == 380 && stored.resonances.count == 1)
    }

    @Test func everyPresetParses() {
        for item in Presets.groups.flatMap(\.items) {
            #expect((try? Reaction(notation: item)) != nil, "\(item)")
        }
    }

    @Test func recentAndSavedReactions() throws {
        let defaults = isolatedDefaults()
        let workbench = Workbench(defaults: defaults)
        workbench.reactionText = "14N(p,g)15O"
        workbench.reactionText = "22Ne(p,g)23Na"
        workbench.reactionText = "14N(p,g)15O"
        #expect(workbench.recentReactions.prefix(2) == ["14N(p,g)15O", "22Ne(p,g)23Na"])
        let r = try #require(workbench.reaction)
        workbench.toggleSaved(r)
        #expect(Workbench(defaults: defaults).savedReactions == ["14N(p,g)15O"])
        workbench.toggleSaved(r)
        #expect(workbench.savedReactions.isEmpty)
    }

    @Test func astrophysicsInputsStayWithTheirReaction() throws {
        let defaults = isolatedDefaults()
        let workbench = Workbench(defaults: defaults)
        workbench.reactionText = "14N(p,g)15O"
        #expect(workbench.sFactorIsPlaceholder)
        #expect(abs(workbench.isotopicAbundance - 99.6205) < 1e-6)     // NUBASE2020 natural ¹⁴N (nubase2020.csv)
        workbench.sFactorModel = SFactorModel(s0: 1.6)
        workbench.screeningPotential = 600
        #expect(!workbench.sFactorIsPlaceholder)

        workbench.reactionText = "17O(p,a)14N"
        #expect(workbench.sFactorModel.s0 == 1)                        // not ¹⁴N(p,γ)'s 1.6 keV b
        #expect(workbench.screeningPotential == 0)
        #expect(workbench.sFactorIsPlaceholder)

        workbench.reactionText = "14N(p,g)15O"
        #expect(workbench.sFactorModel.s0 == 1.6)
        #expect(workbench.screeningPotential == 600)

        // Survives a relaunch.
        let reloaded = Workbench(defaults: defaults)
        #expect(reloaded.sFactorModel.s0 == 1.6 && !reloaded.sFactorIsPlaceholder)
        reloaded.reactionText = "17O(p,a)14N"
        #expect(reloaded.sFactorModel.s0 == 1)
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
