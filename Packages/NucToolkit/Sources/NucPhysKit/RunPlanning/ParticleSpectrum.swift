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
    /// Elastic groups: Rutherford dσ/dΩ (lab, b/sr) per atom of the target material, i.e. weighted by the
    /// element's atom fraction and the isotope's abundance. nil for reaction groups.
    public var rutherford: Double? = nil
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
            let totalAtoms = material.components.reduce(0) { $0 + $1.stoichiometry }
            var seen = Set<Int>()
            for c in material.components where seen.insert(c.z).inserted {
                let same = material.components.filter { $0.z == c.z }
                let elementAtoms = same.reduce(0) { $0 + $1.stoichiometry }
                let atomFraction = elementAtoms / max(totalAtoms, 1e-300)
                // Each component of the element with its own share: a named isotope (enriched ¹³C next to ¹²C),
                // else the natural isotopes (NUBASE2020 abundances).
                var isotopes: [(Nuclide, Double)] = []
                for comp in same {
                    let share = comp.stoichiometry / max(elementAtoms, 1e-300)
                    if let a = comp.isotopeMassNumber, let n = table.nuclide(z: c.z, a: a) {
                        isotopes.append((n, share))
                    } else {
                        var natural = naturalIsotopes(z: c.z, table: table)
                        if natural.isEmpty, let n = table.nuclide(z: c.z, a: Int(comp.mass.rounded())) { natural = [(n, 1)] }
                        isotopes += natural.map { ($0.0, $0.1 * share) }
                    }
                }
                // The same isotope from two components is one scatterer.
                isotopes = Dictionary(isotopes.map { ($0.0, $0.1) }, uniquingKeysWith: +).map { ($0.key, $0.value) }
                    .sorted { $0.0.a < $1.0.a }
                out += elasticGroups(element: c.z, isotopes: isotopes, atomFraction: atomFraction,
                                     projectile: reaction.projectile, beamEnergy: beamEnergy, theta: theta, setup: setup)
            }
        }
        return out.sorted { ($0.detected ?? -1) > ($1.detected ?? -1) }
    }

    /// Stable isotopes of an element with their natural abundance fractions.
    public static func naturalIsotopes(z: Int, table: MassTable = .ame2020) -> [(Nuclide, Double)] {
        table.isotopes(z: z).compactMap { n in
            guard let ab = Nubase.nubase2020.groundState(z: z, a: n.a)?.abundance, ab > 0 else { return nil }
            return (n, ab / 100)
        }
    }

    /// Elastic scattering of the beam on one element: one group per isotope and kinematic branch, merged into
    /// a single abundance-weighted group when the isotopes are closer than half the detector resolution.
    private static func elasticGroups(element z: Int, isotopes: [(Nuclide, Double)], atomFraction: Double,
                                      projectile: Nuclide, beamEnergy: Double, theta: Double,
                                      setup: ParticleDetectorSetup) -> [ParticleGroup] {
        struct Hit { let nucleus: Nuclide; let weight: Double; let solution: KinematicSolution; let sigma: Double; let branch: Int }
        var hits: [Hit] = []
        for (n, w) in isotopes {
            let ruth = RutherfordScattering(projectile: projectile, target: n, beamEnergy: beamEnergy)
            let k = ruth.kinematics
            // Both branches when the projectile is heavier than the target: the slow one is the projectile
            // scattered at large c.m. angle, not the recoil. Equal masses: the θ* = π branch has no energy.
            for (i, s) in k.solutions(labAngle: theta).enumerated() where s.ejectileEnergy > 1e-6 * beamEnergy {
                let sigma = ruth.crossSectionCM(thetaCM: s.thetaCM) * s.jacobian
                hits.append(Hit(nucleus: n, weight: w, solution: s, sigma: sigma, branch: i))
            }
        }
        guard !hits.isEmpty else { return [] }
        let symbol = Elements.symbol(z: z) ?? "?"
        var out: [ParticleGroup] = []
        for branch in Set(hits.map(\.branch)).sorted() {
            let hs = hits.filter { $0.branch == branch }
            let es = hs.map(\.solution.ejectileEnergy)
            let suffix = branch > 0 ? " (slow branch)" : ""
            if hs.count > 1, (es.max()! - es.min()!) < setup.resolution / 2 {
                // Merge: the weighted mean energy, the main isotope's kinematics for the width.
                let wsum = hs.reduce(0) { $0 + $1.weight }
                let mean = hs.reduce(0) { $0 + $1.weight * $1.solution.ejectileEnergy } / wsum
                let main = hs.max { $0.weight < $1.weight }!
                var g = group(id: "e\(z)b\(branch)", kind: .elastic, particle: projectile, origin: "elastic on \(symbol)\(suffix)",
                              solution: main.solution, setup: setup, energy: mean)
                g.rutherford = atomFraction * hs.reduce(0) { $0 + $1.weight * $1.sigma }
                out.append(g)
            } else {
                for h in hs where h.weight >= 0.01 {
                    let pct = h.weight < 1 ? " (\(Int((100 * h.weight).rounded())) %)" : ""
                    var g = group(id: "e\(z)-\(h.nucleus.a)b\(branch)", kind: .elastic, particle: projectile,
                                  origin: "elastic on \(h.nucleus.label)\(pct)\(suffix)", solution: h.solution, setup: setup)
                    g.rutherford = atomFraction * h.weight * h.sigma
                    out.append(g)
                }
            }
        }
        return out
    }

    private static func group(id: String, kind: ParticleGroup.Kind, particle: Nuclide, origin: String,
                              solution s: KinematicSolution, setup: ParticleDetectorSetup, energy: Double? = nil) -> ParticleGroup {
        let kinematic = abs(s.energySlope) * 2 * setup.halfOpening * .pi / 180
        let emitted = energy ?? s.ejectileEnergy
        let label = particleLabel(particle)
        guard particle.z > 0 else {
            let fwhm = (setup.resolution * setup.resolution + pow(0.68 * kinematic, 2)).squareRoot()
            return ParticleGroup(id: id, kind: kind, particle: label, origin: origin, emitted: emitted,
                                 detected: emitted, fwhm: fwhm, stoppedIn: nil, neutral: true)
        }
        let ion = StoppingIon(nuclide: particle)
        var e = emitted, sigma = 0.0
        var stoppedIn: Int?
        for (i, foil) in setup.foils.enumerated() where foil.thickness > 0 {
            guard e > 0, let r = try? StoppingCalculator(ion: ion, target: foil.material)
                .energyLoss(energy: e, thickness: foil.thickness, angle: foil.angle, sigmaIn: sigma) else { stoppedIn = i; break }
            if r.stopped || r.energyOut <= 0 { stoppedIn = i; break }
            e = r.energyOut; sigma = r.sigma
        }
        let straggling = 2 * (2 * log(2)).squareRoot() * sigma
        let fwhm = (setup.resolution * setup.resolution + straggling * straggling + pow(0.68 * kinematic, 2)).squareRoot()
        return ParticleGroup(id: id, kind: kind, particle: label, origin: origin, emitted: emitted,
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
