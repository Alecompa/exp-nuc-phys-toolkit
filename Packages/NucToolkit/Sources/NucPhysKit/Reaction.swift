import Foundation

/// A participant in a two-body reaction: a nuclide or a photon.
public enum ReactionParticle: Hashable, Sendable {
    case nuclide(Nuclide)
    case photon

    public var z: Int { if case .nuclide(let n) = self { n.z } else { 0 } }
    public var a: Int { if case .nuclide(let n) = self { n.a } else { 0 } }
    public var massExcess: Double { if case .nuclide(let n) = self { n.massExcess } else { 0 } }
    public var massExcessUncertainty: Double { if case .nuclide(let n) = self { n.massExcessUncertainty } else { 0 } }
    /// Nuclear (bare) mass in keV/c²; zero for a photon.
    public var mass: Double { if case .nuclide(let n) = self { n.kinematicMass } else { 0 } }
    public var nuclide: Nuclide? { if case .nuclide(let n) = self { n } else { nil } }
    public var isPhoton: Bool { self == .photon }
    public var reactionLabel: String { if case .nuclide(let n) = self { n.reactionLabel } else { "γ" } }
    public var label: String { if case .nuclide(let n) = self { n.label } else { "γ" } }
}

public enum ReactionError: LocalizedError, Equatable, Sendable {
    case malformed
    case unknownNuclide(String)
    case notConserved
    case noResidual

    public var errorDescription: String? {
        switch self {
        case .malformed: "Use the form Target(projectile,ejectile)Residual, e.g. 12C(p,γ)13N."
        case .unknownNuclide(let s): "“\(s)” is not in AME2020."
        case .notConserved: "Charge or mass number is not conserved."
        case .noResidual: "No bound residual nucleus for this channel."
        }
    }
}

/// A two-body reaction A(a,b)B, written target(projectile,ejectile)residual.
public struct Reaction: Hashable, Sendable {
    public let target: Nuclide
    public let projectile: Nuclide
    public let ejectile: ReactionParticle
    public let residual: Nuclide

    public init(target: Nuclide, projectile: Nuclide, ejectile: ReactionParticle, residual: Nuclide) throws {
        guard target.z + projectile.z == ejectile.z + residual.z,
              target.a + projectile.a == ejectile.a + residual.a else { throw ReactionError.notConserved }
        self.target = target
        self.projectile = projectile
        self.ejectile = ejectile
        self.residual = residual
    }

    /// Builds the reaction inferring the residual from conservation laws.
    public init(target: Nuclide, projectile: Nuclide, ejectile: ReactionParticle, table: MassTable = .ame2020) throws {
        let z = target.z + projectile.z - ejectile.z
        let a = target.a + projectile.a - ejectile.a
        guard z >= 0, a >= 1, let residual = table.nuclide(z: z, a: a) else { throw ReactionError.noResidual }
        try self.init(target: target, projectile: projectile, ejectile: ejectile, residual: residual)
    }

    /// Parses "12C(p,g)13N", "12C(p,γ)", "3He(a,g)7Be", "d(p,g)", "7Li(p,n)7Be".
    public init(notation: String, table: MassTable = .ame2020) throws {
        let s = notation.replacingOccurrences(of: " ", with: "")
        guard let open = s.firstIndex(of: "("), let close = s.firstIndex(of: ")"), open < close else {
            throw ReactionError.malformed
        }
        let targetText = String(s[..<open])
        let inner = s[s.index(after: open)..<close].split(separator: ",", omittingEmptySubsequences: false)
        guard inner.count == 2, !targetText.isEmpty else { throw ReactionError.malformed }
        let residualText = String(s[s.index(after: close)...])

        func nuclide(_ text: String) throws -> Nuclide {
            guard let n = table.nuclide(named: text) else { throw ReactionError.unknownNuclide(text) }
            return n
        }
        let target = try nuclide(targetText)
        let projectile = try nuclide(String(inner[0]))
        let ejText = String(inner[1])
        let ejectile: ReactionParticle = ["g", "γ", "gamma"].contains(ejText.lowercased())
            ? .photon : .nuclide(try nuclide(ejText))
        if residualText.isEmpty {
            try self.init(target: target, projectile: projectile, ejectile: ejectile, table: table)
        } else {
            try self.init(target: target, projectile: projectile, ejectile: ejectile, residual: try nuclide(residualText))
        }
    }

    // MARK: Energetics

    /// Ground-state Q value, keV, from AME atomic mass excesses (electron masses cancel).
    public var qValue: Double {
        target.massExcess + projectile.massExcess - ejectile.massExcess - residual.massExcess
    }

    /// Uncertainty of Q, keV (quadrature sum; AME correlations neglected).
    /// A nuclide present in both channels cancels exactly, so elastic scattering has σ(Q) = 0.
    public var qValueUncertainty: Double {
        var weight: [Nuclide: (count: Int, u: Double)] = [:]
        func add(_ n: Nuclide?, _ sign: Int) {
            guard let n else { return }
            weight[n, default: (0, n.massExcessUncertainty)].count += sign
        }
        add(target, 1); add(projectile, 1); add(ejectile.nuclide, -1); add(residual, -1)
        return weight.values.reduce(0) { sum, w in
            let s = Double(w.count) * w.u
            return sum + s * s
        }.squareRoot()
    }

    public var usesEstimatedMasses: Bool {
        target.isEstimated || projectile.isEstimated || residual.isEstimated || (ejectile.nuclide?.isEstimated ?? false)
    }

    /// Q value populating the residual at excitation energy `ex` (keV).
    public func qValue(residualExcitation ex: Double) -> Double { qValue - ex }

    /// Relativistic laboratory threshold of the projectile kinetic energy, keV (0 when exothermic).
    public func threshold(residualExcitation ex: Double = 0) -> Double {
        let m1 = projectile.kinematicMass, m2 = target.kinematicMass
        let mf = ejectile.mass + residual.kinematicMass + ex
        let t = (mf * mf - (m1 + m2) * (m1 + m2)) / (2 * m2)
        return max(0, t)
    }

    // MARK: Notation

    /// e.g. "¹²C(p,γ)¹³N"
    public var label: String {
        "\(target.label)(\(projectile.reactionLabel),\(ejectile.reactionLabel))\(residual.label)"
    }

    /// e.g. "12C(p,g)13N"
    public var plainLabel: String {
        let ej = ejectile.nuclide.map(Self.plainLight) ?? "g"
        return "\(target.plainLabel)(\(Self.plainLight(projectile)),\(ej))\(residual.plainLabel)"
    }

    private static func plainLight(_ n: Nuclide) -> String {
        switch (n.z, n.a) {
        case (0, 1): "n"
        case (1, 1): "p"
        case (1, 2): "d"
        case (1, 3): "t"
        case (2, 4): "a"
        default: n.plainLabel
        }
    }

    /// The compound system target+projectile (exists for radiative capture).
    public func compoundNucleus(table: MassTable = .ame2020) -> Nuclide? {
        table.nuclide(z: target.z + projectile.z, a: target.a + projectile.a)
    }
}
