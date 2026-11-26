import Foundation

/// Where the γ detector sits and how fast recoils stop, for Doppler shifts of in-beam γ rays.
public struct GammaGeometry: Hashable, Codable, Sendable {
    /// Detector axis relative to the beam, degrees.
    public var angle: Double = 55
    /// Half-opening of the detector face seen from the target, degrees.
    public var halfOpening: Double = 0
    /// Recoils come to rest in the target (solid) after `stoppingTime` seconds; in a gas target they do not.
    public var recoilsStop = true
    /// Typical slowing-down time of a recoil in a solid, s (0.1–1 ps).
    public var stoppingTime = 0.5e-12
    public init() {}

    /// Probability that a level of mean life `tau` (s) decays before its recoil has stopped.
    /// Instantaneous emitters (tau = 0, e.g. the capture state) are always in flight.
    public func fractionInFlight(meanLife tau: Double?) -> Double {
        guard recoilsStop else { return 1 }
        guard let tau, tau > 0 else { return 1 }
        return 1 - exp(-stoppingTime / tau)
    }
}

/// A γ ray from a reaction as a detector at a given angle sees it.
public struct InBeamLine: Hashable, Sendable, Identifiable {
    public let label: String
    /// Emitter at rest: transition energy minus the recoil energy, keV.
    public let restEnergy: Double
    /// Centroid of the part emitted in flight, keV.
    public let shiftedEnergy: Double
    /// Half-width of the flat Doppler distribution of the part emitted in flight, keV
    /// (residual velocities isotropic in the c.m. frame project uniformly on the detector axis).
    public let halfWidth: Double
    /// Fraction emitted before the recoil stops (shifted and broadened); the rest sits at `restEnergy`.
    public let fractionInFlight: Double
    /// γ rays per reaction.
    public let intensity: Double
    public var id: String { "\(label)-\(restEnergy)" }

    /// Mean detected energy, keV.
    public var meanEnergy: Double { fractionInFlight * shiftedEnergy + (1 - fractionInFlight) * restEnergy }

    /// Spectrum lines for the Gaussian-response model: the stopped part as a sharp line, the part in flight
    /// as a Doppler box. `counts` is the photopeak area of the whole γ ray.
    public func spectrumLines(counts: Double, name: String? = nil) -> [SpectrumLine] {
        let n = name ?? label
        var out: [SpectrumLine] = []
        let moving = counts * fractionInFlight
        if counts - moving > 0 {
            out.append(SpectrumLine(name: n, energy: restEnergy, counts: counts - moving))
        }
        if moving > 0 {
            out.append(SpectrumLine(name: n + " (in flight)", energy: shiftedEnergy, counts: moving, dopplerHalfWidth: halfWidth))
        }
        return out
    }
}

/// In-beam γ-ray energies with recoil and Doppler corrections.
public enum InBeamGamma {
    /// Primary γ of radiative capture to `finalLevel` (keV) of the residual.
    /// The capture state decays at once and moves with the c.m. velocity; in its rest frame
    /// E*γ = (s − M_f²)/(2√s), exact (recoil included). The lab energy is E*γ/[γ_cm(1 − β_cm cos θ)],
    /// averaged over the detector face.
    public static func primary(_ r: Reaction, beamEnergy: Double, finalLevel: Double = 0,
                               geometry: GammaGeometry = GammaGeometry()) -> InBeamLine? {
        guard r.ejectile.isPhoton else { return nil }
        let k = TwoBodyKinematics(reaction: r, beamEnergy: beamEnergy, residualExcitation: finalLevel)
        guard k.isOpen, k.e3Star > 1 else { return nil }
        let eStar = k.e3Star
        let theta = geometry.angle * .pi / 180, open = geometry.halfOpening * .pi / 180
        let lab = GammaDoppler.meanOverCone(eStar, beta: k.beta, angle: theta, halfOpening: open)
        let spread = open > 0 ? GammaDoppler.range(eStar, beta: k.beta, angle: theta, halfOpening: open) : lab...lab
        // Strictly the capture state is never at rest; restEnergy is the c.m. value for reference.
        return InBeamLine(label: finalLevel > 0 ? "primary → \(fmt(finalLevel))" : "primary → g.s.",
                          restEnergy: eStar, shiftedEnergy: lab, halfWidth: (spread.upperBound - spread.lowerBound) / 2,
                          fractionInFlight: 1, intensity: 1)
    }

