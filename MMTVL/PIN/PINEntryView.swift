import SwiftUI

/// The PIN screen on the 1920×1080 canvas, after Google TV's privacy keypad (D20, L9): a D-pad circle shows the
/// highlighted row's digits where Left/Select/Right enter them, beside a small keypad with that row outlined.
/// Nothing reacts to which column is pressed; only the underline slots fill.
struct PINEntryView: View {
    let model: PINEntryModel
    /// Mouse click on the small keypad: (row, column).
    let onEnter: (Int, Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 120) {
                header
                    .frame(width: 640, alignment: .leading)
                entry
            }
            .padding(.top, 160)

            Spacer()

            Text("Up/Down: row · Left, Select, Right: digit · Back: delete")
                .font(Theme.settingsHintFont)
                .foregroundStyle(Theme.secondaryText)
                .padding(.bottom, 48)
        }
        .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.primaryText)
            Text(model.title)
                .font(Theme.pinTitleFont)
                .foregroundStyle(Theme.primaryText)
            if let message = model.message {
                Text(message)
                    .font(Theme.settingsDetailFont)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var entry: some View {
        VStack(alignment: .leading, spacing: 48) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Enter PIN")
                    .font(Theme.pinLabelFont)
                    .textCase(.uppercase)
                    .tracking(2)
                    .foregroundStyle(Theme.secondaryText)
                slots
            }
            HStack(alignment: .center, spacing: Theme.pinColumnSpacing) {
                dial
                keypad
            }
        }
    }

    /// One underline per digit: filled ones white, the next one thicker, the rest dim. Digits are never shown.
    private var slots: some View {
        HStack(spacing: Theme.pinSlotSpacing) {
            ForEach(0..<PINPad.length, id: \.self) { index in
                let entered = index < model.pad.digits.count
                let isNext = index == model.pad.digits.count
                Capsule()
                    .fill(entered || isNext ? Theme.primaryText : Theme.secondaryText)
                    .frame(width: Theme.pinSlotWidth, height: isNext ? Theme.pinActiveSlotHeight : Theme.pinSlotHeight)
            }
        }
        .frame(height: Theme.pinActiveSlotHeight)
        .keyframeAnimator(initialValue: CGFloat.zero, trigger: model.shakeTrigger) { view, offset in
            view.offset(x: offset)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(-Theme.shakeDistance, duration: 0.05)
                LinearKeyframe(Theme.shakeDistance, duration: 0.1)
                LinearKeyframe(-Theme.shakeDistance / 2, duration: 0.1)
                LinearKeyframe(0, duration: 0.05)
            }
        }
    }

    /// The remote's D-pad ring: the highlighted row's digits at left, center and right; ticks hint Up/Down.
    private var dial: some View {
        let digits = PINPad.rows[model.pad.row]
        let offset = Theme.pinDialSize * 0.28
        return ZStack {
            Circle()
                .fill(Theme.pinDialFill)
                .shadow(color: .white.opacity(0.35), radius: 40)
            Text("–").offset(y: -Theme.pinDialSize * 0.4)
            Text("–").offset(y: Theme.pinDialSize * 0.4)
            if digits.count == 1 {
                Text("\(digits[0])")
            } else {
                Text("\(digits[0])").offset(x: -offset)
                Text("\(digits[1])")
                Text("\(digits[2])").offset(x: offset)
            }
        }
        .font(Theme.pinDialDigitFont)
        .foregroundStyle(Theme.pinDialText)
        .frame(width: Theme.pinDialSize, height: Theme.pinDialSize)
        .animation(Theme.focusAnimation, value: model.pad.row)
    }

    /// Small keypad; the highlighted row is outlined. Clicking a digit enters it.
    private var keypad: some View {
        VStack(spacing: Theme.pinKeypadRowSpacing) {
            ForEach(PINPad.rows.indices, id: \.self) { row in
                HStack(spacing: Theme.pinKeypadColumnSpacing) {
                    ForEach(PINPad.rows[row].indices, id: \.self) { column in
                        Text("\(PINPad.rows[row][column])")
                            .font(Theme.pinKeypadFont)
                            .foregroundStyle(Theme.primaryText)
                            .contentShape(Rectangle())
                            .onTapGesture { onEnter(row, column) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay {
                    if row == model.pad.row {
                        Capsule().strokeBorder(Theme.primaryText, lineWidth: 3)
                    }
                }
            }
        }
        // M7 L28: the keypad sits on glass.
        .padding(24)
        .glassPanel()
        .animation(Theme.focusAnimation, value: model.pad.row)
    }
}
