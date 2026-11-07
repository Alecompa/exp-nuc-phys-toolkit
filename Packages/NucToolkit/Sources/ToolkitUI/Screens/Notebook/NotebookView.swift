import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Saved calculations: every tool's "Save to Notebook" button lands here.
struct NotebookView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \NotebookEntry.date, order: .reverse) private var entries: [NotebookEntry]
    @State private var search = ""
    @State private var confirmDeleteAll = false

    private var filtered: [NotebookEntry] {
        guard !search.isEmpty else { return entries }
        return entries.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.subtitle.localizedCaseInsensitiveContains(search)
                || $0.note.localizedCaseInsensitiveContains(search) || ($0.tool?.title.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("No saved calculations", systemImage: "book.pages")
                    } description: {
                        Text("Tap \(Image(systemName: "book.pages")) in any tool to save its inputs and results here, with a note.")
                    }
                } else {
                    List {
                        ForEach(groupedByDay, id: \.day) { group in
                            Section(group.day.formatted(date: .complete, time: .omitted)) {
                                ForEach(group.entries) { e in
                                    NavigationLink { NotebookDetailView(entry: e) } label: { NotebookRow(entry: e) }
                                }
                                .onDelete { idx in
                                    withAnimation { for i in idx { context.delete(group.entries[i]) } }
                                    try? context.save()
                                }
                            }
                        }
                    }
                    .groupedList()
                    .overlay {
                        if filtered.isEmpty { ContentUnavailableView.search(text: search) }
                    }
                }
            }
            .navigationTitle("Notebook")
            .searchable(text: $search, prompt: "Search calculations")
            .toolbar {
                if !entries.isEmpty {
                    ToolbarItem(placement: .trailingBar) {
                        Menu {
                            ShareLink(item: CSVFile(name: "gamow_notebook", text: NotebookEntry.csv(filtered)),
                                      preview: SharePreview("Notebook (\(filtered.count) entries)", image: Image(systemName: "tablecells"))) {
                                Label("Export \(search.isEmpty ? "All" : "Results") as CSV", systemImage: "tablecells")
                            }
                            ShareLink(item: filtered.map(\.text).joined(separator: "\n———\n\n")) {
                                Label("Share as Text", systemImage: "doc.plaintext")
                            }
                            Divider()
                            Button("Delete All…", systemImage: "trash", role: .destructive) { confirmDeleteAll = true }
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .confirmationDialog("Delete all \(entries.count) saved calculations?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) {
                    withAnimation { for e in entries { context.delete(e) } }
                    try? context.save()
                }
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    private var groupedByDay: [(day: Date, entries: [NotebookEntry])] {
        let cal = Calendar.current
        var order: [Date] = [], groups: [Date: [NotebookEntry]] = [:]
        for e in filtered {
            let d = cal.startOfDay(for: e.date)
            if groups[d] == nil { order.append(d) }
            groups[d, default: []].append(e)
        }
        return order.map { ($0, groups[$0]!) }
    }
}

private struct NotebookRow: View {
    let entry: NotebookEntry
    var body: some View {
        HStack(spacing: 12) {
            ToolGlyph(tool: entry.tool, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.body.weight(.medium)).lineLimit(1)
                Text([entry.tool?.title, entry.subtitle.isEmpty ? nil : entry.subtitle].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if !entry.note.isEmpty {
                    Text(entry.note).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Small rounded tile with the tool's symbol and tint.
struct ToolGlyph: View {
    let tool: Tool?
    var size: CGFloat = 36
    var body: some View {
        Image(systemName: tool?.symbol ?? "doc.text")
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background((tool?.tint ?? .gray).gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct NotebookDetailView: View {
    @Bindable var entry: NotebookEntry
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @FocusState private var editingNote: Bool

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ToolGlyph(tool: entry.tool, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title).font(.title3.weight(.semibold))
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline).foregroundStyle(.secondary)
                        if !entry.subtitle.isEmpty {
                            Text(entry.subtitle).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            ForEach(entry.sections, id: \.title) { sec in
                Section(sec.title) {
                    ForEach(sec.items) { i in
                        ValueRow(label: i.label, value: i.value, unit: i.unit.isEmpty ? nil : i.unit)
                    }
                }
            }
            Section("Note") {
                TextField("Add a note (run number, target, conditions…)", text: $entry.note, axis: .vertical)
                    .lineLimit(3...12)
                    .focused($editingNote)
            }
        }
        .groupedList()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(entry.tool?.title ?? "Calculation")
        .inlineTitle()
        .onDisappear { try? context.save() }
        .toolbar {
            ToolbarItem(placement: .trailingBar) {
                Menu {
                    ShareLink(item: entry.text) { Label("Share as Text", systemImage: "doc.plaintext") }
                    ShareLink(item: CSVFile(name: entry.fileName, text: NotebookEntry.csv([entry])),
                              preview: SharePreview(entry.title, image: Image(systemName: "tablecells"))) {
                        Label("Export CSV", systemImage: "tablecells")
                    }
                    if let pdf = pdfFile() {
                        ShareLink(item: pdf, preview: SharePreview(entry.title, image: Image(systemName: "doc.richtext"))) {
                            Label("Export PDF", systemImage: "doc.richtext")
                        }
                    }
                    Button("Copy as Text", systemImage: "doc.on.doc") { Pasteboard.copy(entry.text) }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            if editingNote {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { editingNote = false; try? context.save() }
                }
            }
        }
    }

    /// One A4 page rendered from the entry.
    @MainActor private func pdfFile() -> PDFFile? {
        let renderer = ImageRenderer(content: NotebookPrintView(entry: entry).frame(width: 595))
        renderer.scale = displayScale
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(entry.fileName + ".pdf")
        var ok = false
        renderer.render { size, draw in
            var box = CGRect(x: 0, y: 0, width: 595, height: max(842, size.height))
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil)
            ctx.translateBy(x: 0, y: box.height - size.height)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            ok = true
        }
        return ok ? PDFFile(url: url) : nil
    }
}

/// The printable layout used for PDF export.
private struct NotebookPrintView: View {
    let entry: NotebookEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.title).font(.system(size: 20, weight: .bold))
                Spacer()
                Text("Gamow").font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
            }
            Text("\(entry.tool?.title ?? "") · \(entry.date.formatted(date: .long, time: .shortened))\(entry.subtitle.isEmpty ? "" : " · " + entry.subtitle)")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            ForEach(entry.sections, id: \.title) { sec in
                VStack(alignment: .leading, spacing: 4) {
                    Text(sec.title.uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(sec.items) { i in
                        HStack {
                            Text(i.label)
                            Spacer()
                            Text(i.value + (i.unit.isEmpty ? "" : " " + i.unit)).monospacedDigit()
                        }
                        .font(.system(size: 11))
                        Divider()
                    }
                }
            }
            if !entry.note.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NOTE").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    Text(entry.note).font(.system(size: 11))
                }
            }
        }
        .padding(40)
        .foregroundStyle(.black)
        .background(.white)
        .environment(\.colorScheme, .light)
    }
}

extension NotebookEntry {
    var fileName: String {
        let base = "\(tool?.rawValue ?? "calc")_\(date.formatted(.iso8601.year().month().day()))"
        return base.replacingOccurrences(of: "/", with: "-")
    }

    static func csv(_ entries: [NotebookEntry]) -> String {
        ([csvHeader] + entries.flatMap(\.csvRows)).joined(separator: "\n") + "\n"
    }
}

/// A CSV text shared as a file.
struct CSVFile: Transferable {
    let name: String
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { Data($0.text.utf8) }
            .suggestedFileName { "\($0.name).csv" }
    }
}

/// A rendered PDF on disk, shared as a file.
struct PDFFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { SentTransferredFile($0.url) }
    }
}