    /// A transition from `level` (keV) of the reaction's residual, with ENSDF energy `transition` (keV, recoil
    /// already included as tabulated; nil: level − recoil). The residual's lab velocity is the c.m. velocity plus
    /// an isotropic c.m. velocity β*₄; projected on the detector axis it is uniform in β_cm cos θ ± β*₄.
    public static func residualLevel(_ r: Reaction, beamEnergy: Double, level: Double, transition: Double? = nil,
                                     finalLevel: Double = 0, meanLife: Double?, intensity: Double = 1,
                                     geometry: GammaGeometry = GammaGeometry(), label: String? = nil) -> InBeamLine? {
        let k = TwoBodyKinematics(reaction: r, beamEnergy: beamEnergy, residualExcitation: level)
        guard k.isOpen else { return nil }
        let m = r.residual.kinematicMass + finalLevel
        let e0 = transition ?? GammaDoppler.recoilCorrected(transition: level - finalLevel, mass: m)
        let beta4 = k.e4Star > 0 ? k.pStar / k.e4Star : 0
        let theta = geometry.angle * .pi / 180
        let centre = e0 * (1 + k.beta * cos(theta))
        // Opening angle adds the spread of β_cm cos θ over the detector face.
        let open = geometry.halfOpening * .pi / 180
        let coneSpread = open > 0 ? e0 * k.beta * abs(cos(max(0, theta - open)) - cos(min(.pi, theta + open))) / 2 : 0
        return InBeamLine(label: label ?? "\(r.residual.label) \(fmt(level)) → \(fmt(finalLevel))",
                          restEnergy: e0, shiftedEnergy: centre, halfWidth: e0 * beta4 + coneSpread,
                          fractionInFlight: geometry.fractionInFlight(meanLife: meanLife), intensity: intensity)
    }

    static func fmt(_ e: Double) -> String {
        e == 0 ? "0" : String(format: e < 100 ? "%.1f" : "%.0f", e)
    }
}

// MARK: - Contaminants and room background

/// A beam-induced background reaction or a room-background line, with the γ rays it produces.
/// Each beam-induced source lists one complete cascade (every γ once per reaction); branchings to other
/// levels depend on the resonance and are left out, so the counts the user sets apply to each listed γ ray.
/// Energies and lifetimes are ENSDF values (IAEA LiveChart, retrieved 2026-11-20); capture primaries are
/// computed from AME2020 Q values and the beam energy.
public struct BackgroundSource: Identifiable, Hashable, Sendable {
    public enum Gamma: Hashable, Sendable {
        /// Primary capture γ to a residual level, keV.
        case primary(finalLevel: Double)
        /// Residual level → final level with the tabulated γ energy (keV) and the level's mean life (s).
        case level(Double, gamma: Double, to: Double, meanLife: Double, intensity: Double)
        /// A line from radioactive decay, emitted at rest (keV, γ per decay relative to the strongest line).
        case decay(Double, intensity: Double)
    }

    public let id: String
    /// Reaction notation for beam-induced sources; nil for room background.
    public let notation: String?
    public let name: String
    public let note: String
    public let gammas: [Gamma]

    public var reaction: Reaction? { notation.flatMap { try? Reaction(notation: $0) } }

    /// Lines at the given beam energy (keV, lab) and detector geometry; empty when the channel is closed.
    public func lines(beamEnergy: Double, geometry: GammaGeometry) -> [InBeamLine] {
        if notation == nil {
            return gammas.compactMap {
                guard case .decay(let e, let i) = $0 else { return nil }
                return InBeamLine(label: "\(name) \(InBeamGamma.fmt(e))", restEnergy: e, shiftedEnergy: e, halfWidth: 0,
                                  fractionInFlight: 0, intensity: i)
            }
        }
        guard let r = reaction else { return [] }
        return gammas.compactMap { g in
            switch g {
            case .primary(let f):
                return InBeamGamma.primary(r, beamEnergy: beamEnergy, finalLevel: f, geometry: geometry)
                    .map { InBeamLine(label: "\(r.label) \($0.label)", restEnergy: $0.restEnergy, shiftedEnergy: $0.shiftedEnergy,
                                      halfWidth: $0.halfWidth, fractionInFlight: 1, intensity: 1) }
            case .level(let lv, let e, let to, let tau, let i):
                // For capture the "residual" is the capture product: it moves with the c.m. plus the small recoil
                // from the primary γ, which β*₄ includes.
                return InBeamGamma.residualLevel(r, beamEnergy: beamEnergy, level: lv, transition: e, finalLevel: to,
                                                 meanLife: tau, intensity: i, geometry: geometry,
                                                 label: "\(r.label) \(r.residual.label) \(InBeamGamma.fmt(lv)) → \(InBeamGamma.fmt(to))")
            case .decay:
                return nil
            }
        }
    }

    /// True when the source can occur with this beam: same projectile and the channel open.
    public func applies(projectile: Nuclide, beamEnergy: Double) -> Bool {
        guard let r = reaction else { return true }
        return r.projectile == projectile && !lines(beamEnergy: beamEnergy, geometry: GammaGeometry()).isEmpty
    }
}

