import NucPhysKit
import SwiftUI

/// ENSDF level scheme of a nuclide: the cached copy, else a download when online data are allowed.
enum LevelSchemeLoader {
    static func load(_ nuclide: Nuclide) async -> LevelScheme? {
        if let cached = await LiveChartClient.shared.cached(z: nuclide.z, a: nuclide.a) { return cached }
        guard UserDefaults.standard.object(forKey: "livechart.autoload") as? Bool ?? true else { return nil }
        return try? await LiveChartClient.shared.levelScheme(z: nuclide.z, a: nuclide.a)
    }
}

/// Residual excitation energy, typed or picked from the residual's ENSDF levels.
struct ResidualLevelField: View {
    let residual: Nuclide?
    @Binding var keV: Double
    let unit: EnergyUnit
    /// Highest level worth offering (the energy available in the exit channel), keV.
    var maximum: Double = .infinity

    @State private var scheme: LevelScheme?

    var body: some View {
        HStack(spacing: 10) {
            EnergyField(title: "Residual Eₓ", keV: $keV, unit: unit)
            if let levels = offered, !levels.isEmpty {
                Menu {
                    Button("Ground state") { keV = 0 }
                    ForEach(levels) { level in
                        Button("\(Fmt.keV(level.energy, digits: 6)) keV  \(level.spinParity)") { keV = level.energy }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                        .accessibilityLabel("Choose a level of \(residual?.label ?? "the residual")")
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .task(id: residual) {
            scheme = nil
            if let residual { scheme = await LevelSchemeLoader.load(residual) }
        }
    }

    private var offered: [Level]? {
        scheme?.levels.filter { $0.energy > 0 && $0.energy <= maximum }.prefix(40).map { $0 }
    }
}
