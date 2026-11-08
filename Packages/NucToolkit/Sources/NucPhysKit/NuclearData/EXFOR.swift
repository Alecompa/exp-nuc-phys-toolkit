import Foundation

// EXFOR experimental cross sections, from the tables that the IAEA Nuclear Data Section publishes as
// IAEA-NDS/exfortables_py (the same tables behind the IAEA Nuclear Reaction Data Explorer). The app bundles an
// index of the tables at one pinned commit (Tools/build_exfor_index.py) and downloads a table from GitHub only
// when it is opened; downloaded tables are cached and never change, because the commit is fixed.

// MARK: - Dataset (one table in the index)

/// One EXFOR cross-section table: an EXFOR subentry and data pointer for one reaction.
public struct ExforDataset: Hashable, Sendable, Identifiable, Codable {
    /// Directory in exfortables_py before `/xs/`: "p/Al-27/p-g", "ion/C-12/C-12/a-L1".
    public let directory: String
    /// File name after `/xs/` (may contain "/" for isomer labels such as "Au-196-M2/T").
    public let fileName: String

    /// "p", "d", "t", "h" (³He), "a" (α) or a heavy ion such as "C-12".
    public let projectile: String
    /// "Al-27"
    public let target: String
    /// Outgoing channel without the level suffix: "g", "a", "n", "el", "inl", "x", "n+p", "he3", "f"…
    public let outgoing: String
    /// Final level of the residual (0 = ground state) when the table is for one level, nil for the total.
    public let level: Int?
    /// Reaction product named in the file name (residual nucleus for production cross sections), if any.
    public let product: String?
    public let author: String
    /// EXFOR entry (5 characters), subentry (3 digits) and data pointer.
    public let entry: String, subentry: String, pointer: String
    public let year: Int

    public var path: String { directory + "/xs/" + fileName }
    public var id: String { path }
    /// "D6305-002", with the pointer appended when it is not 0.
    public var exforID: String { "\(entry)-\(subentry)" + (pointer == "0" ? "" : "-\(pointer)") }
    /// Page of the entry in the IAEA EXFOR web retrieval.
    public var exforURL: URL { URL(string: "https://nds.iaea.org/EXFOR/\(entry)")! }