public enum BackgroundLibrary {
    /// τ = T½ / ln 2, or ħ/Γ for widths in eV.
    private static func tau(halfLife t: Double) -> Double { t / log(2.0) }
    private static func tau(widthEV g: Double) -> Double { 6.582_119_569e-16 / g }

    /// Common beam-induced contaminant reactions for proton and α beams.
    public static let beamInduced: [BackgroundSource] = [
        BackgroundSource(id: "19F(p,ag)", notation: "19F(p,a)16O", name: "¹⁹F(p,αγ)¹⁶O",
                         note: "Fluorine in targets, backings and o-rings; 6.13 MeV mostly emitted after the ¹⁶O recoil stopped (T½ = 18.4 ps).",
                         gammas: [.level(6129.89, gamma: 6128.63, to: 0, meanLife: tau(halfLife: 18.4e-12), intensity: 1)]),
        BackgroundSource(id: "15N(p,ag)", notation: "15N(p,a)12C", name: "¹⁵N(p,αγ)¹²C",
                         note: "Nitrogen in targets; the 4.44 MeV γ is emitted in flight (τ ≈ 61 fs) and Doppler broadened.",
                         gammas: [.level(4439.82, gamma: 4438.94, to: 0, meanLife: tau(widthEV: 10.8e-3), intensity: 1)]),
        BackgroundSource(id: "11B(p,g)", notation: "11B(p,g)12C", name: "¹¹B(p,γ)¹²C",
                         note: "Boron in backings and glass; capture through the 4.44 MeV level (the ground-state branch is not included).",
                         gammas: [.primary(finalLevel: 4439.82),
                                  .level(4439.82, gamma: 4438.94, to: 0, meanLife: tau(widthEV: 10.8e-3), intensity: 1)]),
        BackgroundSource(id: "13C(p,g)", notation: "13C(p,g)14N", name: "¹³C(p,γ)¹⁴N",
                         note: "Carbon build-up on the target; primary to the ground state.",
                         gammas: [.primary(finalLevel: 0)]),
        BackgroundSource(id: "12C(p,g)", notation: "12C(p,g)13N", name: "¹²C(p,γ)¹³N",
                         note: "Carbon build-up on the target; primary to the ground state.",
                         gammas: [.primary(finalLevel: 0)]),
        BackgroundSource(id: "2H(p,g)", notation: "d(p,g)3He", name: "²H(p,γ)³He",
                         note: "Deuterium in targets and water layers.",
                         gammas: [.primary(finalLevel: 0)]),
        BackgroundSource(id: "14N(p,g)", notation: "14N(p,g)15O", name: "¹⁴N(p,γ)¹⁵O",
                         note: "Nitrogen in targets; capture through the 6.18 MeV level only (other branches depend on energy and are not included).",
                         gammas: [.primary(finalLevel: 6176.3),
                                  .level(6176.3, gamma: 6174.9, to: 0, meanLife: tau(halfLife: 1.74e-15), intensity: 1)]),
        BackgroundSource(id: "23Na(p,g)", notation: "23Na(p,g)24Mg", name: "²³Na(p,γ)²⁴Mg",
                         note: "Sodium (glass, salts); primary to the first 2⁺ level and its 1369 keV γ.",
                         gammas: [.primary(finalLevel: 1368.667),
                                  .level(1368.667, gamma: 1368.625, to: 0, meanLife: tau(halfLife: 1.36e-12), intensity: 1)]),
        BackgroundSource(id: "27Al(p,g)", notation: "27Al(p,g)28Si", name: "²⁷Al(p,γ)²⁸Si",
                         note: "Aluminium in apertures and holders; primary to the first 2⁺ level and its 1779 keV γ.",
                         gammas: [.primary(finalLevel: 1779.03),
                                  .level(1779.03, gamma: 1778.969, to: 0, meanLife: tau(halfLife: 475e-15), intensity: 1)]),
        BackgroundSource(id: "23Na(p,ag)", notation: "23Na(p,a)20Ne", name: "²³Na(p,αγ)²⁰Ne",
                         note: "Sodium; 1634 keV γ from the first 2⁺ level of ²⁰Ne.",
                         gammas: [.level(1633.674, gamma: 1633.602, to: 0, meanLife: tau(halfLife: 0.73e-12), intensity: 1)]),
        BackgroundSource(id: "7Li(p,p'g)", notation: "7Li(p,p)7Li", name: "⁷Li(p,p′γ)⁷Li",
                         note: "Lithium; inelastic scattering to the 478 keV level.",
                         gammas: [.level(477.612, gamma: 477.595, to: 0, meanLife: tau(halfLife: 73e-15), intensity: 1)]),
        BackgroundSource(id: "10B(p,ag)", notation: "10B(p,a)7Be", name: "¹⁰B(p,αγ)⁷Be",
                         note: "Boron; 429 keV γ from the first excited state of ⁷Be.",
                         gammas: [.level(429.08, gamma: 429.07, to: 0, meanLife: tau(halfLife: 133e-15), intensity: 1)]),
        BackgroundSource(id: "19F(p,p'g)", notation: "19F(p,p)19F", name: "¹⁹F(p,p′γ)¹⁹F",
                         note: "Fluorine; 110 and 197 keV γ from inelastic scattering (long-lived levels, emitted at rest).",
                         gammas: [.level(109.894, gamma: 109.9, to: 0, meanLife: tau(halfLife: 0.591e-9), intensity: 1),
                                  .level(197.143, gamma: 197.1, to: 0, meanLife: tau(halfLife: 89.3e-9), intensity: 1)]),
        BackgroundSource(id: "23Na(p,p'g)", notation: "23Na(p,p)23Na", name: "²³Na(p,p′γ)²³Na",
                         note: "Sodium; 440 keV γ from inelastic scattering.",
                         // ENSDF lists Eγ = 440.5 keV above its 440.2 keV level; the level energy is used.
                         gammas: [.level(440.2, gamma: 440.2, to: 0, meanLife: tau(halfLife: 1.14e-12), intensity: 1)]),
        BackgroundSource(id: "27Al(p,p'g)", notation: "27Al(p,p)27Al", name: "²⁷Al(p,p′γ)²⁷Al",
                         note: "Aluminium; 844 and 1015 keV γ from inelastic scattering.",
                         gammas: [.level(843.76, gamma: 843.76, to: 0, meanLife: tau(halfLife: 35e-12), intensity: 1),
                                  .level(1014.56, gamma: 1014.52, to: 0, meanLife: tau(halfLife: 1.49e-12), intensity: 1)]),
        BackgroundSource(id: "13C(a,ng)", notation: "13C(a,n)16O", name: "¹³C(α,nγ)¹⁶O",
                         note: "Carbon build-up under α beams; the 6.13 MeV level opens only at high α energies.",
                         gammas: [.level(6129.89, gamma: 6128.63, to: 0, meanLife: tau(halfLife: 18.4e-12), intensity: 1)]),
        BackgroundSource(id: "9Be(a,ng)", notation: "9Be(a,n)12C", name: "⁹Be(α,nγ)¹²C",
                         note: "Beryllium; 4.44 MeV γ in flight.",
                         gammas: [.level(4439.82, gamma: 4438.94, to: 0, meanLife: tau(widthEV: 10.8e-3), intensity: 1)]),
        BackgroundSource(id: "12C(a,a'g)", notation: "12C(a,a)12C", name: "¹²C(α,α′γ)¹²C",
                         note: "Carbon under α beams, above the threshold of the 4.44 MeV level.",
                         gammas: [.level(4439.82, gamma: 4438.94, to: 0, meanLife: tau(widthEV: 10.8e-3), intensity: 1)]),
    ]

