import AppIntents
import NucPhysKit
import SwiftUI
import WidgetKit

// "Source activity" widget: the activity today of one calibration source, configured on the widget
// itself (nuclide, certificate activity, reference date), so it needs no shared container with the app.

struct SourceOptions: DynamicOptionsProvider {
    func results() async throws -> [String] { CalibrationSources.all.map(\.id) }
    func defaultResult() async -> String? { "137Cs" }
}

struct SourceWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Calibration Source"
    static let description = IntentDescription("Shows the activity today of one of your sources.")

    @Parameter(title: "Nuclide", optionsProvider: SourceOptions())
    var nuclide: String?

    @Parameter(title: "Name", description: "Label shown on the widget, e.g. the certificate number")
    var name: String?

    @Parameter(title: "Certificate activity (kBq)", default: 10)
    var activity: Double

    @Parameter(title: "Reference date")
    var referenceDate: Date?
}

struct SourceEntry: TimelineEntry {
    let date: Date
    let label: String
    let name: String
    let activity: Double?          // Bq
    let fraction: Double?
    let halfLife: String
}

struct SourceProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SourceEntry {
        SourceEntry(date: .now, label: "¹³⁷Cs", name: "Reference source", activity: 8_840, fraction: 0.884, halfLife: "30.0 y")
    }

    func snapshot(for configuration: SourceWidgetIntent, in context: Context) async -> SourceEntry {
        entry(configuration, at: .now)
    }

    func timeline(for configuration: SourceWidgetIntent, in context: Context) async -> Timeline<SourceEntry> {
        // One entry per hour for a day: short-lived sources (e.g. 18F) visibly change.
        let start = Calendar.current.dateInterval(of: .hour, for: .now)?.start ?? .now
        let entries = (0..<24).map { entry(configuration, at: start.addingTimeInterval(Double($0) * 3600)) }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func entry(_ c: SourceWidgetIntent, at date: Date) -> SourceEntry {
        let nuclide = c.nuclide ?? "137Cs"
        let cert = SourceCertificate(nuclide: nuclide, name: c.name ?? "", activity: c.activity * 1000,
                                     referenceDate: c.referenceDate ?? Calendar.current.date(byAdding: .year, value: -1, to: .now)!)
        let state = cert.state
        let now = cert.activity(at: date)
        return SourceEntry(date: date, label: state?.label ?? nuclide, name: c.name ?? "",
                           activity: now?.activity, fraction: now.map { $0.activity / cert.activity },
                           halfLife: halfLifeText(state?.halfLife))
    }

    private func halfLifeText(_ s: Double?) -> String {
        guard let s, s.isFinite else { return "—" }
        let u = HalfLifeFormat.unit(for: s)
        return "\((s / u.scale).formatted(.number.precision(.significantDigits(3))))\u{2009}\(u.label)"
    }
}

struct SourceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SourceEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.label).font(.headline)
                Text(activityText).font(.body.monospacedDigit())
                Text("T½ \(entry.halfLife)").font(.caption)
            }
        case .accessoryInline:
            Text("\(entry.label) \(activityText)")
        default:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "rays").foregroundStyle(.orange)
                    Text(entry.label).font(.headline)
                    Spacer()
                }
                if !entry.name.isEmpty {
                    Text(entry.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(activityText)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                if let f = entry.fraction {
                    ProgressView(value: min(1, max(0, f))).tint(.orange)
                    Text("\((100 * f).formatted(.number.precision(.fractionLength(1)))) % · T½ \(entry.halfLife)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var activityText: String {
        guard let a = entry.activity else { return "—" }
        let (scale, unit): (Double, String) = a < 1e3 ? (1, "Bq") : a < 1e6 ? (1e3, "kBq") : a < 1e9 ? (1e6, "MBq") : (1e9, "GBq")
        return "\((a / scale).formatted(.number.precision(.significantDigits(4)))) \(unit)"
    }
}

struct SourceWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SourceActivity", intent: SourceWidgetIntent.self, provider: SourceProvider()) { entry in
            SourceWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Source Activity")
        .description("The activity today of a calibration source. Edit the widget to enter its certificate.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct GamowWidgets: WidgetBundle {
    var body: some Widget { SourceWidget() }
}
