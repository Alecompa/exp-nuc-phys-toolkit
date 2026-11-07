import Foundation

/// One kinematic solution for the ejectile (particle 3) and the matching residual (particle 4).
/// Angles are in radians, energies in keV, momenta in keV/c.
public struct KinematicSolution: Hashable, Sendable {
    public let thetaCM: Double
    public let ejectileAngle: Double
    public let ejectileEnergy: Double
    public let ejectileMomentum: Double
    public let residualAngle: Double
    public let residualEnergy: Double
    public let residualMomentum: Double
    /// dΩ_cm / dΩ_lab for the ejectile: σ_lab(θ) = jacobian · σ_cm(θ*).
    public let jacobian: Double
    /// dT₃/dθ_lab, keV per radian (kinematic broadening).
    public let energySlope: Double
}

/// Relativistic two-body kinematics for 1 + 2 → 3 + 4 with particle 2 at rest.
///
/// Masses in keV/c² (photon: 0), beam kinetic energy in keV. Inverse kinematics is handled
/// naturally: when the centre-of-mass moves faster than the ejectile in the CM frame there are
/// two solutions per lab angle up to `maxEjectileAngle`.
public struct TwoBodyKinematics: Sendable {
    public let m1, m2, m3, m4: Double
    public let beamEnergy: Double

    public let sqrtS: Double
    /// Velocity (β) and Lorentz factor of the centre of mass.
    public let beta: Double
    public let gamma: Double
    /// Momentum of the products in the CM frame (keV/c) and their CM total energies.
    public let pStar: Double
    public let e3Star: Double
    public let e4Star: Double

    public init(m1: Double, m2: Double, m3: Double, m4: Double, beamEnergy: Double) {
        self.m1 = m1; self.m2 = m2; self.m3 = m3; self.m4 = m4
        self.beamEnergy = beamEnergy
        let e1 = beamEnergy + m1
        let p1 = (beamEnergy * (beamEnergy + 2 * m1)).squareRoot()
        let eTot = e1 + m2
        let s = m1 * m1 + m2 * m2 + 2 * e1 * m2
        sqrtS = s.squareRoot()
        beta = p1 / eTot
        gamma = eTot / sqrtS
        let sum = m3 + m4, diff = m3 - m4
        let arg = (s - sum * sum) * (s - diff * diff)
        pStar = arg > 0 ? arg.squareRoot() / (2 * sqrtS) : 0
        e3Star = (s + m3 * m3 - m4 * m4) / (2 * sqrtS)
        e4Star = (s + m4 * m4 - m3 * m3) / (2 * sqrtS)
    }

    /// Kinematics for a reaction, with optional excitation energies (keV) of ejectile and residual.
    public init(reaction: Reaction, beamEnergy: Double, residualExcitation: Double = 0, ejectileExcitation: Double = 0) {
        let m3 = reaction.ejectile.isPhoton ? 0 : reaction.ejectile.mass + ejectileExcitation
        self.init(m1: reaction.projectile.kinematicMass, m2: reaction.target.kinematicMass,
                  m3: m3, m4: reaction.residual.kinematicMass + residualExcitation, beamEnergy: beamEnergy)
    }

    /// True when the channel is open at this beam energy.
    public var isOpen: Bool { sqrtS > m3 + m4 }

    /// Kinetic energy available in the CM frame, keV (relativistic).
    public var centerOfMassEnergy: Double { sqrtS - m1 - m2 }

    /// Ejectile velocity in the CM frame.
    public var ejectileBetaCM: Double { e3Star > 0 ? pStar / e3Star : 0 }

    /// Maximum lab angle of the ejectile (rad), or nil when every angle up to π is reachable.
    public var maxEjectileAngle: Double? {
        guard isOpen, m3 > 0, beta > ejectileBetaCM else { return nil }
        let g3 = e3Star / m3
        let c2 = (1 - (g3 * g3) / (gamma * gamma)) / (beta * beta)
        return acos(min(1, max(0, c2)).squareRoot())
    }

    /// Maximum lab angle of the residual (rad), or nil when unrestricted.
    public var maxResidualAngle: Double? {
        guard isOpen, m4 > 0, beta > pStar / e4Star else { return nil }
        let g4 = e4Star / m4
        let c2 = (1 - (g4 * g4) / (gamma * gamma)) / (beta * beta)
        return acos(min(1, max(0, c2)).squareRoot())
    }