    /// Laboratory background lines (emitted at rest). Intensities relative within each source (ENSDF decay data).
    public static let room: [BackgroundSource] = [
        BackgroundSource(id: "40K", notation: nil, name: "⁴⁰K", note: "Concrete, glass, people.",
                         gammas: [.decay(1460.82, intensity: 1)]),
        BackgroundSource(id: "208Tl", notation: nil, name: "²⁰⁸Tl (²³²Th)", note: "Thorium chain.",
                         gammas: [.decay(2614.511, intensity: 1), .decay(583.187, intensity: 85 / 99.754),
                                  .decay(860.557, intensity: 12.5 / 99.754)]),
        BackgroundSource(id: "214Bi", notation: nil, name: "²¹⁴Bi (radon)", note: "Radon daughters; varies with ventilation.",
                         gammas: [.decay(609.321, intensity: 1), .decay(1764.491, intensity: 15.29 / 45.44),
                                  .decay(1120.294, intensity: 14.9 / 45.44), .decay(2204.1, intensity: 4.92 / 45.44)]),
        BackgroundSource(id: "511", notation: nil, name: "Annihilation", note: "e⁺e⁻ annihilation (Doppler broadened in reality).",
                         gammas: [.decay(510.999, intensity: 1)]),
    ]

    public static var all: [BackgroundSource] { beamInduced + room }

    public static func source(id: String) -> BackgroundSource? { all.first { $0.id == id } }
}

/// A background source switched on in the spectrum, with the photopeak area of its strongest γ ray.
public struct BackgroundEntry: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var counts: Double
    public var enabled: Bool
    public init(id: String, counts: Double = 1000, enabled: Bool = true) {
        self.id = id; self.counts = counts; self.enabled = enabled
    }
}
