import Foundation
import SwiftData
import SwiftUI

/// One value in a saved calculation.
struct NotebookItem: Codable, Hashable, Identifiable {
    var section: String
    var label: String
    var value: String
    var unit: String
    var id: String { section + "|" + label }
}

/// A saved calculation: the inputs and results of a tool at one moment, plus the user's note.
@Model
final class NotebookEntry {
    var date: Date = Date()
    var toolID: String = ""
    var title: String = ""
    var subtitle: String = ""
    var note: String = ""
    var itemsData: Data = Data()

    init(date: Date = .now, tool: Tool, title: String, subtitle: String, items: [NotebookItem], note: String = "") {
        self.date = date
        self.toolID = tool.rawValue
        self.title = title
        self.subtitle = subtitle
        self.note = note
        self.itemsData = (try? JSONEncoder().encode(items)) ?? Data()
    }

    var tool: Tool? { Tool(rawValue: toolID) }

    var items: [NotebookItem] {
        get { (try? JSONDecoder().decode([NotebookItem].self, from: itemsData)) ?? [] }
        set { itemsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    /// Items grouped by section, in their saved order.
    var sections: [(title: String, items: [NotebookItem])] {
        var order: [String] = [], groups: [String: [NotebookItem]] = [:]
        for i in items {
            if groups[i.section] == nil { order.append(i.section) }
            groups[i.section, default: []].append(i)
        }
        return order.map { ($0, groups[$0]!) }
    }

    /// Plain-text rendering for sharing.
    var text: String {
        var s = "\(title)\n\(subtitle)\n\(date.formatted(date: .abbreviated, time: .shortened))\n"
        for sec in sections {
            s += "\n\(sec.title)\n"
            for i in sec.items { s += "  \(i.label): \(i.value)\(i.unit.isEmpty ? "" : " " + i.unit)\n" }
        }
        if !note.isEmpty { s += "\nNote\n\(note)\n" }
        return s
    }

    /// CSV rows: date, tool, title, section, quantity, value, unit.
    var csvRows: [String] {
        let d = date.ISO8601Format()
        return items.map { i in
            [d, tool?.title ?? toolID, title, i.section, i.label, i.value, i.unit].map(Self.csvField).joined(separator: ",")
        }
    }

    static let csvHeader = "date,tool,title,section,quantity,value,unit"

    static func csvField(_ s: String) -> String {
        // Typographic minus and ×10ⁿ back to plain ASCII for spreadsheets.
        var t = s.replacingOccurrences(of: "\u{2212}", with: "-")
        if let r = t.range(of: "×10") {
            let exp = t[r.upperBound...].map { c -> Character in
                let map: [Character: Character] = ["⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5",
                                                   "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-"]
                return map[c] ?? c
            }
            t = String(t[..<r.lowerBound]) + "e" + String(exp)
        }
        return t.contains(",") || t.contains("\"") || t.contains("\n") || t.contains("\r") ? "\"" + t.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : t
    }
}

/// What a tool hands to the notebook.
struct NotebookSnapshot {
    let tool: Tool
    let title: String
    var subtitle: String = ""
    var items: [NotebookItem] = []

    init(tool: Tool, title: String, subtitle: String = "") {
        self.tool = tool; self.title = title; self.subtitle = subtitle
    }

    mutating func add(_ section: String, _ label: String, _ value: String, _ unit: String = "") {
        items.append(NotebookItem(section: section, label: label, value: value, unit: unit))
    }
}

/// Toolbar button that saves the current tool state to the notebook.
struct SaveToNotebookButton: View {
    @Environment(\.modelContext) private var context
    let snapshot: () -> NotebookSnapshot?
    @State private var saved = 0
    @State private var showsCheck = false
    @State private var saveError: String?

    var body: some View {
        Button {
            guard let s = snapshot() else { return }
            let entry = NotebookEntry(tool: s.tool, title: s.title, subtitle: s.subtitle, items: s.items)
            context.insert(entry)
            do { try context.save() }
            catch {
                context.delete(entry)
                saveError = error.localizedDescription
                return
            }
            saved += 1
            withAnimation(.smooth) { showsCheck = true }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.smooth) { showsCheck = false }
            }
        } label: {
            Label("Save to Notebook", systemImage: showsCheck ? "checkmark" : "book.pages")
                .contentTransition(.symbolEffect(.replace))
        }
        .sensoryFeedback(.success, trigger: saved)
        .alert("Could not save calculation", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: { Text(saveError ?? "") }
        .accessibilityHint("Saves the inputs and results of this tool to the Notebook tab")
    }
}

extension View {
    /// Adds the Save to Notebook toolbar button.
    func notebookSnapshot(_ snapshot: @escaping () -> NotebookSnapshot?) -> some View {
        toolbar {
            ToolbarItem(placement: .trailingBar) { SaveToNotebookButton(snapshot: snapshot) }
        }
    }
}
