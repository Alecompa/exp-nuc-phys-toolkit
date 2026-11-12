import Foundation

/// A charged-particle detector (e.g. a silicon detector) at a laboratory angle, behind absorber foils.
public struct ParticleDetectorSetup: Hashable, Codable, Sendable {
    /// Laboratory angle to the beam, degrees.
    public var angle: Double = 135
    /// Intrinsic detector resolution, keV FWHM.
    public var resolution: Double = 15
    /// Half-opening angle of the detector seen from the target, degrees (kinematic broadening).
    public var halfOpening: Double = 2
    /// Absorbers between target and detector, in the order the particles cross them.
    public var foils: [DetectorFoil] = []
    /// Also show beam particles elastically scattered by each element of the target material.
    public var showElastic = true
    public init() {}
}

/// One group of particles reaching the detector: an energy before and after the foils.
public struct ParticleGroup: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case reaction, elastic }

    public let id: String
    public let kind: Kind
    /// Particle label, e.g. "α" or "p".
    public let particle: String
    /// What produced it, e.g. "⁷Li(p,α)" or "elastic on Ta".
    public let origin: String
    /// Kinetic energy leaving the target, keV.
    public let emitted: Double
    /// Energy after the foils, keV; nil when the particle stops in them.
    public let detected: Double?
    /// Expected peak FWHM in the detector, keV (resolution, foil straggling, kinematic spread).
    public let fwhm: Double
    /// Index of the foil the particle stops in.
    public let stoppedIn: Int?
    /// Neutral particles are not slowed by the foils and are usually not seen by a silicon detector.
    public let neutral: Bool
}

public enum ParticleSpectrum {
    /// Particle groups at the detector for the reaction and, optionally, for elastic scattering of the beam
    /// on each element of `material`. `beamEnergy` is the laboratory energy at which the reaction happens.
    public static func groups(reaction: Reaction, beamEnergy: Double, residualExcitation: Double,
                              material: StoppingTarget?, setup: ParticleDetectorSetup,
                              table: MassTable = .ame2020) -> [ParticleGroup] {
        guard beamEnergy > 0, setup.angle > 0, setup.angle < 180 else { return [] }
        let theta = setup.angle * .pi / 180
        var out: [ParticleGroup] = []

        if case .nuclide(let ejectile) = reaction.ejectile {
            let k = TwoBodyKinematics(reaction: reaction, beamEnergy: beamEnergy, residualExcitation: residualExcitation)
            let origin = "\(reaction.target.label)(\(reaction.projectile.reactionLabel),\(ejectile.reactionLabel))"
                + (residualExcitation > 0 ? " Eₓ \(Int(residualExcitation.rounded())) keV" : "")
            for (i, s) in k.solutions(labAngle: theta).enumerated() {
                out.append(group(id: "r\(i)", kind: .reaction, particle: ejectile, origin: origin, solution: s, setup: setup))
            }
        }

        if setup.showElastic, let material {
            var seen = Set<Int>()
            for c in material.components where seen.insert(c.z).inserted {
                let a = c.isotopeMassNumber ?? Int(c.mass.rounded())
                guard let nucleus = table.nuclide(z: c.z, a: a) ?? table.nuclide(z: c.z, a: a + 1) ?? table.nuclide(z: c.z, a: a - 1),
                      let elastic = try? Reaction(target: nucleus, projectile: reaction.projectile,
                                                  ejectile: .nuclide(reaction.projectile), residual: nucleus) else { continue }
                let k = TwoBodyKinematics(reaction: elastic, beamEnergy: beamEnergy)
                // Forward-only branch for a heavier projectile; the slow branch would be the recoil-like one.
                guard let s = k.solutions(labAngle: theta).first else { continue }
                out.append(group(id: "e\(c.z)", kind: .elastic, particle: reaction.projectile,
                                 origin: "elastic on \(nucleus.symbol)", solution: s, setup: setup))
            }
        }
        return out.sorted { ($0.detected ?? -1) > ($1.detected ?? -1) }
    }

    private static func group(id: String, kind: ParticleGroup.Kind, particle: Nuclide, origin: String,
                              solution s: KinematicSolution, setup: ParticleDetectorSetup) -> ParticleGroup {
        let kinematic = abs(s.energySlope) * 2 * setup.halfOpening * .pi / 180
        let label = particleLabel(particle)
        guard particle.z > 0 else {
            let fwhm = (setup.resolution * setup.resolution + pow(0.68 * kinematic, 2)).squareRoot()
            return ParticleGroup(id: id, kind: kind, particle: label, origin: origin, emitted: s.ejectileEnergy,
                                 detected: s.ejectileEnergy, fwhm: fwhm, stoppedIn: nil, neutral: true)
        }
        let ion = StoppingIon(nuclide: particle)
        var e = s.ejectileEnergy, sigma = 0.0
        var stoppedIn: Int?
        for (i, foil) in setup.foils.enumerated() where foil.thickness > 0 {
            guard e > 0, let r = try? StoppingCalculator(ion: ion, target: foil.material)
                .energyLoss(energy: e, thickness: foil.thickness, angle: foil.angle, sigmaIn: sigma) else { stoppedIn = i; break }
            if r.stopped || r.energyOut <= 0 { stoppedIn = i; break }
            e = r.energyOut; sigma = r.sigma
        }
        let straggling = 2 * (2 * log(2)).squareRoot() * sigma
        let fwhm = (setup.resolution * setup.resolution + straggling * straggling + pow(0.68 * kinematic, 2)).squareRoot()
        return ParticleGroup(id: id, kind: kind, particle: label, origin: origin, emitted: s.ejectileEnergy,
                             detected: stoppedIn == nil ? e : nil, fwhm: fwhm, stoppedIn: stoppedIn, neutral: false)
    }

    /// p, d, t, ³He, α, n by their usual symbols; other nuclides as ¹²C.
    public static func particleLabel(_ n: Nuclide) -> String {
        switch (n.z, n.a) {
        case (1, 1): "p"
        case (1, 2): "d"
        case (1, 3): "t"
        case (2, 4): "α"
        case (0, 1): "n"
        default: n.label
        }
    }
}
