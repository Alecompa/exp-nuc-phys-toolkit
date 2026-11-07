import Foundation

/// One layer of a target stack: a material and its thickness along the layer normal.
public struct StackLayer: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var target: StoppingTarget
    /// Å
    public var thickness: Double

    public init(id: UUID = UUID(), target: StoppingTarget, thickness: Double) {
        self.id = id
        self.target = target
        self.thickness = thickness
    }
}

/// A beam crossing several layers in turn (window, dead layer, target, backing…).
public enum LayerStack {
    /// Energy loss in each layer the beam reaches, in beam order. The mean energy and the energy
    /// variance leaving one layer enter the next; the list ends early when the beam stops.
    /// The tilt `angle` (degrees to the normal) applies to every layer.
    public static func transport(ion: StoppingIon, layers: [StackLayer], energy: Double, angle: Double = 0,
                                 sigmaIn: Double = 0, data: SRIMData = .shared) throws -> [StoppingCalculator.EnergyLoss] {
        var out: [StoppingCalculator.EnergyLoss] = []
        var e = energy, sigma = sigmaIn
        for layer in layers where layer.thickness > 0 {
            let r = try StoppingCalculator(ion: ion, target: layer.target, data: data)
                .energyLoss(energy: e, thickness: layer.thickness, angle: angle, sigmaIn: sigma)
            out.append(r)
            if r.stopped { break }
            e = r.energyOut
            sigma = r.sigma
        }
        return out
    }
}

/// Gas targets: density from pressure and temperature (ideal gas).
public enum GasTarget {
    /// Boltzmann constant, J/K.
    static let boltzmann = 1.380_649e-23

    /// Atoms per cm³ of a gas at `pressure` mbar and `temperature` K with `atomsPerMolecule`.
    public static func atomDensity(pressure: Double, temperature: Double, atomsPerMolecule: Double) -> Double {
        pressure * 100 / (boltzmann * temperature) * 1e-6 * atomsPerMolecule
    }

    /// Mass density (g/cm³) to give `target` the atom density of the gas, with SRIM's Avogadro
    /// constant, so that `target.atomDensity` reproduces p/(kT) exactly.
    public static func density(of target: StoppingTarget, pressure: Double, temperature: Double,
                               atomsPerMolecule: Double) -> Double {
        atomDensity(pressure: pressure, temperature: temperature, atomsPerMolecule: atomsPerMolecule)
            * target.meanMass / 6.022e23
    }

    /// Atoms per molecule: 2 for the diatomic gases H, N, O, F, Cl, Br, I as single elements,
    /// 1 for other single elements, otherwise the sum of the stoichiometries (N₂O → 3).
    public static func defaultAtomsPerMolecule(_ target: StoppingTarget) -> Double {
        if target.components.count == 1 {
            let z = target.components[0].z
            let stoich = target.components[0].stoichiometry
            if stoich > 1, stoich == stoich.rounded() { return stoich }
            return [1, 7, 8, 9, 17, 35, 53].contains(z) ? 2 : 1
        }
        return max(1, target.components.reduce(0) { $0 + $1.stoichiometry })
    }
}
