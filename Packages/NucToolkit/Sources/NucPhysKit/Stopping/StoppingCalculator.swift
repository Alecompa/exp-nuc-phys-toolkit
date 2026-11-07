import Foundation

/// Stopping powers, ranges and energy loss of an ion in a target, following SRIM-2013 as
/// reconstructed by LunaSRIM. Stopping cross sections are in eV/(10¹⁵ atoms/cm²).
public struct StoppingCalculator: Sendable {
    public let ion: StoppingIon
    public let target: StoppingTarget
    let data: SRIMData

    public init(ion: StoppingIon, target: StoppingTarget, data: SRIMData = .shared) {
        self.ion = ion
        self.target = target
        self.data = data
    }

    public struct Stopping: Hashable, Sendable {
        public let electronic: Double
        public let nuclear: Double
        public var total: Double { electronic + nuclear }
    }

    /// Bragg-rule stopping with the compound correction applied once (SR tables, TRIM, energy loss).
    /// Nuclear stopping with SRIM's pair coefficients.
    public func stopping(at energy: Double) throws -> Stopping {
        var se = 0.0, sn = 0.0
        for (c, f) in zip(target.components, target.fractions) {
            se += f * (try SRIMStopping.electronic(z1: ion.z, m1: ion.mass, z2: c.z, energy: energy,
                                                   gas: target.isGas, correction: target.compoundCorrection, data: data))
            sn += f * SRIMStopping.nuclear(z1: ion.z, m1: ion.mass, z2: c.z, m2: c.mass, energy: energy, data: data)
        }
        return Stopping(electronic: se, nuclear: sn)
    }

    /// The SR module's list mode, which applies the compound correction a second time below 10 MeV.
    public func listModeStopping(at energy: Double) throws -> Stopping {
        let s = try stopping(at: energy)
        let corr = target.compoundCorrection
        guard energy < 10_000, corr != 1, corr != 0 else { return s }
        return Stopping(electronic: s.electronic * (try SRIMStopping.fade(corr, ePerU: energy / ion.mass, z1: 1)),
                        nuclear: s.nuclear)
    }

    /// Converts a stopping cross section (eV/(10¹⁵ atoms/cm²)) to `unit`.
    public func convert(_ s: Double, to unit: StoppingUnit) -> Double {
        s * unit.factor(ion: ion, target: target)
    }

    // MARK: - Range tables (SR module)

    public struct RangeRow: Hashable, Sendable {
        /// keV
        public let energy: Double
        /// eV/(10¹⁵ atoms/cm²)
        public let electronic: Double
        /// eV/(10¹⁵ atoms/cm²), ZBL universal form as in SRModule.exe's tables
        public let nuclear: Double
        /// Å
        public let projectedRange: Double
        /// Å
        public let longitudinalStraggling: Double
        /// Å
        public let lateralStraggling: Double
    }

    public enum RangeError: Error, Equatable {
        case negativeVariance
        case energyTooHigh
        case invalidEnergies
    }

    static let mantissa: [Double] = [0, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 2.0, 2.25, 2.5, 2.75,
                                     3.0, 3.25, 3.5, 3.75, 4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0, 8.0, 9.0]

