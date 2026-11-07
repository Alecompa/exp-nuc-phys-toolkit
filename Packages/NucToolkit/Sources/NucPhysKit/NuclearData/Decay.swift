import Foundation

/// Exponential decay: activity, number of atoms, mass and elapsed time. Times in seconds, activities in Bq.
public enum RadioactiveDecay {
    public static let avogadro = 6.022_140_76e23

    public static func decayConstant(halfLife t: Double) -> Double { t == .infinity ? 0 : log(2) / t }

    /// A(t) = A₀ exp(−λt).
    public static func activity(initial a0: Double, elapsed t: Double, halfLife: Double) -> Double {
        a0 * exp(-decayConstant(halfLife: halfLife) * t)
    }

    /// Relative uncertainty of A(t) from that of the half-life: σ_A/A = λt · σ_T/T.
    public static func relativeActivityUncertainty(elapsed t: Double, halfLife: Double, halfLifeUncertainty u: Double) -> Double {
        decayConstant(halfLife: halfLife) * abs(t) * u / halfLife
    }

    /// N = A/λ.
    public static func atoms(activity: Double, halfLife: Double) -> Double {
        let l = decayConstant(halfLife: halfLife)
        return l > 0 ? activity / l : .infinity
    }

    public static func activity(atoms n: Double, halfLife: Double) -> Double { n * decayConstant(halfLife: halfLife) }

    /// Mass in grams of `n` atoms of molar mass `molarMass` (g/mol).
    public static func mass(atoms n: Double, molarMass: Double) -> Double { n * molarMass / avogadro }

    public static func atoms(mass grams: Double, molarMass: Double) -> Double { grams * avogadro / molarMass }

    /// Time for the activity to fall to `fraction` of its initial value.
    public static func time(toFraction fraction: Double, halfLife: Double) -> Double {
        -log(fraction) * halfLife / log(2)
    }

    /// Decays between t₁ and t₂ for an activity A₀ at t = 0: (A₀/λ)(e^{−λt₁} − e^{−λt₂}).
    public static func decays(initial a0: Double, from t1: Double, to t2: Double, halfLife: Double) -> Double {
        let l = decayConstant(halfLife: halfLife)
        guard l > 0 else { return a0 * (t2 - t1) }
        return a0 / l * (exp(-l * t1) - exp(-l * t2))
    }
}

/// A photon emitted in a decay: energy (keV) and intensity (% per decay).
public struct EmissionLine: Hashable, Sendable, Codable, Identifiable {
    public enum Kind: String, Sendable, Codable { case gamma, xray, annihilation }
    public let energy: Double
    public let intensity: Double
    public let intensityUncertainty: Double
    public let kind: Kind
    public var id: String { "\(kind.rawValue)\(energy)" }

    enum CodingKeys: String, CodingKey { case energy = "e", intensity = "i", intensityUncertainty = "di", kind }

    public init(energy: Double, intensity: Double, intensityUncertainty: Double = 0, kind: Kind = .gamma) {
        self.energy = energy; self.intensity = intensity; self.intensityUncertainty = intensityUncertainty; self.kind = kind
    }
}

/// A calibration source: its decaying state (NUBASE) and photon emissions (ENSDF via the IAEA LiveChart).
public struct CalibrationSource: Hashable, Sendable, Identifiable {
    public let state: NuclearState
    public let lines: [EmissionLine]
    public var id: String { state.plainLabel }
    public var label: String { state.label }

    /// Lines worth listing: γ rays and annihilation above `minIntensity` %, X rays above 5 %.
    public func prominentLines(minIntensity: Double = 1) -> [EmissionLine] {
        lines.filter { $0.kind == .xray ? $0.intensity >= 5 : $0.intensity >= minIntensity }
    }
}

public enum CalibrationSources {
    private struct File: Decodable {
        struct Entry: Decodable { let nuclide: String; let lines: [EmissionLine] }
        let sources: [Entry]
    }

    /// The bundled sources, in the order of `Tools/fetch_sources.py`.
    public static let all: [CalibrationSource] = {
        guard let url = MassTable.resourceURL(name: "calibration_sources", ext: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.sources.compactMap { e in
            Nubase.nubase2020.state(named: e.nuclide).map { CalibrationSource(state: $0, lines: e.lines) }
        }
    }()

    public static func source(named name: String) -> CalibrationSource? {
        all.first { $0.id.lowercased() == name.lowercased() }
    }
}

/// Air kerma from photon emitters: K̇ = A Σ Iᵢ Eᵢ (μ_en/ρ)ᵢ / (4πr²), unshielded point source.
public enum AirKerma {
    /// NIST mass energy-absorption coefficients of dry air (Hubbell & Seltzer), MeV → cm²/g.
    static let table: [(Double, Double)] = [
        (0.010, 4.742), (0.015, 1.334), (0.020, 0.5389), (0.030, 0.1537), (0.040, 0.06833), (0.050, 0.04098),
        (0.060, 0.03041), (0.080, 0.02407), (0.100, 0.02325), (0.150, 0.02496), (0.200, 0.02672), (0.300, 0.02872),
        (0.400, 0.02949), (0.500, 0.02966), (0.600, 0.02953), (0.800, 0.02882), (1.000, 0.02789), (1.250, 0.02666),
        (1.500, 0.02547), (2.000, 0.02345), (3.000, 0.02057), (4.000, 0.01870), (5.000, 0.01740), (6.000, 0.01647),
        (8.000, 0.01525), (10.00, 0.01450),
    ]

    /// μ_en/ρ of air at `energy` keV, cm²/g (log–log interpolation, clamped to 10 keV–10 MeV).
    public static func massEnergyAbsorption(energy keV: Double) -> Double {
        let e = min(max(keV / 1000, table.first!.0), table.last!.0)
        guard let i = table.firstIndex(where: { $0.0 >= e }), i > 0 else { return table.first!.1 }
        let (e0, m0) = table[i - 1], (e1, m1) = table[i]
        let t = log(e / e0) / log(e1 / e0)
        return exp(log(m0) + t * (log(m1) - log(m0)))
    }

    /// Air-kerma rate constant, µGy m² MBq⁻¹ h⁻¹, from photons above `cutoff` keV.
    public static func rateConstant(lines: [EmissionLine], cutoff: Double = 20) -> Double {
        let sum = lines.filter { $0.energy >= cutoff }
            .reduce(0) { $0 + $1.intensity / 100 * $1.energy * massEnergyAbsorption(energy: $1.energy) }  // keV cm²/g
        // keV → J: 1.602176634e-16; per gram → per kg: ×1000; 1/(4π r²) with r = 1 m = 100 cm.
        let gyPerDecay = sum * 1.602_176_634e-16 * 1000 / (4 * .pi * 1e4)
        return gyPerDecay * 1e6 * 3600 * 1e6           // per MBq, per hour, in µGy
    }

    /// Air-kerma rate, µGy/h, of `activity` Bq at `distance` m.
    public static func rate(lines: [EmissionLine], activity: Double, distance: Double, cutoff: Double = 20) -> Double {
        rateConstant(lines: lines, cutoff: cutoff) * activity / 1e6 / (distance * distance)
    }
}
