import Charts
import NucPhysKit
import SwiftUI

struct GammaDopplerView: View {
    @Environment(Workbench.self) private var workbench
    @State private var editingSetup = false
    @AppStorage("doppler.e0") private var e0 = 0.0              // keV, at rest
    @AppStorage("doppler.customBeta") private var customBeta = false
    @AppStorage("doppler.beta") private var betaValue = 0.01
    @AppStorage("doppler.angle") private var angle = 55.0       // degrees
    @AppStorage("doppler.distance") private var distance = 5.0  // cm, source to detector face
    @AppStorage("doppler.radius") private var radius = 3.5      // cm, crystal radius

    var body: some View {
        let reaction = workbench.reaction
        let k = reaction.map { TwoBodyKinematics(reaction: $0, beamEnergy: workbench.reactionEnergy,
                                                 residualExcitation: workbench.residualExcitation) }
        let beta = customBeta ? betaValue : (k?.beta ?? betaValue)
        let theta = angle * .pi / 180
        let half = Geometry.halfOpeningAngle(radius: radius, distance: distance)
        let e = GammaDoppler.energy(e0, beta: beta, angle: theta)
        let range = GammaDoppler.range(e0, beta: beta, angle: theta, halfOpening: half)
        let mean = GammaDoppler.meanOverCone(e0, beta: beta, angle: theta, halfOpening: half, samples: 30)
        let spread = range.upperBound - range.lowerBound
        let det = workbench.resolutionModel.fwhm(at: e)
        let total = (det * det + pow(0.68 * spread, 2)).squareRoot()

        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    if let reaction { ReactionHeader(reaction: reaction) { editingSetup = true } }
                    HeroNumber(value: Fmt.keV(e, digits: 6), unit: "keV",
                               caption: "\(Fmt.keV(e0, digits: 6)) keV γ at \(Fmt.number(angle, decimals: 1))°")
                    HStack(spacing: 8) {
                        StatusBadge(text: "Shift \(e - e0 >= 0 ? "+" : "")\(Fmt.significant(e - e0, digits: 3)) keV",
                                    symbol: "arrow.left.and.right", tint: .pink)
                        StatusBadge(text: "β = \(Fmt.significant(beta, digits: 3))", symbol: "speedometer", tint: .teal)
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                if let r = reaction, !r.ejectile.isPhoton, workbench.residualExcitation == 0 {
                    Label("\(r.label) to the ground state emits no γ. Set a residual Eₓ in the setup.",
                          systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                NumberField(title: "γ energy at rest", value: $e0, unit: "keV", range: 0...1e5)
                if let r = reaction, let ecm = workbench.reactionEnergyCM, r.ejectile.isPhoton {
                    let primary = ecm + r.qValue(residualExcitation: workbench.residualExcitation)
                    Button("Primary capture γ, \(Fmt.keV(primary, digits: 5)) keV") { e0 = primary.rounded(toPlaces: 2) }
                        .font(.callout)
                }
                if workbench.residualExcitation > 0, let r = reaction {
                    Button("\(r.residual.label) level \(Fmt.keV(workbench.residualExcitation, digits: 5)) keV → ground state") {
                        e0 = GammaDoppler.recoilCorrected(transition: workbench.residualExcitation, mass: r.residual.kinematicMass).rounded(toPlaces: 2)
                    }
                    .font(.callout)
                }
                Toggle("Custom recoil velocity", isOn: $customBeta.animation(.smooth))
                if customBeta {
                    NumberField(title: "β = v/c", value: $betaValue, range: 0...0.999)
                } else {
                    ValueRow(label: "β", value: Fmt.significant(beta, digits: 4),
                             note: reaction?.ejectile.isPhoton == true ? "Compound nucleus (centre of mass)" : "Centre of mass (mean recoil)")
                }
            } header: {
                Text("Emitter")
            } footer: {
                Text(reaction?.ejectile.isPhoton == false ? "The recoil velocity depends on the ejectile angle; β is its average." : "The compound nucleus moves with the centre of mass.")
            }

            Section {
                LabeledContent("Detector angle") { Text("\(Fmt.number(angle, decimals: 1))°").monospacedDigit() }
                Slider(value: Binding(get: { angle }, set: { angle = ($0 * 2).rounded() / 2 }), in: 0...180) { Text("Angle") }
                NumberField(title: "Distance to face", value: $distance, unit: "cm", range: 0...1e4)
                NumberField(title: "Crystal radius", value: $radius, unit: "cm", range: 0...100)
                ValueRow(label: "Half-opening angle", value: Fmt.angle(half, decimals: 1))
                ValueRow(label: "Solid angle", value: Fmt.significant(Geometry.diskSolidAngle(radius: radius, distance: distance) / (4 * .pi) * 100, digits: 3),
                         unit: "% of 4π")
            } header: {
                Text("Detector")
            }

            Section {
                DopplerChart(e0: e0, beta: beta, angle: angle, half: half * 180 / .pi)
                    .frame(height: 220)
                    .padding(.vertical, 6)
                ValueRow(label: "Energy range on the face", value: "\(Fmt.keV(range.lowerBound, digits: 6))–\(Fmt.keV(range.upperBound, digits: 6))", unit: "keV")
                ValueRow(label: "Mean over the face", value: Fmt.keV(mean, digits: 6), unit: "keV")
                ValueRow(label: "Kinematic spread", value: Fmt.significant(spread, digits: 3), unit: "keV")
                ValueRow(label: "Detector FWHM", value: Fmt.significant(det, digits: 3), unit: "keV", note: "Detector Response model")
                ValueRow(label: "Expected peak FWHM", value: Fmt.significant(total, digits: 3), unit: "keV",
                         note: "Spread as a box, added in quadrature")
            } header: {
                Text("Line shape")
            } footer: {
                Text("E = E₀ √(1−β²)/(1 − β cos θ). Assumes the emitter does not slow down before decaying (lifetime ≪ stopping time); otherwise the line is partly attenuated (DSAM).")
            }
        }
        .groupedList()
        .scrollDismissesKeyboard(.interactively)
        .keyboardDoneButton()
        .navigationTitle("Gamma Doppler")
        .inlineTitle()
        .sheet(isPresented: $editingSetup) { ReactionSetupSheet() }
        .onAppear {
            guard e0 == 0, let r = reaction else { return }
            if r.ejectile.isPhoton, let ecm = workbench.reactionEnergyCM {
                e0 = max(1, ecm + r.qValue(residualExcitation: workbench.residualExcitation)).rounded(toPlaces: 2)
            } else if workbench.residualExcitation > 0 {
                e0 = GammaDoppler.recoilCorrected(transition: workbench.residualExcitation, mass: r.residual.kinematicMass).rounded(toPlaces: 2)
            }
        }
        .notebookSnapshot {
            var s = NotebookSnapshot(tool: .gammaDoppler, title: "\(Fmt.keV(e0)) keV γ at \(Fmt.number(angle, decimals: 1))°",
                                     subtitle: reaction?.label ?? "")
            s.add("Emitter", "E₀", Fmt.keV(e0, digits: 7), "keV")
            s.add("Emitter", "β", Fmt.significant(beta, digits: 5))
            s.add("Detector", "Angle", Fmt.number(angle, decimals: 1), "°")
            s.add("Detector", "Half-opening", Fmt.angle(half, decimals: 2))
            s.add("Line", "Energy at axis", Fmt.keV(e, digits: 7), "keV")
            s.add("Line", "Range", "\(Fmt.keV(range.lowerBound, digits: 7))–\(Fmt.keV(range.upperBound, digits: 7))", "keV")
            s.add("Line", "Expected FWHM", Fmt.significant(total, digits: 3), "keV")
            return s
        }
    }
}

private struct DopplerChart: View {
    let e0: Double, beta: Double, angle: Double, half: Double

