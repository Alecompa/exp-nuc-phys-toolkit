import NucPhysKit
import SwiftData
import SwiftUI

/// App root: tab bar (sidebar on iPad) with Tools, Nuclides, Notebook and Settings.
public struct RootView: View {
    @State private var workbench = Workbench()
    @State private var selection: AppTab = .tools

    public init() {}

    public var body: some View {
        TabView(selection: $selection) {
            Tab("Tools", systemImage: "square.grid.2x2.fill", value: AppTab.tools) {
                ToolsHomeView()
            }
            Tab("Nuclides", systemImage: "atom", value: AppTab.nuclides) {
                NuclidesView()
            }
            Tab("Notebook", systemImage: "book.pages.fill", value: AppTab.notebook) {
                NotebookView()
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .minimizingTabBar()
        .environment(workbench)
        .tint(.accent)
        .modelContainer(for: NotebookEntry.self)
    }
}

enum AppTab: Hashable { case tools, nuclides, notebook, settings }

enum Route: Hashable {
    case tool(Tool)
    case nuclide(Nuclide)
}

extension ShapeStyle where Self == Color {
    /// Brand accent: a warm stellar orange, used for primary actions and selection only.
    static var accent: Color { Color(red: 0.96, green: 0.45, blue: 0.16) }
}

extension View {
    /// Shared destinations for every navigation stack in the app.
    func appDestinations(namespace: Namespace.ID) -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .tool(.qValue):
                QValueView().zoomTransition(id: Tool.qValue, in: namespace)
            case .tool(.kinematics):
                KinematicsView().zoomTransition(id: Tool.kinematics, in: namespace)
            case .tool(.stopping):
                StoppingPowerView().zoomTransition(id: Tool.stopping, in: namespace)
            case .tool(.energyLoss):
                EnergyLossView().zoomTransition(id: Tool.energyLoss, in: namespace)
            case .tool(.rutherford):
                RutherfordView().zoomTransition(id: Tool.rutherford, in: namespace)
            case .tool(.gamowWindow):
                GamowWindowView().zoomTransition(id: Tool.gamowWindow, in: namespace)
            case .tool(.penetrability):
                PenetrabilityView().zoomTransition(id: Tool.penetrability, in: namespace)
            case .tool(.sFactor):
                SFactorView().zoomTransition(id: Tool.sFactor, in: namespace)
            case .tool(.resonanceStrength):
                ResonanceStrengthView().zoomTransition(id: Tool.resonanceStrength, in: namespace)
            case .tool(.reactionRate):
                ReactionRateView().zoomTransition(id: Tool.reactionRate, in: namespace)
            case .tool(.gammaDoppler):
                GammaDopplerView().zoomTransition(id: Tool.gammaDoppler, in: namespace)
            case .tool(.yieldEstimate):
                YieldEstimateView().zoomTransition(id: Tool.yieldEstimate, in: namespace)
            case .tool(.beamCurrent):
                BeamCurrentView().zoomTransition(id: Tool.beamCurrent, in: namespace)
            case .tool(.detector):
                DetectorView().zoomTransition(id: Tool.detector, in: namespace)
            case .tool(.sources):
                SourcesView().zoomTransition(id: Tool.sources, in: namespace)
            case .tool(.decay):
                DecayView().zoomTransition(id: Tool.decay, in: namespace)
            case .tool(.constants):
                ConstantsView().zoomTransition(id: Tool.constants, in: namespace)
            case .tool(.units):
                UnitConverterView().zoomTransition(id: Tool.units, in: namespace)
            case .tool(.exfor):
                ExforToolView().zoomTransition(id: Tool.exfor, in: namespace)
            case .tool(.formulas):
                FormulaSheetView().zoomTransition(id: Tool.formulas, in: namespace)
            case .nuclide(let n):
                NuclideDetailView(nuclide: n).zoomTransition(id: n.id, in: namespace)
            }
        }
    }
}