    /// SRIM's stopping and range table between `emin` and `emax` (keV), 26 energies per decade.
    /// PRAL-type moment integration (Biersack) as in SRModule.exe; see LunaSRIM docs/physics.md §4.
    public func rangeTable(emin: Double, emax: Double) throws -> [RangeRow] {
        let (emin, emax) = (min(emin, emax), max(emin, emax))
        guard emax > 0 else { throw RangeError.invalidEnergies }
        let m = Self.mantissa
        let comps = target.components, frac = target.fractions
        let z1 = ion.z, m1 = ion.mass
        let meanMass = target.meanMass

        // Energy grid (keV), 1-based like SRModule.exe.
        var grid: [Double] = [0]
        var i = 1
        while i <= 1000 {
            let j = (i - 1) % 26 + 1
            let k = Double((i - 1) / 26) - 3
            grid.append(m[j] * pow(10, k))
            if grid[i] > emax { break }
            i += 1
        }
        let n = min(i, 1000)

        // Electronic stopping on the grid, eV/Å (N with 0.60223).
        let conv = 0.60223 * target.density / meanMass
        var se = [Double](repeating: 0, count: n + 1)
        for (k, c) in comps.enumerated() {
            for i in 1...n {
                let s: Double
                do {
                    s = try SRIMStopping.electronic(z1: z1, m1: m1, z2: c.z, energy: grid[i], gas: target.isGas,
                                                    correction: target.compoundCorrection, data: data) * 10
                } catch { throw RangeError.energyTooHigh }
                se[i] += frac[k] * s
            }
        }
        for i in 1...n { se[i] *= conv }

        // Nuclear stopping and its second moment per element (universal ZBL form).
        let pi = 3.1415926
        let nDensity = target.density * 0.6023 / meanMass
        var a = [Double](), g = [Double](), epsf = [Double](), snf = [Double]()
        var sumA = 0.0, sumG = 0.0
        for (k, c) in comps.enumerated() {
            let ak = c.mass / m1
            a.append(ak)
            sumA += ak * frac[k]
            let gk = 4 * ak / pow(1 + ak, 2)
            g.append(gk)
            sumG += gk * frac[k]
            let sc = 0.4685 / (pow(Double(z1), 0.23) + pow(Double(c.z), 0.23))
            let ef = sc * ak / ((1 + ak) * Double(z1) * Double(c.z) * 14.4)
            epsf.append(ef)
            snf.append(pi * sc * sc * gk * nDensity / ef)
        }
        func nuclear(_ energy: Double, _ c4: Double) -> (sv: [Double], st: [Double]) {
            var sv = [Double](repeating: 0, count: comps.count), st = sv
            for k in comps.indices {
                let eps = energy * epsf[k]
                let s = 0.5 * log(1.1383 * eps + 1) / (pow(eps, 0.21226) * 0.01321 + eps + c4 * eps.squareRoot())
                sv[k] = snf[k] * s
                let t = 1 / (6.684 / pow(eps, 1.0494) + 0.197 / pow(eps, 1.6991) + 4)
                st[k] = g[k] * t * snf[k] / epsf[k]
            }
            return (sv, st)
        }

        // Starting point at 1.1 eV: low-energy solution fixed by S_n / S_e.
        var (i350, i1e0, i198, i214) = (1, 0, 2, 0)
        var en = m[i350 + 1] * pow(10, Double(i1e0))
        var (sv, st) = nuclear(en, 0.19593)
        var sn = 0.0, stt = 0.0
        for k in comps.indices { sn += sv[k] * frac[k]; stt += st[k] * frac[k] }
        var idx = 1
        var ek = en / 1000
        while idx < n, grid[idx] <= ek { idx += 1 }
        var seE = se[idx]
        let x38 = sumA / (seE / sn + 1)
        let x320 = 1 / (1 - stt / (sumG * en * sn))
        var rp = 2 * en / (sumA * sn * (1 / x38 + 1))
        var r2 = (1 + x38) * rp * rp
        var lat = r2 / (x320 / x38 + 2)

        let toCrossSection = 0.1 / conv          // eV/Å → eV/(10¹⁵ atoms/cm²), as SRModule.exe prints
        var rows: [RangeRow] = []
        var last: Double?
        func append(_ lon: Double, _ lat: Double) throws {
            var lon = lon, lat = lat
            if lon < 0 {
                lon = 0
                if lat < 0 { lat = 0 }
            }
            guard lat >= 0 else { throw RangeError.negativeVariance }
            rows.append(RangeRow(energy: en / 1000, electronic: seE * toCrossSection, nuclear: sn * toCrossSection,
                                 projectedRange: rp, longitudinalStraggling: lon.squareRoot(),
                                 lateralStraggling: (lat / 2).squareRoot()))
            last = en
        }

        let steps = 50
        let eminEV = emin * 1000 - 0.2, emaxEV = emax * 1000
        while true {
            if !(en < eminEV) { try append(r2 - lat - rp * rp, lat) }
            i350 = i198
            i1e0 = i214
            i198 = (i350 + 1) % 26
            if i198 == 0 { i198 = 26 }
            if i198 == 1 { i214 += 1 }
            let lo = m[i350] * pow(10, Double(i1e0))
            var hi = m[i198] * pow(10, Double(i214))
            if emaxEV < hi { hi = emaxEV }
            let de = (hi - lo) / Double(steps)
            guard de > 0 else { break }
            for _ in 0..<steps {
                en += de
                (sv, st) = nuclear(en, 0.19594)
                sn = 0
                var s310 = 0.0, sdc = 0.0, s1b0 = 0.0
                for k in comps.indices {
                    sn += frac[k] * sv[k]
                    s310 += frac[k] * a[k] * sv[k]
                    sdc += frac[k] * a[k] * st[k]
                    s1b0 += frac[k] * pow(1 - a[k], 2) * st[k]
                }
                ek = en / 1000
                while idx < n, grid[idx] < ek { idx += 1 }
                idx = min(max(idx, 2), n)
                let fr = (ek - grid[idx - 1]) / (grid[idx] - grid[idx - 1])
                seE = se[idx - 1] + fr * (se[idx] - se[idx - 1])
                let stot = sn + seE
                let x88 = 2 * s310 * en
                let xb0 = 2 * sdc
                let x204 = 4 * xb0
                let x154 = 4 * en * stot
                let x290 = de / en
                let x260 = 1 - x204 / x154
                rp = (4 * en * en - (x88 + sdc) * rp) * x290 / (x154 - xb0) + rp
                r2 += 2 * rp * de / stot
                let x108 = x154 - x204
                let x14c = 2 * x88 - s1b0
                let x178 = en * x204 * rp / stot
                if x260 >= 0.01 {
                    lat = ((r2 - 2 * lat) * x14c - x178) * x290 / x108 + lat
                } else {
                    lat = 0.5 * r2 - en * en * rp / (x88 - 0.5 * s1b0)
                }
            }
            if en >= emaxEV { break }
        }
        if last == nil || en > last! { try append(r2 - lat - rp * rp, lat) }
        return rows
    }

