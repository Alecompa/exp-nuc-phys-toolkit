import SwiftUI

/// Reuses a chart's bindings in an expanded presentation, so probe changes remain live.
struct ExpandablePlot<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading) {
            content().frame(height: 260)
            Button("Expand plot", systemImage: "arrow.up.left.and.arrow.down.right") { expanded = true }
                .font(.subheadline)
        }
        .sheet(isPresented: $expanded) {
            NavigationStack {
                ScrollView { content().frame(height: 440).padding() }
                    .navigationTitle(title)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { expanded = false } } }
            }
        }
    }
}
