import AppIntents
import Foundation
import NucPhysKit

// Shortcuts and Siri actions. They run without opening the app and return values that can be
// chained in the Shortcuts app.

struct QValueIntent: AppIntent {
    static let title: LocalizedStringResource = "Reaction Q Value"
    static let description = IntentDescription("Ground-state Q value and threshold of a nuclear reaction, from AME2020 masses.")

    @Parameter(title: "Reaction", description: "Reaction notation, e.g. 12C(p,g)13N or 7Li(p,a)4He")
    var reaction: String

    static var parameterSummary: some ParameterSummary { Summary("Q value of \(\.$reaction)") }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let r = try Reaction(notation: reaction)
        let q = r.qValue
        var text = "Q = \(format(q, 3)) ± \(format(r.qValueUncertainty, 3)) keV for \(r.plainLabel)."
        if q < 0 { text += " Threshold \(format(r.threshold(residualExcitation: 0), 2)) keV." }
        return .result(value: q, dialog: IntentDialog(stringLiteral: text))
    }
}

struct GamowPeakIntent: AppIntent {
    static let title: LocalizedStringResource = "Gamow Peak"
    static let description = IntentDescription("Gamow peak energy E₀ and width Δ of a charged-particle reaction at a stellar temperature.")

    @Parameter(title: "Reaction", description: "e.g. 12C(p,g)13N")
    var reaction: String

    @Parameter(title: "T₉", description: "Temperature in GK", default: 0.1)
    var t9: Double

    static var parameterSummary: some ParameterSummary { Summary("Gamow peak of \(\.$reaction) at T₉ = \(\.$t9)") }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let r = try Reaction(notation: reaction)
        guard r.projectile.z > 0, r.target.z > 0 else {
            return .result(value: 0, dialog: "The entrance channel has no Coulomb barrier.")
        }
        let c = ChargedChannel(projectile: r.projectile, target: r.target)
        let w = c.gamowWindow(t9: t9)
        return .result(value: w.peak,
                       dialog: IntentDialog(stringLiteral: "E₀ = \(format(w.peak, 1)) keV, Δ = \(format(w.width, 1)) keV (c.m.) at T₉ = \(t9)."))
    }
}

struct SourceActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "Source Activity Today"
    static let description = IntentDescription("Activity of a radioactive source now, from its certificate activity and date (NUBASE2020 half-life).")

    @Parameter(title: "Nuclide", description: "e.g. 60Co, 137Cs, 152Eu, 26mAl")
    var nuclide: String

    @Parameter(title: "Activity (kBq)", description: "Certificate activity in kBq")
    var activity: Double

    @Parameter(title: "Reference date")
    var referenceDate: Date

    static var parameterSummary: some ParameterSummary {
        Summary("Activity of \(\.$nuclide), \(\.$activity) kBq on \(\.$referenceDate)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let cert = SourceCertificate(nuclide: nuclide, activity: activity * 1000, referenceDate: referenceDate)
        guard let now = cert.activity(at: .now) else {
            return .result(value: 0, dialog: IntentDialog(stringLiteral: "Unknown or stable nuclide: \(nuclide)."))
        }
        let kBq = now.activity / 1000
        return .result(value: kBq,
                       dialog: IntentDialog(stringLiteral: "\(nuclide) now: \(format(kBq, 4, significant: true)) kBq (\(format(100 * now.activity / cert.activity, 1)) % of the certificate)."))
    }
}

struct HalfLifeIntent: AppIntent {
    static let title: LocalizedStringResource = "Half-Life"
    static let description = IntentDescription("Half-life of a nuclide or isomer from NUBASE2020, in seconds.")

    @Parameter(title: "Nuclide", description: "e.g. 14C, 26mAl, 180mTa")
    var nuclide: String

    static var parameterSummary: some ParameterSummary { Summary("Half-life of \(\.$nuclide)") }

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        guard let s = Nubase.nubase2020.state(named: nuclide), let t = s.halfLife else {
            return .result(value: 0, dialog: IntentDialog(stringLiteral: "No NUBASE2020 entry for \(nuclide)."))
        }
        if t == .infinity { return .result(value: t, dialog: IntentDialog(stringLiteral: "\(s.plainLabel) is stable.")) }
        let text = s.halfLifeText.isEmpty ? "\(t) s" : s.halfLifeText
        return .result(value: t, dialog: IntentDialog(stringLiteral: "T½(\(s.plainLabel)) = \(text)."))
    }
}

struct GamowShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: QValueIntent(), phrases: ["Q value in \(.applicationName)", "Compute a Q value with \(.applicationName)"],
                    shortTitle: "Q Value", systemImageName: "scalemass.fill")
        AppShortcut(intent: GamowPeakIntent(), phrases: ["Gamow peak in \(.applicationName)"],
                    shortTitle: "Gamow Peak", systemImageName: "sun.max.fill")
        AppShortcut(intent: SourceActivityIntent(), phrases: ["Source activity in \(.applicationName)"],
                    shortTitle: "Source Activity", systemImageName: "rays")
        AppShortcut(intent: HalfLifeIntent(), phrases: ["Half-life in \(.applicationName)"],
                    shortTitle: "Half-Life", systemImageName: "hourglass")
    }
}

private func format(_ x: Double, _ digits: Int, significant: Bool = false) -> String {
    significant
        ? x.formatted(.number.precision(.significantDigits(digits)).grouping(.never))
        : x.formatted(.number.precision(.fractionLength(digits)).grouping(.never))
}
