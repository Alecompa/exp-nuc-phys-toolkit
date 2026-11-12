import Foundation

/// A chemical formula with arbitrary, also fractional, stoichiometry.
///
/// Accepted syntax: element symbols with counts (`Ta2N3`, `Ti0.5Al0.5N`), groups (`Ca(OH)2`),
/// hydrates with a leading multiplier (`CuSO4·5H2O` or `CuSO4*5H2O`; a `.` between digits is a decimal
/// point), deuterium and tritium
/// (`D`, `T`, as in `TiD2`) and isotopes in square brackets (`Ta2[17O]5`). Spaces are ignored.
public struct ChemicalFormula: Hashable, Sendable {
    public struct Part: Hashable, Sendable {
        public let z: Int
        /// Mass number for an isotopically pure entry (D, T, [17O]); nil for the natural element.
        public let massNumber: Int?
        public let count: Double
    }

    /// One entry per (element, isotope), in order of first appearance.
    public let parts: [Part]

    public enum ParseError: Error, Equatable, LocalizedError {
        case empty
        case unknownSymbol(String)
        case unknownIsotope(String)
        case unbalancedParentheses
        case unexpected(Character)
        case outOfRange(String)

        public var errorDescription: String? {
            switch self {
            case .empty: "Enter a formula, e.g. Ta2N3."
            case .unknownSymbol(let s): "Unknown element “\(s)”."
            case .unknownIsotope(let s): "Unknown isotope “\(s)”."
            case .unbalancedParentheses: "Unbalanced parentheses."
            case .unexpected(let c): "Unexpected “\(c)”."
            case .outOfRange(let s): "\(s) is beyond SRIM's range (Z = 1–92)."
            }
        }
    }

    public init(_ text: String) throws {
        let chars = Array(text.filter { !$0.isWhitespace })
        guard !chars.isEmpty else { throw ParseError.empty }
        var p = Parser(chars: chars)
        let counts = try p.formula()
        guard p.i == chars.count else { throw ParseError.unexpected(chars[p.i]) }
        guard !counts.isEmpty else { throw ParseError.empty }
        parts = counts
    }

    /// The formula with subscript counts and superscript mass numbers, e.g. "Ta₂N₃", "TiD₂", "Ta₂¹⁷O₅".
    public var label: String {
        parts.map { part in
            ChemicalFormula.symbol(z: part.z, massNumber: part.massNumber) + ChemicalFormula.subscriptCount(part.count)
        }.joined()
    }

    static func symbol(z: Int, massNumber: Int?) -> String {
        let s = Elements.symbol(z: z) ?? "?"
        guard let a = massNumber else { return s }
        if z == 1, a == 2 { return "D" }
        if z == 1, a == 3 { return "T" }
        return Superscript.digits(a) + s
    }

