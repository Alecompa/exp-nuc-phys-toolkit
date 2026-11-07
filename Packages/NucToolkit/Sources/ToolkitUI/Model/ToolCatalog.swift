import SwiftUI

/// Tools that are implemented and navigable.
enum Tool: String, CaseIterable, Identifiable, Hashable {
    case qValue, kinematics, rutherford, stopping, energyLoss
    case gamowWindow, penetrability, sFactor, resonanceStrength, reactionRate
    case gammaDoppler, yieldEstimate, beamCurrent, detector, sources, decay
    case constants, units, formulas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qValue: "Q-Value"
        case .kinematics: "Kinematics"
        case .stopping: "Stopping Power"
        case .energyLoss: "Energy Loss"
        case .rutherford: "Rutherford Scattering"
        case .gamowWindow: "Gamow Window"
        case .penetrability: "Penetrability & Widths"
        case .sFactor: "S-Factor ↔ Cross Section"
        case .resonanceStrength: "Resonance Strength"
        case .reactionRate: "Reaction Rate"
        case .gammaDoppler: "Gamma Doppler Shift"
        case .yieldEstimate: "Yield & Beam Time"
        case .beamCurrent: "Beam Current"
        case .detector: "Detector Response"
        case .sources: "Calibration Sources"
        case .decay: "Decay Calculator"
        case .constants: "Constants"
        case .units: "Unit Converter"
        case .formulas: "Formula Sheet"
        }
    }

    var subtitle: String {
        switch self {
        case .qValue: "Masses, thresholds, final states"
        case .kinematics: "Relativistic two-body, lab ↔ CM"
        case .stopping: "SRIM-2013, ranges, straggling"
        case .energyLoss: "Layer stacks, straggling, mean energy"
        case .rutherford: "dσ/dΩ lab and CM, monitor counts"
        case .gamowWindow: "E₀ and Δ vs T₉, Sommerfeld η"
        case .penetrability: "Coulomb penetrability, Wigner limit, θ²"
        case .sFactor: "Conversion with electron screening"
        case .resonanceStrength: "Thick-target yield ↔ ωγ, widths"
        case .reactionRate: "Nₐ⟨σv⟩ from S(E) and resonances"
        case .gammaDoppler: "Shift and broadening at a detector"
        case .yieldEstimate: "Count rate, statistics, beam time"
        case .beamCurrent: "µA ↔ pps, charge, power on target"
        case .detector: "Resolution model, efficiency fit"
        case .sources: "Activity today, γ lines, dose rate"
        case .decay: "Activity, atoms, mass, time"
        case .constants: "CODATA 2018, nuclear and atomic"
        case .units: "Energy, T₉, barns, lengths, activity"
        case .formulas: "Kinematics, astrophysics, decay, detectors"
        }
    }

    var symbol: String {
        switch self {
        case .qValue: "scalemass.fill"
        case .kinematics: "arrow.triangle.branch"
        case .stopping: "gauge.with.dots.needle.67percent"
        case .energyLoss: "arrow.down.right"
        case .rutherford: "scope"
        case .gamowWindow: "sun.max.fill"
        case .penetrability: "wave.3.right"
        case .sFactor: "function"
        case .resonanceStrength: "waveform.path.ecg"
        case .reactionRate: "flame.fill"
        case .gammaDoppler: "dot.radiowaves.right"
        case .yieldEstimate: "clock.badge.checkmark.fill"
        case .beamCurrent: "bolt.horizontal.fill"
        case .detector: "cylinder.split.1x2.fill"
        case .sources: "rays"
        case .decay: "hourglass"
        case .constants: "number"
        case .units: "arrow.left.arrow.right"
        case .formulas: "sum"
        }
    }

    var tint: Color {
        switch self {
        case .qValue: .indigo
        case .kinematics: .teal
        case .stopping: .orange
        case .energyLoss: .brown
        case .rutherford: .mint
        case .gamowWindow: .yellow
        case .penetrability: .cyan
        case .sFactor: .purple
        case .resonanceStrength: .pink
        case .reactionRate: .red
        case .gammaDoppler: .pink
        case .yieldEstimate: .green
        case .beamCurrent: .blue
        case .detector: .gray
        case .sources: .orange
        case .decay: .cyan
        case .constants: .gray
        case .units: .blue
        case .formulas: .indigo
        }
    }
}

/// Tools on the roadmap (see ROADMAP.md), shown so the app's direction is visible.
struct PlannedTool: Identifiable, Hashable {
    let title: String
    let symbol: String
    let tint: Color
    var id: String { title }
}

struct ToolSection: Identifiable {
    let title: String
    let tools: [Tool]
    let planned: [PlannedTool]
    var id: String { title }
}

enum ToolCatalog {
    static let sections: [ToolSection] = [
        ToolSection(title: "Reactions", tools: [.qValue, .kinematics, .rutherford, .gammaDoppler], planned: []),
        ToolSection(title: "Stopping & Targets", tools: [.stopping, .energyLoss], planned: []),
        ToolSection(title: "Nuclear Astrophysics",
                    tools: [.gamowWindow, .sFactor, .resonanceStrength, .reactionRate, .penetrability], planned: []),
        ToolSection(title: "Run Planning", tools: [.yieldEstimate, .beamCurrent], planned: []),
        ToolSection(title: "Detectors & Sources", tools: [.detector, .sources, .decay], planned: []),
        ToolSection(title: "Reference", tools: [.constants, .units, .formulas], planned: []),
    ]
}