    /// Projected range and stragglings at `energy` (keV).
    public func range(at energy: Double) throws -> RangeRow {
        guard let row = try rangeTable(emin: energy, emax: energy).last else { throw RangeError.invalidEnergies }
        return row
    }

    // MARK: - Energy loss and straggling through a layer

    public struct EnergyLoss: Sendable {
        public struct Point: Hashable, Sendable {
            /// Å
            public let depth: Double
            /// keV
            public let energy: Double
            /// keV, one standard deviation (TRIM model)
            public let sigma: Double
        }
        public let energyIn: Double
        public let energyOut: Double
        public var energyLoss: Double { energyIn - energyOut }
        public let electronicLoss: Double
        public let nuclearLoss: Double
        /// keV, one standard deviation, TRIM's straggling model (Bohr with integer mean Z₂).
        public let sigma: Double
        /// keV, Bohr's formula with the exact mean Z₂.
        public let sigmaBohr: Double
        public var fwhm: Double { sigma * 2 * (2 * log(2)).squareRoot() }
        /// Path length in the layer, Å.
        public let pathLength: Double
        /// Mean energy along the path (energy at which a thin-target cross section is effectively measured), keV.
        public let meanEnergy: Double
        /// The ions stopped inside the layer (mean energy below 1 % of the initial energy).
        public let stopped: Bool
        public let profile: [Point]
    }

