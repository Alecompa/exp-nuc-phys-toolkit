import Foundation

/// Expected areas in a region; these are model components, not a background-subtracted measurement.
public struct SpectrumRegion: Sendable {
    public var photopeak: Double = 0
    public var compton: Double = 0
    public var background: Double = 0
    public var total: Double { photopeak + compton + background }

    /// Partially intersected channels contribute in proportion to their overlap with the ROI.
    /// This assumes uniform counts within each channel; it does not re-integrate the response model.
    public static func integrate(_ bins: [SpectrumBin], binWidth: Double, lower: Double, upper: Double) -> SpectrumRegion {
        var result = SpectrumRegion()
        guard binWidth.isFinite, binWidth > 0, lower.isFinite, upper.isFinite, upper > lower else { return result }
        for bin in bins {
            let overlap = max(0, min(upper, bin.energy + binWidth / 2) - max(lower, bin.energy - binWidth / 2))
            let fraction = min(1, overlap / binWidth)
            result.photopeak += fraction * bin.photopeak
            result.compton += fraction * bin.compton
            result.background += fraction * bin.background
        }
        return result
    }
}

/// Display-only reduction: retain extrema in energy buckets so narrow peaks do not disappear.
/// Analysis and CSV export must always use the original channels.
public enum SpectrumPlotSampling {
    public static func envelope(_ bins: [SpectrumBin], budget: Int = 1200) -> [SpectrumBin] {
        guard budget >= 8, bins.count > budget else { return bins }
        let buckets = max(1, budget / 8)
        let size = Int(ceil(Double(bins.count) / Double(buckets)))
        var indices = Set<Int>()
        for start in stride(from: 0, to: bins.count, by: size) {
            let end = min(bins.count, start + size)
            indices.insert(start); indices.insert(end - 1)
            for key in [\SpectrumBin.total, \SpectrumBin.photopeak, \SpectrumBin.compton] {
                var low = start, high = start
                for i in start..<end {
                    if bins[i][keyPath: key] < bins[low][keyPath: key] { low = i }
                    if bins[i][keyPath: key] > bins[high][keyPath: key] { high = i }
                }
                indices.insert(low); indices.insert(high)
            }
        }
        return indices.sorted().map { bins[$0] }
    }
}