    /// Parses an index entry. Returns nil when the names do not follow the exfortables_py grammar
    /// `<target>_<code>[_<product>]_<author>-<entry>-<subentry>-<pointer>-<year>.txt`.
    public init?(directory: String, fileName: String) {
        let dir = directory.split(separator: "/").map(String.init)
        let channelDir: String
        switch dir.first {
        case "ion" where dir.count == 4:
            target = dir[1]; projectile = dir[2]; channelDir = dir[3]
        case let p? where dir.count == 3 && ExforIndex.lightProjectiles.contains(p):
            target = dir[1]; projectile = p
            guard dir[2].hasPrefix(p + "-") else { return nil }
            channelDir = String(dir[2].dropFirst(p.count + 1))
        default:
            return nil
        }
        let (base, dirLevel) = Self.splitLevel(channelDir)
        outgoing = base

        let fields = fileName.split(separator: "_", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 3 || fields.count == 4, fields[0] == target,
              fields[fields.count - 1].hasSuffix(".txt") else { return nil }
        product = fields.count == 4 ? fields[2] : nil
        level = Self.splitLevel(fields[1]).level ?? dirLevel

        let tail = fields[fields.count - 1].dropLast(4).split(separator: "-", omittingEmptySubsequences: false)
        guard tail.count >= 5, let y = Int(tail[tail.count - 1]), tail[tail.count - 4].count == 5 else { return nil }
        year = y
        pointer = String(tail[tail.count - 2])
        subentry = String(tail[tail.count - 3])
        entry = String(tail[tail.count - 4])
        author = tail[..<(tail.count - 4)].joined(separator: "-")
        self.directory = directory
        self.fileName = fileName
    }

    /// "p-g-L1" → ("p-g", 1); "a" → ("a", nil).
    static func splitLevel(_ s: String) -> (base: String, level: Int?) {
        guard let r = s.range(of: #"-L\d+$"#, options: .regularExpression),
              let l = Int(s[r].dropFirst(2)) else { return (s, nil) }
        return (String(s[..<r.lowerBound]), l)
    }

    /// The reaction channel this table belongs to.
    public var channel: ExforChannel { ExforChannel(projectile: projectile, target: target, outgoing: outgoing) }

    /// "Total", "Ground state", "Level 3".
    public var finalStateLabel: String {
        switch level {
        case nil: "Total"
        case 0?: "Ground state"
        case let l?: "Level \(l)"
        }
    }
}

// MARK: - Channel

/// A reaction channel target(projectile, outgoing) with all its tables.
public struct ExforChannel: Hashable, Sendable, Identifiable, Codable {
    public let projectile: String
    public let target: String
    public let outgoing: String
    public var id: String { "\(target)(\(projectile),\(outgoing))" }

    public init(projectile: String, target: String, outgoing: String) {
        self.projectile = projectile; self.target = target; self.outgoing = outgoing
    }

    /// Code of a nuclide as an exfortables_py projectile: "p", "d", "t", "h", "a" or "C-12".
    public static func projectileCode(_ n: Nuclide) -> String {
        switch (n.z, n.a) {
        case (1, 1): "p"
        case (1, 2): "d"
        case (1, 3): "t"
        case (2, 3): "h"
        case (2, 4): "a"
        default: ExforIndex.name(n)
        }
    }

    /// Outgoing-channel codes that correspond to a two-body reaction. Elastic scattering maps to "el" and the
    /// inelastic channel "inl"; for the light-ion tree ³He is written "he3".
    public static func outgoingCodes(_ r: Reaction) -> [String] {
        guard let e = r.ejectile.nuclide else { return ["g"] }
        if e == r.projectile && r.residual == r.target { return ["el", "inl"] }
        switch (e.z, e.a) {
        case (0, 1): return ["n"]
        case (1, 1): return ["p"]
        case (1, 2): return ["d"]
        case (1, 3): return ["t"]
        case (2, 3): return ["he3", "h"]
        case (2, 4): return ["a"]
        default: return [ExforIndex.name(e)]
        }
    }

    /// The projectile as a nuclide ("h" is ³He, "C-12" is ¹²C).
    public func projectileNuclide(in table: MassTable = .ame2020) -> Nuclide? {
        switch projectile {
        case "p", "d", "t", "a": return table.nuclide(named: projectile)
        case "h": return table.nuclide(named: "3He")
        default:
            let p = projectile.split(separator: "-")
            guard p.count == 2 else { return nil }
            return table.nuclide(named: "\(p[1])\(p[0])")
        }
    }

    /// Entrance channel projectile + target, used for lab ↔ c.m. and σ ↔ S conversions.
    public func entranceChannel(target: Nuclide, table: MassTable = .ame2020) -> ChargedChannel? {
        projectileNuclide(in: table).map { ChargedChannel(projectile: $0, target: target) }
    }

    /// Readable notation: "(p,γ)", "(α,n)", "(¹²C,α)", "(p,X)", "(p,p′)".
    public var label: String { "(\(Self.particleLabel(projectile)),\(outgoingLabel))" }

    /// "p", "α", "³He", "¹²C"
    public var projectileLabel: String { Self.particleLabel(projectile) }

    public var outgoingLabel: String {
        switch outgoing {
        case "el": Self.particleLabel(projectile)
        case "inl": Self.particleLabel(projectile) + "′"
        case "x": "X"
        case "non": "nonel."
        case "abs": "abs."
        case "tot": "total"
        default:
            outgoing.split(separator: "+").map { Self.particleLabel(String($0)) }.joined(separator: "+")
        }
    }

    /// Short description for list rows.
    public var kind: String {
        switch outgoing {
        case "g": "Radiative capture"
        case "el": "Elastic scattering"
        case "inl": "Inelastic scattering"
        case "x": "Production cross sections"
        case "non": "Nonelastic"
        case "f": "Fission"
        case "abs": "Absorption"
        default: "Reaction"
        }
    }

    /// "a" → "α", "h"/"he3" → "³He", "g" → "γ", "2n" stays, "C-12" → "¹²C".
    public static func particleLabel(_ code: String) -> String {
        switch code {
        case "g": return "γ"
        case "a": return "α"
        case "h", "he3": return "³He"
        case "p", "n", "d", "t": return code
        default:
            let parts = code.split(separator: "-")
            if parts.count == 2, let a = Int(parts[1]) { return Superscript.digits(a) + parts[0] }
            // multiplicities such as "2n", "3p", "2a"
            if let m = code.first, m.isNumber {
                return String(m) + particleLabel(String(code.dropFirst()))
            }
            return code
        }
    }
}

// MARK: - Index

/// Index of the EXFOR cross-section tables in IAEA-NDS/exfortables_py at one commit.
public struct ExforIndex: Sendable {
    /// Commit of IAEA-NDS/exfortables_py the index was built from; table URLs use it.
    public let commit: String
    /// Commit date (YYYY-MM-DD).
    public let date: String
    /// Number of tables.
    public let count: Int

    static let lightProjectiles: Set<String> = ["p", "d", "t", "h", "a"]

    private struct Group: Sendable {
        let directory: Substring
        let files: Range<Int>
    }
    private let lines: [Substring]
    private let groupsByTarget: [String: [Group]]

    public enum Failure: Error, LocalizedError {
        case missing, unreadable
        public var errorDescription: String? {
            switch self {
            case .missing: "The EXFOR index is not in the app bundle."
            case .unreadable: "The EXFOR index could not be read."
            }
        }
    }

    /// Parses the index text (see Tools/build_exfor_index.py for the format).
    public init(text: String) throws {
        let lines = text.split(whereSeparator: \.isNewline)
        guard let header = lines.first, header.hasPrefix("#exfortables_py ") else { throw Failure.unreadable }
        let h = header.split(separator: " ")
        commit = h.count > 1 ? String(h[1]) : ""
        date = h.count > 2 ? String(h[2]) : ""
        var groups: [String: [Group]] = [:]
        var i = 1, n = 0
        while i < lines.count {
            guard lines[i].hasPrefix("@") else { i += 1; continue }
            let dir = lines[i].dropFirst()
            var j = i + 1
            while j < lines.count, !lines[j].hasPrefix("@") { j += 1 }
            let parts = dir.split(separator: "/")
            if parts.count >= 3 {
                groups[String(parts[1]), default: []].append(Group(directory: dir, files: (i + 1)..<j))
                n += j - i - 1
            }
            i = j
        }
        self.lines = lines
        self.groupsByTarget = groups
        self.count = n
    }

    /// Reads the raw-DEFLATE file written by Tools/build_exfor_index.py.
    public init(compressed data: Data) throws {
        guard let raw = try? (data as NSData).decompressed(using: .zlib) as Data else { throw Failure.unreadable }
        try self.init(text: String(decoding: raw, as: UTF8.self))
    }

    /// The index bundled with the app (empty if the resource is missing, which the tests catch).
    public static let bundled: ExforIndex = {
        if let url = Bundle.module.url(forResource: "exfor_index", withExtension: "deflate"),
           let data = try? Data(contentsOf: url), let index = try? ExforIndex(compressed: data) {
            return index
        }
        return try! ExforIndex(text: "#exfortables_py unavailable -\n")
    }()

    /// exfortables_py name of a nuclide: "Al-27", "He-4", "H-1".
    public static func name(_ n: Nuclide) -> String { "\(n.symbol)-\(n.a)" }

    /// All tables with `target` as the target nucleus.
    public func datasets(target: Nuclide) -> [ExforDataset] {
        (groupsByTarget[Self.name(target)] ?? []).flatMap { g in
            let dir = String(g.directory)
            return g.files.compactMap { ExforDataset(directory: dir, fileName: String(lines[$0])) }
        }
    }

    /// Every entry of the index parsed as a dataset (nil where a name does not parse); for validation.
    func allDatasets() -> [ExforDataset?] {
        groupsByTarget.values.flatMap { $0 }.flatMap { g in
            let dir = String(g.directory)
            return g.files.map { ExforDataset(directory: dir, fileName: String(lines[$0])) }
        }
    }

    /// Reaction channels measured on `target`, with their tables, sorted light projectiles first and by size.
    public func channels(target: Nuclide) -> [(channel: ExforChannel, datasets: [ExforDataset])] {
        let byChannel = Dictionary(grouping: datasets(target: target), by: \.channel)
        let order = ["p": 0, "a": 1, "d": 2, "h": 3, "t": 4]
        return byChannel.map { ($0.key, $0.value.sorted(by: Self.newestFirst)) }.sorted {
            let a = order[$0.channel.projectile] ?? 9, b = order[$1.channel.projectile] ?? 9
            if a != b { return a < b }
            if $0.channel.projectile != $1.channel.projectile { return $0.channel.projectile < $1.channel.projectile }
            return $0.datasets.count > $1.datasets.count
        }
    }

    /// Tables for a two-body reaction (all final states).
    public func datasets(for reaction: Reaction) -> [ExforDataset] {
        let p = ExforChannel.projectileCode(reaction.projectile)
        let out = Set(ExforChannel.outgoingCodes(reaction))
        return datasets(target: reaction.target)
            .filter { $0.projectile == p && out.contains($0.outgoing) }
            .sorted(by: Self.newestFirst)
    }

    /// Tables of one channel.
    public func datasets(for channel: ExforChannel, target: Nuclide) -> [ExforDataset] {
        datasets(target: target).filter { $0.channel == channel }.sorted(by: Self.newestFirst)
    }

    static func newestFirst(_ a: ExforDataset, _ b: ExforDataset) -> Bool {
        a.year != b.year ? a.year > b.year : a.path < b.path
    }
}

// MARK: - Table

/// A downloaded exfortables_py table, in keV and barn (or keV b for S factors).
public struct ExforTable: Hashable, Sendable, Codable {
    public enum Quantity: String, Hashable, Sendable, Codable, CaseIterable {
        case crossSection, sFactor
    }
    public enum Frame: String, Hashable, Sendable, Codable, CaseIterable {
        case lab, cm
    }
    /// EXFOR data heading: an ordinary value, an upper limit (DATA-MAX) or an approximate value (DATA-APRX).
    public enum Qualifier: String, Hashable, Sendable, Codable {
        case value, upperLimit, approximate, other
    }

    public struct Point: Hashable, Sendable, Codable {
        /// keV, in `frame`
        public var energy: Double
        public var energyUncertainty: Double?
        /// barn for a cross section, keV b for an S factor
        public var value: Double
        public var uncertainty: Double?
    }

    public let quantity: Quantity
    public let frame: Frame
    public let qualifier: Qualifier
    /// Points with a numerical value (rows with NAN are dropped).
    public let points: [Point]
    /// Number of rows without a value (NAN in the table).
    public let missingValues: Int

    /// Rows at zero energy. EXFOR stores extrapolated S(0) values this way; they cannot be converted to σ
    /// or plotted on a logarithmic energy axis, and `points(as:frame:channel:)` leaves them out.
    public var zeroEnergyPoints: [Point] { points.filter { $0.energy <= 0 } }

    public let title: String
    /// EXFOR reaction code, e.g. "(13-AL-27(P,G)14-SI-28,PAR,SIG)".
    public let reactionCode: String
    public let residual: String
    /// Excitation energy of the final level, keV, when the table is for one level.
    public let levelEnergy: Double?
    public let firstAuthor: String
    public let year: String
    /// EXFOR reference code, e.g. "(J,PR/C,95,014614,2017)".
    public let reference: String
    public let institute: String
    public let facility: String
    public let entryID: String

    public enum ParseError: Error, Equatable, LocalizedError {
        case noColumns, unsupportedUnit(String), noData
        public var errorDescription: String? {
            switch self {
            case .noColumns: "The table has no column header."
            case .unsupportedUnit(let u): "Unit “\(u)” is not supported."
            case .noData: "The table has no data points."
            }
        }
    }

    /// Parses an exfortables_py text table.
    public static func parse(_ text: String) throws -> ExforTable {
        var meta: [String: String] = [:]
        var columns: [String] = []
        var points: [Point] = []
        var missing = 0
        var eScale = 1.0, eUncScale = 1.0, yScale = 1.0, yUncScale = 1.0
        var quantity = Quantity.crossSection, frame = Frame.lab, qualifier = Qualifier.value

        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if body.hasPrefix("E_in_") || body.hasPrefix("dE_in_") {
                    columns = body.split(separator: " ").map(String.init)
                    guard columns.count >= 4 else { throw ParseError.noColumns }
                    frame = columns[0].hasPrefix("E_in_cm") ? .cm : .lab
                    eScale = try energyUnit(unit(of: columns[0]))
                    eUncScale = try energyUnit(unit(of: columns[1]))
                    (quantity, yScale) = try dataUnit(unit(of: columns[2]))
                    yUncScale = try dataUnit(unit(of: columns[3])).1
                    let head = columns[2].prefix { $0 != "(" }
                    qualifier = head == "data" ? .value : head == "data_max" ? .upperLimit
                        : head == "data_aprx" ? .approximate : .other
                } else if let colon = body.firstIndex(of: ":") {
                    let key = body[..<colon].trimmingCharacters(in: .whitespaces)
                    let value = body[body.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    // The file has two "Nuclide:" keys (target, then residual); keep both.
                    if key == "Nuclide", meta["Nuclide"] != nil { meta["Residual nuclide"] = value } else { meta[key] = value }
                }
                continue
            }
            guard !columns.isEmpty else { continue }
            let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard f.count >= 4, let e = Double(f[0]) else { continue }
            guard let y = Double(f[2]), y.isFinite else { missing += 1; continue }
            let de = Double(f[1]).flatMap { $0.isFinite && $0 > 0 ? $0 * eUncScale : nil }
            let dy = Double(f[3]).flatMap { $0.isFinite && $0 > 0 ? $0 * yUncScale : nil }
            points.append(Point(energy: e * eScale, energyUncertainty: de, value: y * yScale, uncertainty: dy))
        }
        guard !columns.isEmpty else { throw ParseError.noColumns }
        guard !points.isEmpty else { throw ParseError.noData }

        let level = meta["Level energy"].flatMap { s -> Double? in
            let p = s.split(separator: " ")
            guard let v = p.first.flatMap({ Double($0) }) else { return nil }
            return v * ((try? energyUnit(p.count > 1 ? String(p[1]) : "MeV")) ?? 1000)
        }
        return ExforTable(quantity: quantity, frame: frame, qualifier: qualifier,
                          points: points.sorted { $0.energy < $1.energy }, missingValues: missing,
                          title: meta["Title"] ?? "", reactionCode: meta["Reaction code"] ?? "",
                          residual: meta["Residual nuclide"] ?? "", levelEnergy: level,
                          firstAuthor: meta["First author"] ?? "", year: meta["Year"] ?? "",
                          reference: meta["Reference"] ?? "", institute: meta["Institute"] ?? "",
                          facility: meta["Facility"] ?? "", entryID: meta["Entry id"] ?? "")
    }

    /// "E_in_lab(MeV)" → "MeV"
    private static func unit(of column: String) -> String {
        guard let o = column.firstIndex(of: "("), let c = column.lastIndex(of: ")"), o < c else { return "" }
        return String(column[column.index(after: o)..<c])
    }

    /// keV per unit.
    static func energyUnit(_ u: String) throws -> Double {
        switch u.uppercased() {
        case "EV": 1e-3
        case "KEV": 1
        case "MEV": 1e3
        case "GEV": 1e6
        default: throw ParseError.unsupportedUnit(u)
        }
    }

    /// barn per unit for σ; for "σ-unit*energy-unit" an S factor in keV b per unit.
    static func dataUnit(_ u: String) throws -> (Quantity, Double) {
        let parts = u.uppercased().split(separator: "*").map(String.init)
        func barn(_ s: String) throws -> Double {
            switch s {
            case "B": 1
            case "MB": 1e-3
            case "MUB", "MICRO-B", "UB": 1e-6
            case "NB": 1e-9
            case "PB": 1e-12
            default: throw ParseError.unsupportedUnit(u)
            }
        }
        switch parts.count {
        case 1: return (.crossSection, try barn(parts[0]))
        case 2: return (.sFactor, try barn(parts[0]) * energyUnit(parts[1]))
        default: throw ParseError.unsupportedUnit(u)
        }
    }

    /// The points as σ or S at laboratory or centre-of-mass energies, converted with the entrance channel
    /// (non-relativistic, target at rest; S = σ E exp(2πη) at the c.m. energy). The relative uncertainty of
    /// the value is kept; the energy uncertainty is not propagated into the value.
    public func points(as q: Quantity, frame f: Frame, channel c: ChargedChannel) -> [Point] {
        points.compactMap { p in
            let ecm = frame == .cm ? p.energy : c.cmEnergy(lab: p.energy)
            guard ecm > 0 else { return nil }
            let eOut = f == .cm ? ecm : c.labEnergy(cm: ecm)
            let eFactor = eOut / p.energy
            var factor = 1.0
            if q != quantity {
                let sOverSigma = ecm * exp(2 * .pi * c.sommerfeld(ecm))
                factor = q == .sFactor ? sOverSigma : 1 / sOverSigma
            }
            let v = p.value * factor
            guard v.isFinite else { return nil }
            return Point(energy: eOut, energyUncertainty: p.energyUncertainty.map { $0 * eFactor },
                         value: v, uncertainty: p.uncertainty.map { $0 * abs(factor) })
        }
    }
}

// MARK: - Client

/// Downloads exfortables_py tables from GitHub at the index's commit and caches them on disk.
public actor ExforClient {
    public static let shared = ExforClient()

    public enum Failure: Error, LocalizedError {
        case http(Int), offline
        public var errorDescription: String? {
            switch self {
            case .http(404): "The table is not on GitHub at this commit (HTTP 404)."
            case .http(let c): "GitHub answered with HTTP \(c)."
            case .offline: "Not connected to the internet, and this table is not cached."
            }
        }
    }

    private let session: URLSession
    private let cacheDirectory: URL
    public let commit: String

    public init(session: URLSession = .shared, cacheDirectory: URL? = nil, commit: String = ExforIndex.bundled.commit) {
        self.session = session
        self.commit = commit
        self.cacheDirectory = (cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EXFOR", isDirectory: true)).appendingPathComponent(commit, isDirectory: true)
    }

    /// raw.githubusercontent.com URL of a table at the pinned commit.
    public nonisolated static func url(for d: ExforDataset, commit: String) -> URL {
        let path = d.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["+", "?", "#"])) ?? d.path
        return URL(string: "https://raw.githubusercontent.com/IAEA-NDS/exfortables_py/\(commit)/\(path)")!
    }