    /// Mean energy loss and energy straggling of ions of `energy` keV crossing `thickness` Å
    /// at `angle` degrees to the layer normal (LunaSRIM `straggling.energy_loss`, Eq. 26).
    /// `sigmaIn` (keV) is the energy spread of the incoming beam, e.g. after a previous layer; the variance
    /// equation then also follows how the slope of S widens or narrows it.
    public func energyLoss(energy: Double, thickness: Double, angle: Double = 0, sigmaIn: Double = 0,
                           steps: Int = 500) throws -> EnergyLoss {
        precondition(energy > 0 && thickness > 0)
        let nA3 = target.atomsPerA3
        let path = thickness / cos(angle * .pi / 180)
        // TRIM's integer mean Z₂ and Bohr straggling.
        let total = target.components.reduce(0) { $0 + $1.stoichiometry }
        var zz = 0
        for c in target.components {
            zz = Int((c.stoichiometry / total * Double(c.z) + Double(zz)).rounded(.toNearestOrEven))
        }
        let zExact = target.meanZ
        let z1 = Double(ion.z)
        let bohr = 177 * z1 * (Double(zz) * nA3).squareRoot()
        let kLow = (3.2 * 12 * nA3 / (ion.mass * 1000) * pow(Double(zz) + z1, 8.0 / 3.0)).squareRoot()
        let e2 = 14.39964
        let wBohr = 4 * Double.pi * e2 * e2 * z1 * z1 * zExact * nA3          // eV²/Å

        func wTrim(_ eKeV: Double) -> Double {
            let e = eKeV * 1000
            var w = kLow * e
            if w > bohr {
                let q = 1 - 1 / pow(1 + e / (ion.mass * 1000 * 931_494), 2)
                w = bohr * ((1 / q - 0.5) / (1 / q - 1))
            }
            return w * w / 12
        }
        // eV/Å
        func stop(_ e: Double) throws -> Stopping {
            let s = try stopping(at: e)
            return Stopping(electronic: s.electronic * 10 * nA3, nuclear: s.nuclear * 10 * nA3)
        }
        func slope(_ e: Double) throws -> Double {
            let d = 1e-3
            return (try stop(e * (1 + d)).total - stop(e * (1 - d)).total) / (2 * d * e * 1000)
        }
        func deriv(_ e: Double, _ v: Double, _ vb: Double) throws -> (Double, Double, Double) {
            let s = try stop(e).total, sp = try slope(e)
            return (-s / 1000, wTrim(e) - 2 * sp * v, wBohr - 2 * sp * vb)
        }

        let eStop = energy * 0.01
        let h = path / Double(steps)
        let v0 = pow(max(sigmaIn, 0) * 1000, 2)
        var x = 0.0, e = energy, v = v0, vb = v0
        var lossE = 0.0, lossN = 0.0
        var stopped = false
        var profile = [EnergyLoss.Point(depth: 0, energy: e, sigma: max(sigmaIn, 0))]
        for _ in 0..<steps {
            let k1 = try deriv(e, v, vb)
            let k2 = try deriv(max(e + h / 2 * k1.0, eStop / 2), v + h / 2 * k1.1, vb + h / 2 * k1.2)
            let k3 = try deriv(max(e + h / 2 * k2.0, eStop / 2), v + h / 2 * k2.1, vb + h / 2 * k2.2)
            let k4 = try deriv(max(e + h * k3.0, eStop / 2), v + h * k3.1, vb + h * k3.2)
            let de = h / 6 * (k1.0 + 2 * k2.0 + 2 * k3.0 + k4.0)
            let eNew = e + de
            if eNew <= eStop { stopped = true; break }
            let mid = try stop(max(e + de / 2, eStop / 2))
            lossE += -de * mid.electronic / mid.total
            lossN += -de * mid.nuclear / mid.total
            v = max(v + h / 6 * (k1.1 + 2 * k2.1 + 2 * k3.1 + k4.1), 0)
            vb = max(vb + h / 6 * (k1.2 + 2 * k2.2 + 2 * k3.2 + k4.2), 0)
            e = eNew
            x += h
            profile.append(.init(depth: x, energy: e, sigma: v.squareRoot() / 1000))
        }
        // Path-averaged energy (trapezoidal).
        var meanE = profile[0].energy
        if profile.count > 1, x > 0 {
            var s = 0.0
            for i in 1..<profile.count {
                s += (profile[i].depth - profile[i - 1].depth) * (profile[i].energy + profile[i - 1].energy) / 2
            }
            meanE = s / x
        }
        return EnergyLoss(energyIn: energy, energyOut: e, electronicLoss: lossE, nuclearLoss: lossN,
                          sigma: v.squareRoot() / 1000, sigmaBohr: vb.squareRoot() / 1000,
                          pathLength: path, meanEnergy: meanE, stopped: stopped, profile: profile)
    }
}
