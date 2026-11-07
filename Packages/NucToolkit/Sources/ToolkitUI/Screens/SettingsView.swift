import NucPhysKit
import SwiftUI

struct SettingsView: View {
    @Environment(Workbench.self) private var workbench
    @AppStorage("livechart.autoload") private var autoloadLevels = true
    @State private var cacheCleared = 0

    var body: some View {
        @Bindable var workbench = workbench
        NavigationStack {
            Form {
                Section {
                    Picker("Energy unit", selection: $workbench.energyUnit) {
                        ForEach(EnergyUnit.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Units")
                } footer: {
                    Text("Inputs and results across all tools use this unit.")
                }

                Section("Data") {
                    LabeledContent("Atomic masses", value: "AME2020")
                    LabeledContent("Nuclides", value: MassTable.ame2020.nuclides.count.formatted())
                    LabeledContent("Half-lives, Jπ, isomers", value: "NUBASE2020")
                    LabeledContent("Levels, γ rays", value: "ENSDF (IAEA)")
                    Link(destination: URL(string: "https://doi.org/10.1088/1674-1137/abddaf")!) {
                        Label("Wang et al., Chin. Phys. C 45, 030003 (2021)", systemImage: "doc.text")
                    }
                }

                Section {
                    LabeledContent("Kinematics", value: "Relativistic, ion masses")
                    LabeledContent("Q uncertainties", value: "Quadrature")
                } header: {
                    Text("Conventions")
                } footer: {
                    Text("Kinematic masses are atomic masses minus Z electron masses, so kinematic and tabulated Q values agree exactly. Mass correlations in AME are neglected.")
                }

                Section {
                    Toggle("Load ENSDF levels automatically", isOn: $autoloadLevels)
                    Button("Clear Level Cache", role: .destructive) { LiveChartCache.clear(); cacheCleared += 1 }
                } header: {
                    Text("Online data")
                } footer: {
                    Text("Level schemes come from the IAEA LiveChart of Nuclides the first time a nuclide is opened, and are cached for offline use for 30 days.")
                }

                Section {
                    NavigationLink { AboutView() } label: { Label("About Gamow", systemImage: "info.circle") }
                    NavigationLink { LicencesView() } label: { Label("Data Sources & Licences", systemImage: "books.vertical") }
                    NavigationLink { PrivacyView() } label: { Label("Privacy", systemImage: "hand.raised") }
                } footer: {
                    Text("Version \(AboutView.version)")
                }
            }
            .navigationTitle("Settings")
            .largeTitle()
            .sensoryFeedback(.success, trigger: cacheCleared)
        }
    }
}
