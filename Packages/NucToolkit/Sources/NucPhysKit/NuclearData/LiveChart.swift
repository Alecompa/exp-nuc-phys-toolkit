import Foundation

/// An excited level from ENSDF (IAEA LiveChart).
public struct Level: Hashable, Sendable, Identifiable, Codable {
    public let index: Int
    /// keV
    public let energy: Double
    public let energyUncertainty: Double?
    public let spinParity: String
    /// Half-life as printed, e.g. "475 fs", "STABLE".
    public let halfLife: String
    public let halfLifeSeconds: Double?
    public var id: Int { index }
}

/// A γ transition between ENSDF levels.
public struct GammaTransition: Hashable, Sendable, Identifiable, Codable {
    public let initialLevel: Double
    public let finalLevel: Double
    public let initialSpinParity: String
    public let finalSpinParity: String
    /// keV
    public let energy: Double
    public let energyUncertainty: Double?
    /// Relative intensity within the decay of the initial level (strongest = 100).
    public let relativeIntensity: Double?
    public let multipolarity: String
    public var id: String { "\(initialLevel)-\(finalLevel)-\(energy)" }
}

/// ENSDF data for one nuclide.
public struct LevelScheme: Hashable, Sendable, Codable {
    public let levels: [Level]
    public let gammas: [GammaTransition]
    /// ENSDF evaluation reference (authors, cut-off date).
    public let reference: String
    public let retrieved: Date
}

/// Client of the IAEA LiveChart of Nuclides data API (https://nds.iaea.org/relnsd/v1/data), with an on-disk cache.
public actor LiveChartClient {
    public static let shared = LiveChartClient()

    public enum Failure: Error, LocalizedError {
        case http(Int), empty, offline
        public var errorDescription: String? {
            switch self {
            case .http(let c): "The IAEA server answered with HTTP \(c)."
            case .empty: "No ENSDF levels for this nuclide."
            case .offline: "Not connected to the internet, and nothing is cached."
            }
        }
    }

    private let session: URLSession
    private let cacheDirectory: URL
    /// Cached data older than this is refreshed when online.
    public var maxAge: TimeInterval = 30 * 86400

    public init(session: URLSession = .shared, cacheDirectory: URL? = nil) {
        self.session = session
        self.cacheDirectory = cacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiveChart", isDirectory: true)
    }

    /// API name: lower-case mass number + symbol ("28si").
    static func apiName(z: Int, a: Int) -> String { "\(a)\((Elements.symbol(z: z) ?? "").lowercased())" }

    public func cached(z: Int, a: Int) -> LevelScheme? {
        guard let data = try? Data(contentsOf: cacheURL(z: z, a: a)) else { return nil }
        return try? JSONDecoder().decode(LevelScheme.self, from: data)
    }

    /// Levels and γ rays, from the cache when fresh, otherwise from the network (falling back to stale cache).
    public func levelScheme(z: Int, a: Int, forceRefresh: Bool = false) async throws -> LevelScheme {
        let cache = cached(z: z, a: a)
        if let cache, !forceRefresh, Date().timeIntervalSince(cache.retrieved) < maxAge { return cache }
        do {
            let name = Self.apiName(z: z, a: a)
            async let lv = fetch("fields=levels&nuclides=\(name)")
            async let gm = fetch("fields=gammas&nuclides=\(name)")
            let scheme = try Self.parse(levels: try await lv, gammas: try await gm)
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try? JSONEncoder().encode(scheme).write(to: cacheURL(z: z, a: a))
            return scheme
        } catch {
            if let cache { return cache }
            if (error as? URLError)?.code == .notConnectedToInternet { throw Failure.offline }
            throw error
        }
    }

    private func cacheURL(z: Int, a: Int) -> URL {
        cacheDirectory.appendingPathComponent("\(Self.apiName(z: z, a: a)).json")
    }

    private func fetch(_ query: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://nds.iaea.org/relnsd/v1/data?\(query)")!)
        req.setValue("Gamow-toolkit/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw Failure.http(http.statusCode) }
        return String(decoding: data, as: UTF8.self)
    }

    /// Parses the API's CSV answers.
    public static func parse(levels: String, gammas: String, retrieved: Date = Date()) throws -> LevelScheme {
        let lv = table(levels), gm = table(gammas)
        var reference = ""
        let levelList: [Level] = lv.compactMap { r in
            guard let e = Double(r["energy"] ?? "") else { return nil }
            if reference.isEmpty, let au = r["ENSDF_authors"], let cut = r["ENSDF_publication_cut-off"] {
                reference = "\(au), ENSDF cut-off \(cut)"
            }
            let hl = [r["operator_hl"], r["half_life"], r["unit_hl"]].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            return Level(index: Int(r["idx"] ?? "") ?? 0, energy: e, energyUncertainty: Double(r["unc_e"] ?? ""),
                         spinParity: r["jp"] ?? "", halfLife: hl == "STABLE" ? "stable" : hl,
                         halfLifeSeconds: Double(r["half_life_sec"] ?? ""))
        }
        let gammaList: [GammaTransition] = gm.compactMap { r in
            guard let e = Double(r["energy"] ?? ""), let ei = Double(r["start_level_energy"] ?? "") else { return nil }
            return GammaTransition(initialLevel: ei, finalLevel: Double(r["end_level_energy"] ?? "") ?? 0,
                                   initialSpinParity: r["start_level_jp"] ?? "", finalSpinParity: r["end_level_jp"] ?? "",
                                   energy: e, energyUncertainty: Double(r["unc_en"] ?? ""),
                                   relativeIntensity: Double(r["relative_intensity"] ?? ""), multipolarity: r["multipolarity"] ?? "")
        }
        guard !levelList.isEmpty else { throw Failure.empty }
        return LevelScheme(levels: levelList.sorted { $0.energy < $1.energy }, gammas: gammaList,
                           reference: reference, retrieved: retrieved)
    }

    /// CSV → rows keyed by header (later duplicate headers do not overwrite earlier ones).
    static func table(_ csv: String) -> [[String: String]] {
        let lines = csv.split(whereSeparator: \.isNewline).map(String.init)
        guard let header = lines.first.map(Nubase.fields), header.count > 1 else { return [] }
        return lines.dropFirst().map { line in
            var row: [String: String] = [:]
            for (k, v) in zip(header, Nubase.fields(line)) where row[k] == nil { row[k] = v }
            return row
        }
    }
}
