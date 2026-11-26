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

    /// Pointer highlight for custom tappable cards on iPad (no-op elsewhere).
    func cardHoverEffect() -> some View {
        #if os(iOS)
        hoverEffect(.highlight)
        #else
        self
        #endif
    }

    /// Keeps scrolling content (lists, forms, charts) to a comfortable width on wide iPad windows by widening the
    /// horizontal content margins; narrower windows keep the system margins.
    func readableContentWidth(_ maxWidth: CGFloat = 880) -> some View {
        modifier(ReadableContentWidth(maxWidth: maxWidth))
    }

    /// A text field that sits on the trailing side of a labelled row. On the Mac its own title is hidden (the row
    /// already shows it; macOS forms would print it twice) and it gets the bordered, fixed-width look of a Mac
    /// form field instead of stretching across the row. On iOS the field is capped in width so a long row label
    /// keeps the rest of the row instead of wrapping under, or being truncated by, a greedy field.
    func rowField(width: CGFloat = 120) -> some View {
        #if os(macOS)
        labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
        #else
        frame(minWidth: 44, maxWidth: width + 20)
        #endif
    }

    /// A labelled row holding a text field. On iOS the stock style caps the label at about half the row when the
    /// content is a flexible field, truncating labels such as "Branching / γ intensity" next to a short value;
    /// here the label keeps its full width and the field takes what is left. Unchanged on the Mac.
    func fieldRow() -> some View {
        #if os(macOS)
        self
        #else
        labeledContentStyle(FieldRowStyle())
        #endif
    }

    /// Grouped form sections on every platform (the macOS default, `.columns`, right-aligns labels in a separate
    /// column and repeats the titles of embedded fields).
    func groupedForm() -> some View {
        formStyle(.grouped)
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

/// Words for pointer and touch gestures in hints, so the Mac says "click" where iOS says "tap".
enum GestureWords {
    /// "Tap" / "Click".
    static var tap: String {
        #if os(macOS)
        "Click"
        #else
        "Tap"
        #endif
    }

    /// "Touch and hold" / "Right-click".
    static var hold: String {
        #if os(macOS)
        "Right-click"
        #else
        "Touch and hold"
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

private struct ReadableContentWidth: ViewModifier {
    let maxWidth: CGFloat
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        // nil keeps the system margin, so iPhone and narrow iPad windows are unchanged.
        let excess = (width - maxWidth) / 2
        content
            .contentMargins(.horizontal, excess > 20 ? excess : nil, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

extension View {
    /// Lets a list section footer wrap onto several lines. macOS lists size rows and footers to one line
    /// unless the text is allowed to grow vertically; iOS already wraps.
    func wrappingFooter() -> some View {
        #if os(macOS)
        lineLimit(nil)
        #else
        self
        #endif
    }
}

/// Scrolling container of the calculator screens. iOS: an inset grouped `List`. Mac: a grouped `Form`, the
/// System Settings look, whose sections lay out their own content, so long footers wrap (macOS lists give a
/// footer one line) and fields line up like a Mac inspector.
struct ToolList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if os(macOS)
        Form { content }.formStyle(.grouped)
        #else
        List { content }
        #endif
    }
}

extension View {
    /// Right-click Delete for a row on the Mac, where grouped forms have no swipe-to-delete. No-op on iOS,
    /// which keeps the swipe of `onDelete`.
    func macDeleteMenu(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        contextMenu { Button("Delete", systemImage: "trash", role: .destructive, action: action) }
        #else
        self
        #endif
    }
}

extension View {
    /// A control pinned to the bottom of a scrolling screen. iOS: floating over the content. Mac: a safe-area
    /// bar, so the grouped form scrolls its last rows above the control instead of under it.
    func bottomControlBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        #if os(macOS)
        safeAreaBar(edge: .bottom, content: bar)
        #else
        safeAreaInset(edge: .bottom, content: bar)
        #endif
    }
}

extension View {
    /// A button whose label is a whole row (it opens an editor). On the Mac a grouped form would draw it as a
    /// grey push button spanning the row; plain style keeps it a row, clickable across its full width.
    func rowButton() -> some View {
        #if os(macOS)
        buttonStyle(.plain).contentShape(Rectangle())
        #else
        self
        #endif
    }
}

#if !os(macOS)
/// Label first at full width, the field trailing in the remaining space (see `fieldRow()`).
struct FieldRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label.layoutPriority(1)
            Spacer(minLength: 8)
            configuration.content
        }
    }
}
#endif