    private func cacheURL(_ d: ExforDataset) -> URL { cacheDirectory.appendingPathComponent(d.path) }

    /// The table's text from the cache, if downloaded before.
    public func cachedText(_ d: ExforDataset) -> String? {
        (try? Data(contentsOf: cacheURL(d))).map { String(decoding: $0, as: UTF8.self) }
    }

    public func isCached(_ d: ExforDataset) -> Bool {
        FileManager.default.fileExists(atPath: cacheURL(d).path)
    }

    /// The table's text, from the cache or downloaded (and then cached).
    public func text(_ d: ExforDataset) async throws -> String {
        if let t = cachedText(d) { return t }
        var req = URLRequest(url: Self.url(for: d, commit: commit))
        req.setValue("Gamow-toolkit/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let e as URLError where e.code == .notConnectedToInternet {
            throw Failure.offline
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw Failure.http(http.statusCode) }
        let url = cacheURL(d)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
        return String(decoding: data, as: UTF8.self)
    }

    /// Downloads (or reads from the cache) and parses a table.
    public func table(_ d: ExforDataset) async throws -> ExforTable {
        try ExforTable.parse(try await text(d))
    }

    /// Size of the cache in bytes and the number of tables in it.
    public func cacheUsage() -> (bytes: Int, tables: Int) {
        let root = cacheDirectory.deletingLastPathComponent()
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return (0, 0) }
        var bytes = 0, n = 0
        for case let u as URL in e {
            if let s = try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize { bytes += s; n += 1 }
        }
        return (bytes, n)
    }

    public func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory.deletingLastPathComponent())
    }
}