    /// "" for 1, otherwise the count in subscript digits (up to 4 significant figures).
    static func subscriptCount(_ x: Double) -> String {
        if abs(x - 1) < 1e-9 { return "" }
        let s = x.formatted(.number.precision(.significantDigits(1...4)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
        let map: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅",
                                           "6": "₆", "7": "₇", "8": "₈", "9": "₉", ".": "."]
        return String(s.map { map[$0] ?? $0 })
    }

    private struct Parser {
        let chars: [Character]
        var i = 0

        private var peek: Character? { i < chars.count ? chars[i] : nil }

        /// formula := term ( ('·' | '.' | '*') number? term )*
        mutating func formula() throws -> [Part] {
            var out = try sequence()
            // A "." left over here is a hydrate separator: decimal points were consumed by number().
            while let c = peek, c == "·" || c == "*" || c == "." || c == "•" {
                i += 1
                let mult = number() ?? 1
                out = merge(out, scale(try sequence(), mult))
            }
            return out
        }

        /// sequence := (element | '(' sequence ')' | '[' A Sym ']') count?
        mutating func sequence() throws -> [Part] {
            var out: [Part] = []
            loop: while let c = peek {
                var group: [Part]
                switch c {
                case "(":
                    i += 1
                    group = try sequence()
                    guard peek == ")" else { throw ParseError.unbalancedParentheses }
                    i += 1
                case "[":
                    i += 1
                    guard let a = number(), a == a.rounded(), a >= 1 else { throw ParseError.unexpected(peek ?? "[") }
                    let sym = try symbol()
                    guard peek == "]" else { throw ParseError.unbalancedParentheses }
                    i += 1
                    let z = try element(sym)
                    let label = "\(Int(a))\(sym)"
                    guard MassTable.ame2020.nuclide(z: z, a: Int(a)) != nil else { throw ParseError.unknownIsotope(label) }
                    group = [Part(z: z, massNumber: Int(a), count: 1)]
                case ")":
                    break loop
                case "]":
                    throw ParseError.unbalancedParentheses
                case _ where c.isUppercase:
                    let sym = try symbol()
                    if sym == "D" { group = [Part(z: 1, massNumber: 2, count: 1)] }
                    else if sym == "T" { group = [Part(z: 1, massNumber: 3, count: 1)] }
                    else { group = [Part(z: try element(sym), massNumber: nil, count: 1)] }
                case "·", "*", ".", "•":
                    break loop
                default:
                    throw ParseError.unexpected(c)
                }
                if let n = number() { group = scale(group, n) }
                out = merge(out, group)
            }
            return out
        }

        private mutating func symbol() throws -> String {
            guard let c = peek, c.isUppercase, c.isLetter else { throw ParseError.unexpected(peek ?? " ") }
            var s = String(c)
            i += 1
            if let d = peek, d.isLowercase, d.isLetter { s.append(d); i += 1 }
            return s
        }

        private func element(_ sym: String) throws -> Int {
            guard let z = Elements.symbols.firstIndex(of: sym), z > 0 else { throw ParseError.unknownSymbol(sym) }
            guard z <= 92 else { throw ParseError.outOfRange(sym) }
            return z
        }

        /// A decimal number, or nil if none starts here. "." counts as a decimal point only between digits.
        private mutating func number() -> Double? {
            var s = ""
            while let c = peek, c.isASCII, c.isNumber { s.append(c); i += 1 }
            if peek == ".", i + 1 < chars.count, chars[i + 1].isASCII, chars[i + 1].isNumber {
                s.append("."); i += 1
                while let c = peek, c.isASCII, c.isNumber { s.append(c); i += 1 }
            } else if s.isEmpty, peek == ".", i + 1 < chars.count, chars[i + 1].isNumber {
                // ".5" style
                s = "0."; i += 1
                while let c = peek, c.isASCII, c.isNumber { s.append(c); i += 1 }
            }
            return s.isEmpty ? nil : Double(s)
        }

        private func scale(_ parts: [Part], _ f: Double) -> [Part] {
            parts.map { Part(z: $0.z, massNumber: $0.massNumber, count: $0.count * f) }
        }

        private func merge(_ a: [Part], _ b: [Part]) -> [Part] {
            var out = a
            for p in b {
                if let k = out.firstIndex(where: { $0.z == p.z && $0.massNumber == p.massNumber }) {
                    out[k] = Part(z: p.z, massNumber: p.massNumber, count: out[k].count + p.count)
                } else {
                    out.append(p)
                }
            }
            return out
        }
    }
}

extension StoppingTarget {
    /// A target from a chemical formula. Isotopic entries use their AME2020 atomic mass,
    /// natural elements SRIM's atomic weight.
    public static func formula(_ f: ChemicalFormula, density: Double, gas: Bool = false,
                               data: SRIMData = .shared) -> StoppingTarget {
        StoppingTarget(name: f.label,
                       components: f.parts.map { p in
                           let mass = p.massNumber.flatMap { MassTable.ame2020.nuclide(z: p.z, a: $0) }
                               .map { $0.atomicMass / PhysicalConstants.atomicMassUnit } ?? data.element(p.z).naturalMass
                           return Component(z: p.z, stoichiometry: p.count, mass: mass, massNumber: p.massNumber)
                       },
                       density: density, isGas: gas)
    }

    /// Stoichiometries for display: atom fractions (summing to 1, as in SRIM's dictionary) become
    /// the smallest integer ratio when one exists with counts up to 100 (LiF, not Li0.5F0.5).
    var displayStoichiometries: [Double] {
        let s = components.map(\.stoichiometry)
        let total = s.reduce(0, +)
        guard abs(total - 1) < 1e-6, let lo = s.min(), lo > 0 else { return s }
        for k in 1...20 {
            let r = s.map { $0 / lo * Double(k) }
            if r.allSatisfy({ abs($0 - $0.rounded()) < 2e-3 * max(1, $0) }), r.max()! <= 100 { return r.map { $0.rounded() } }
        }
        return s
    }

    /// The composition written as a formula ("Ta₂N₃", "TiD₂"), preserving explicit isotope tags.
    /// Legacy entries recover isotope tags when their mass is >0.5 u from natural weight.
    public func formulaLabel(data: SRIMData = .shared) -> String {
        zip(components, displayStoichiometries).map { c, n in
            let a = c.isotopeMassNumber
            return ChemicalFormula.symbol(z: c.z, massNumber: a) + ChemicalFormula.subscriptCount(n)
        }.joined()
    }

    /// The composition as plain text that `ChemicalFormula` parses back ("Ta2N3", "TiD2", "[17O]").
    public func formulaText(data: SRIMData = .shared) -> String {
        zip(components, displayStoichiometries).map { c, n in
            let sym = Elements.symbol(z: c.z) ?? "?"
            var s = sym
            if let a = c.isotopeMassNumber {
                s = c.z == 1 && a == 2 ? "D" : c.z == 1 && a == 3 ? "T" : "[\(a)\(sym)]"
            }
            if abs(n - 1) > 1e-9 {
                s += n.formatted(.number.precision(.significantDigits(1...6)).grouping(.never)
                    .locale(Locale(identifier: "en_US_POSIX")))
            }
            return s
        }.joined()
    }
}
