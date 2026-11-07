import SwiftUI

// iOS-only modifiers wrapped so ToolkitUI also compiles for macOS (used to type-check on a Mac
// without Xcode, and for a future Mac build).

extension View {
    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    func largeTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }

    func decimalKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad).autocorrectionDisabled()
        #else
        self
        #endif
    }

    /// Keyboard with digits, minus sign and the letter e (scientific notation).
    func scientificKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        autocorrectionDisabled()
        #endif
    }

    func notationInput() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
        #else
        autocorrectionDisabled()
        #endif
    }

    /// Adds a Done button above the keyboard (the decimal pad has no return key).
    func keyboardDoneButton() -> some View {
        #if os(iOS)
        toolbar {
            ToolbarItem(placement: .keyboard) {
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        #else
        self
        #endif
    }

    func alwaysVisibleSearch(text: Binding<String>, prompt: String) -> some View {
        #if os(iOS)
        searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        #else
        searchable(text: text, prompt: prompt)
        #endif
    }

    func groupedList() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }

    /// Zoom navigation transition from a matched source (iOS); plain push elsewhere.
    @ViewBuilder
    func zoomTransition(id: some Hashable, in namespace: Namespace.ID) -> some View {
        #if os(iOS)
        navigationTransition(.zoom(sourceID: id, in: namespace))
        #else
        self
        #endif
    }

    @ViewBuilder
    func zoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        #if os(iOS)
        matchedTransitionSource(id: id, in: namespace)
        #else
        self
        #endif
    }

    /// Hides the tab bar on screens with their own floating bottom control (no stacked glass bars).
    func hidingTabBar() -> some View {
        #if os(iOS)
        toolbarVisibility(.hidden, for: .tabBar)
        #else
        self
        #endif
    }

    func minimizingTabBar() -> some View {
        #if os(iOS)
        tabBarMinimizeBehavior(.onScrollDown)
        #else
        self
        #endif
    }
}

extension Color {
    /// Card fill in the content layer (never glass).
    static var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    static var groupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}

extension ToolbarItemPlacement {
    static var trailingBar: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

/// Cross-platform clipboard.
enum Pasteboard {
    @MainActor static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