    /// Solution at a given CM angle of the ejectile (rad). Always unique.
    public func solution(cmAngle: Double) -> KinematicSolution? {
        guard isOpen else { return nil }
        let c = cos(cmAngle), s = sin(cmAngle)
        let pz3 = gamma * (pStar * c + beta * e3Star)
        let px3 = pStar * s
        let e3 = gamma * (e3Star + beta * pStar * c)
        let p3 = (pz3 * pz3 + px3 * px3).squareRoot()
        let theta3 = atan2(px3, pz3)

        let pz4 = gamma * (-pStar * c + beta * e4Star)
        let e4 = gamma * (e4Star - beta * pStar * c)
        let theta4 = atan2(pStar * s, pz4)
        let p4 = (pz4 * pz4 + px3 * px3).squareRoot()

        // dΩ*/dΩ = p₃² / (γ p* |p₃ − β E₃ cos θ₃|)
        let denom = gamma * pStar * abs(p3 - beta * e3 * cos(theta3))
        let jac = denom > 0 ? p3 * p3 / denom : .infinity

        // dT₃/dθ₃ = (dT₃/dθ*) / (dθ₃/dθ*), the latter by central difference.
        let h = 1e-5
        let tPlus = atan2(pStar * sin(cmAngle + h), gamma * (pStar * cos(cmAngle + h) + beta * e3Star))
        let tMinus = atan2(pStar * sin(cmAngle - h), gamma * (pStar * cos(cmAngle - h) + beta * e3Star))
        let dThetaLab = (tPlus - tMinus) / (2 * h)
        let dT = -gamma * beta * pStar * s
        let slope = abs(dThetaLab) > 1e-12 ? dT / dThetaLab : 0

        return KinematicSolution(
            thetaCM: cmAngle, ejectileAngle: theta3, ejectileEnergy: e3 - m3, ejectileMomentum: p3,
            residualAngle: theta4, residualEnergy: e4 - m4, residualMomentum: p4, jacobian: jac, energySlope: slope)
    }

    /// Solutions at a given ejectile lab angle (rad): zero, one, or two (inverse kinematics).
    /// The first element is the higher-energy branch.
    public func solutions(labAngle theta: Double) -> [KinematicSolution] {
        guard isOpen, pStar > 0 else { return [] }
        let c = cos(theta)
        let k = e3Star / gamma
        let a = 1 - beta * beta * c * c
        let disc = beta * beta * m3 * m3 * c * c - m3 * m3 + k * k
        guard disc >= 0, a > 0 else { return [] }
        let root = disc.squareRoot()
        var momenta = [(k * beta * c + root) / a]
        if root > 0 { momenta.append((k * beta * c - root) / a) }
        var result: [KinematicSolution] = []
        for p in momenta where p >= 0 && k + beta * p * c >= 0 {
            let cosStar = max(-1, min(1, (p * c / gamma - beta * e3Star) / pStar))
            if let sol = solution(cmAngle: acos(cosStar)) {
                result.append(sol)
            }
        }
        return result.sorted { $0.ejectileEnergy > $1.ejectileEnergy }
    }

    /// Ejectile curve sampled uniformly in CM angle — covers both branches in order.
    public func curve(samples: Int = 181) -> [KinematicSolution] {
        guard isOpen, samples > 1 else { return [] }
        return (0..<samples).compactMap { solution(cmAngle: Double.pi * Double($0) / Double(samples - 1)) }
    }
}

public extension Reaction {
    /// Excitation energy of the compound nucleus reached at this beam energy, keV:
    /// E_x = E_cm + S, with S the separation energy of the projectile in the compound nucleus.
    func compoundExcitation(beamEnergy: Double, table: MassTable = .ame2020) -> Double? {
        guard let cn = compoundNucleus(table: table) else { return nil }
        let separation = target.massExcess + projectile.massExcess - cn.massExcess
        let k = TwoBodyKinematics(m1: projectile.kinematicMass, m2: target.kinematicMass, m3: 0,
                                  m4: cn.kinematicMass, beamEnergy: beamEnergy)
        return k.centerOfMassEnergy + separation
    }
}

public extension Double {
    var degrees: Double { self * 180 / .pi }
    var radians: Double { self * .pi / 180 }
}
