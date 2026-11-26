#if os(macOS)
import NucPhysKit
import SwiftData
import SwiftUI

/// Mac window: a sidebar with the current setup, every tool by category and the data views; the selected
/// tool on the right. Spectrum files dropped on the window open in Spectrum Analysis.
public struct MacRootView: View {
    @State private var workbench = Workbench()
    @SceneStorage("mac.selection") private var stored = "tool:kinematics"
    @State private var editingSetup = false
    @State private var path: [Route] = []
    @Namespace private var zoom

    public init() {}

    enum Item: Hashable {
        case tool(Tool), nuclides, experiments, notebook

        var key: String {
            switch self {
            case .tool(let t): "tool:\(t.rawValue)"
            case .nuclides: "nuclides"
            case .experiments: "experiments"
            case .notebook: "notebook"
            }
        }

        init?(key: String) {
            switch key {
            case "nuclides": self = .nuclides
            case "experiments": self = .experiments
            case "notebook": self = .notebook
            default:
                guard key.hasPrefix("tool:"), let t = Tool(rawValue: String(key.dropFirst(5))) else { return nil }
                self = .tool(t)
            }
        }
    }

    private var selection: Binding<Item?> {
        Binding(get: { Item(key: stored) }, set: { if let i = $0 { stored = i.key; path = [] } })
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section {
                    MacSetupSummary { editingSetup = true }
                }
                ForEach(ToolCatalog.sections) { section in
                    Section(section.title) {
                        ForEach(section.tools) { tool in
                            Label(tool.title, systemImage: tool.symbol).tag(Item.tool(tool))
                        }
                    }
                }
                Section("Data") {
                    Label("Nuclides", systemImage: "atom").tag(Item.nuclides)
                    Label("Experiments", systemImage: "flask").tag(Item.experiments)
                    Label("Notebook", systemImage: "book.pages.fill").tag(Item.notebook)
                }
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 260)
        } detail: {
            detail
        }
        .sheet(isPresented: $editingSetup) {
            ReactionSetupSheet().frame(minWidth: 520, idealWidth: 560, minHeight: 640, idealHeight: 760)
        }
        .onReceive(NotificationCenter.default.publisher(for: MacCommand.editSetup)) { _ in editingSetup = true }
        .onReceive(NotificationCenter.default.publisher(for: MacCommand.openSpectrum)) { _ in
            selection.wrappedValue = .tool(.spectrumAnalysis)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(name: MacCommand.presentImporter, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: MacCommand.beamStep)) { note in
            guard let sign = note.object as? Double else { return }
            let step = UserDefaults.standard.object(forKey: "beam.step") as? Double ?? 10
            workbench.beamEnergy = max(0, ((workbench.beamEnergy + sign * step) / step).rounded() * step)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            selection.wrappedValue = .tool(.spectrumAnalysis)
            // Let the analysis view appear before it receives the file.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(name: MacCommand.loadSpectrum, object: url)
            }
            return true
        }
        #if DEBUG
        // Screenshot automation: GAMOW_MAC_SELECT=<sidebar key>, GAMOW_OPEN_SETUP=1, GAMOW_SPECTRUM_FILE=<path>.
        .onAppear {
            let env = ProcessInfo.processInfo.environment
            if let key = env["GAMOW_MAC_SELECT"], Item(key: key) != nil { stored = key }
            if env["GAMOW_OPEN_SETUP"] == "1" { editingSetup = true }
        }
        #endif
        .environment(workbench)
        .tint(.accent)
        .modelContainer(for: [NotebookEntry.self, ExperimentRecord.self])
    }

    @ViewBuilder private var detail: some View {
        switch Item(key: stored) ?? .tool(.kinematics) {
        case .tool(let t):
            NavigationStack(path: $path) {
                routeDestination(.tool(t), namespace: zoom)
                    .readableContentWidth(1100)
                    .appDestinations(namespace: zoom)
            }
            .id(t)
        case .nuclides: NuclidesView()
        case .experiments: ExperimentsView().readableContentWidth()
        case .notebook: NotebookView().readableContentWidth()
        }
    }
}

/// The shared setup at the top of the sidebar.
private struct MacSetupSummary: View {
    @Environment(Workbench.self) private var workbench
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ReactionTitle(reaction: workbench.reaction, fallback: workbench.reactionText,
                              font: .system(.title3, design: .rounded, weight: .semibold))
                Spacer()
                Button("Edit", action: edit).controlSize(.small)
            }
            Text("\(Fmt.energy(workbench.beamEnergy, unit: workbench.energyUnit, decimals: workbench.energyUnit == .keV ? 1 : 4)) \(workbench.energyUnit.label) beam"
                 + (workbench.residualExcitation > 0 ? " · Eₓ \(Fmt.keV(workbench.residualExcitation)) keV" : ""))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if let t = workbench.stoppingTarget {
                Text(t.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Menu commands of the Mac app, delivered to the window by notification.
public enum MacCommand {
    public static let openSpectrum = Notification.Name("gamow.openSpectrum")
    public static let loadSpectrum = Notification.Name("gamow.loadSpectrum")
    static let presentImporter = Notification.Name("gamow.presentImporter")
    public static let editSetup = Notification.Name("gamow.editSetup")
    /// object: +1.0 or −1.0 beam-energy steps.
    public static let beamStep = Notification.Name("gamow.beamStep")
}

/// Menus and keyboard shortcuts for the Mac app.
public struct GamowMacCommands: Commands {
    public init() {}

    public var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Spectrum…") { NotificationCenter.default.post(name: MacCommand.openSpectrum, object: nil) }
                .keyboardShortcut("o")
        }
        CommandMenu("Setup") {
            Button("Edit Reaction Setup…") { NotificationCenter.default.post(name: MacCommand.editSetup, object: nil) }
                .keyboardShortcut("k")
            Divider()
            Button("Raise Beam Energy") { NotificationCenter.default.post(name: MacCommand.beamStep, object: 1.0) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Lower Beam Energy") { NotificationCenter.default.post(name: MacCommand.beamStep, object: -1.0) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        }
    }
}

/// The Settings window (⌘,).
public struct MacSettingsView: View {
    public init() {}
    public var body: some View {
        SettingsView()
            .environment(Workbench())
            .frame(width: 520, height: 560)
    }
}
#endif
