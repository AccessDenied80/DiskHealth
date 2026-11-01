import SwiftUI

/// ScrollView, висота якого дорівнює висоті вмісту, але не більша за `maxHeight`.
/// Звичайний ScrollView у вікні MenuBarExtra не має власної висоти: доводилося задавати
/// фіксовану, і з одним-двома дисками внизу лишалося багато порожнього місця.
struct FittedScrollView<Content: View>: View {
    var maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content
                .background(GeometryReader { geo in
                    Color.clear.preference(key: HeightKey.self, value: geo.size.height)
                })
        }
        .onPreferenceChange(HeightKey.self) { contentHeight = $0 }
        .frame(height: min(max(contentHeight, 1), maxHeight))
    }
}

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
