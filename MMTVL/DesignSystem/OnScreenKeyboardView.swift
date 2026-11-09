import SwiftUI

/// M7f L11: draws an `OnScreenKeyboard`: the text field above the key grid, sized for a
/// `Theme.keyboardWidth` column on the 1920×1080 canvas.
struct OnScreenKeyboardView: View {
    let keyboard: OnScreenKeyboard
    var placeholder = "Search"
    /// False while focus is elsewhere on the screen (e.g. the results): no key is highlighted.
    var isFocused = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.keyboardFieldSpacing) {
            field
            VStack(alignment: .leading, spacing: Theme.keyboardKeySpacing) {
                ForEach(Array(keyboard.rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: Theme.keyboardKeySpacing) {
                        ForEach(Array(row.enumerated()), id: \.offset) { keyIndex, key in
                            keyView(key, isFocused: isFocused && keyboard.focus == .init(row: rowIndex, key: keyIndex))
                        }
                    }
                }
            }
        }
        .frame(width: Theme.keyboardWidth, alignment: .leading)
    }

    private var field: some View {
        HStack(spacing: 2) {
            if keyboard.text.isEmpty {
                caret
                Text(placeholder)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text(keyboard.text)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.head)
                caret
            }
            Spacer(minLength: 0)
        }
        .font(Theme.keyboardFieldFont)
        .padding(.horizontal, 24)
        .frame(width: Theme.keyboardWidth, height: Theme.keyboardFieldHeight)
        .glassPanel(in: Capsule())
    }

    private var caret: some View {
        Rectangle()
            .fill(Theme.primaryText)
            .frame(width: 3, height: Theme.keyboardFieldHeight * 0.5)
    }

    private func keyView(_ key: OnScreenKeyboard.Key, isFocused: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.keyboardKeyCornerRadius, style: .continuous)
        return Text(key.title)
            .font(key.span == 1 ? Theme.keyboardKeyFont : Theme.keyboardWideKeyFont)
            .foregroundStyle(isFocused ? Theme.focusedRowText : Theme.primaryText)
            .frame(width: Self.width(span: key.span), height: Theme.keyboardKeyHeight)
            .background(isFocused ? Theme.focusedRowFill : Theme.keyboardKeyFill, in: shape)
            .glassRim(cornerRadius: Theme.keyboardKeyCornerRadius, isFocused: isFocused)
            .scaleEffect(isFocused ? Theme.keyboardFocusedScale : 1)
            .animation(Theme.focusAnimation, value: isFocused)
            .accessibilityLabel(key.title)
    }

    /// Wide keys cover their columns and the gaps between them, so every row lines up.
    static func width(span: Int) -> CGFloat {
        let columns = CGFloat(OnScreenKeyboard.columns)
        let column = (Theme.keyboardWidth - Theme.keyboardKeySpacing * (columns - 1)) / columns
        return column * CGFloat(span) + Theme.keyboardKeySpacing * CGFloat(span - 1)
    }
}