    var body: some View {
        let pts = stride(from: 0.0, through: 180, by: 3).map { ($0, GammaDoppler.energy(e0, beta: beta, angle: $0 * .pi / 180)) }
        Chart {
            RectangleMark(xStart: .value("θ", max(0, angle - half)), xEnd: .value("θ", min(180, angle + half)))
                .foregroundStyle(.pink.opacity(0.14))
            RuleMark(y: .value("E₀", e0))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.secondary)
            ForEach(pts, id: \.0) { p in
                LineMark(x: .value("θ", p.0), y: .value("E", p.1))
                    .foregroundStyle(.pink)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
            PointMark(x: .value("θ", angle), y: .value("E", GammaDoppler.energy(e0, beta: beta, angle: angle * .pi / 180)))
                .foregroundStyle(.pink)
                .symbolSize(70)
        }
        .chartXScale(domain: 0...180)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: [0, 30, 60, 90, 120, 150, 180]) { v in
                AxisGridLine(); AxisTick()
                AxisValueLabel { if let x = v.as(Double.self) { Text("\(Int(x))°") } }
            }
        }
        .chartXAxisLabel("θ (lab)", alignment: .leading)
        .chartYAxisLabel("keV")
        .accessibilityLabel("Doppler-shifted energy versus detector angle")
    }
}
