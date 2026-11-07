import NucPhysKit
import SwiftUI

/// Rounded-square symbol tile, in the style of system Settings icons.
struct ToolIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 32
    var muted = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(tint.gradient)
                    .saturation(muted ? 0.15 : 1)
                    .opacity(muted ? 0.55 : 1)
            )
            .accessibilityHidden(true)
    }
}

/// A labelled value row: label leading, monospaced value trailing, optional uncertainty and unit.
struct ValueRow: View {
    let label: Text
    let value: String
    var uncertainty: String? = nil
    var unit: String? = nil
    var note: String? = nil

    init(label: String, value: String, uncertainty: String? = nil, unit: String? = nil, note: String? = nil) {
        self.init(label: Text(label), value: value, uncertainty: uncertainty, unit: unit, note: note)
    }

    init(label: Text, value: String, uncertainty: String? = nil, unit: String? = nil, note: String? = nil) {
        self.label = label
        self.value = value
        self.uncertainty = uncertainty
        self.unit = unit
        self.note = note
    }

    var body: some View {
        LabeledContent {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                if let uncertainty {
                    Text("± \(uncertainty)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                if let unit {
                    Text(unit).foregroundStyle(.secondary)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                label
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .contextMenu {
            let plain = NotebookEntry.csvField(value).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            Button("Copy Value", systemImage: "doc.on.doc") { Pasteboard.copy(plain) }
            if let unit {
                Button("Copy with Unit", systemImage: "doc.on.doc.fill") {
                    Pasteboard.copy(plain + (uncertainty.map { " ± " + NotebookEntry.csvField($0) } ?? "") + " " + unit)
                }
            }
        }
    }
}

/// Large result figure: rounded, monospaced digits, numeric content transition.
struct HeroNumber: View {
    let value: String
    var uncertainty: String? = nil
    let unit: String
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let caption {
                Text(caption)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(unit)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            if let uncertainty {
                Text("± \(uncertainty) \(unit)")
                    .font(.system(.callout, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }
}

/// Status capsule that never relies on colour alone: symbol + text + tint.
struct StatusBadge: View {
    let text: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(text)
        }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

/// Numeric energy entry with a unit suffix. Values are stored in keV.
struct EnergyField: View {
    let title: String
    @Binding var keV: Double
    let unit: EnergyUnit

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: Binding(
                    get: { keV / unit.scale },
                    set: { keV = max(0, $0) * unit.scale }
                ), format: .number.precision(.fractionLength(0...4)).grouping(.never))
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .decimalKeyboard()
                Text(unit.label).foregroundStyle(.secondary)
            }
        }
    }
}

/// Reaction notation rendered with a slightly larger, rounded face.
struct ReactionTitle: View {
    let reaction: Reaction?
    var fallback: String = "No reaction"
    var font: Font = .system(.title2, design: .rounded, weight: .semibold)

    var body: some View {
        Text(reaction?.label ?? fallback)
            .font(font)
            .contentTransition(.interpolate)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityLabel(reaction.map(Self.spoken) ?? fallback)
    }

    /// VoiceOver-friendly reading, e.g. "carbon 12, p gamma, nitrogen 13".
    static func spoken(_ r: Reaction) -> String {
        func name(_ n: Nuclide) -> String { "\(n.elementName) \(n.a)" }
        func light(_ p: ReactionParticle) -> String {
            switch p {
            case .photon: "gamma"
            case .nuclide(let n): n.reactionLabel == "α" ? "alpha" : n.reactionLabel.count <= 1 ? n.reactionLabel : name(n)
            }
        }
        return "\(name(r.target)), \(light(.nuclide(r.projectile))) \(light(r.ejectile)), \(name(r.residual))"
    }
}

/// Switch between the beam energy and the mean energy in the target layer (Energy Loss tool)
/// for the reaction tools.
struct TargetEnergyToggle: View {
    @Environment(Workbench.self) private var workbench

    var body: some View {
        @Bindable var workbench = workbench
        Toggle(isOn: $workbench.useTargetMeanEnergy.animation(.smooth)) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mean energy in target")
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var detail: String {
        guard let target = workbench.stoppingTarget else { return "No target material" }
        guard let t = workbench.stackOutcome?.target else { return "The beam stops before the target layer" }
        let unit = workbench.energyUnit
        let layers = workbench.layersBefore.isEmpty ? "" : " after \(workbench.layersBefore.count) layer\(workbench.layersBefore.count == 1 ? "" : "s")"
        return "\(Fmt.energy(t.meanEnergy, unit: unit)) \(unit.label) in \(Fmt.significant(ThicknessUnit.microgramCm2.fromAngstrom(workbench.layerThickness, target: target), digits: 3)) µg/cm² \(target.name)\(layers)"
    }
}
