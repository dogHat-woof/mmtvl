import SwiftUI

/// M7f L12: search over Live TV on the 1920×1080 canvas: the keyboard on the left, results on the right.
struct LiveSearchView: View {
    let model: LiveSearchModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.searchDim
            Text("Search")
                .font(Theme.settingsTitleFont)
                .foregroundStyle(Theme.primaryText)
                .offset(x: Theme.searchKeyboardOrigin.x, y: Theme.searchTitleTop)
            OnScreenKeyboardView(keyboard: model.keyboard, placeholder: "Channels, teams, shows",
                                 isFocused: model.focus == .keyboard)
                .offset(x: Theme.searchKeyboardOrigin.x, y: Theme.searchKeyboardOrigin.y)
            results
                .frame(width: Theme.searchResultsRect.width, height: Theme.searchResultsRect.height, alignment: .topLeading)
                .offset(x: Theme.searchResultsRect.minX, y: Theme.searchResultsRect.minY)
            Text(hint)
                .font(Theme.settingsHintFont)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: Theme.canvasSize.width)
                .offset(y: Theme.canvasSize.height - 64)
        }
        .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height, alignment: .topLeading)
    }

    private var hint: String {
        switch model.focus {
        case .keyboard: "Select: type · Play/Pause: delete · Right: results · Back: close search"
        case .results(let index):
            // M7l L12: a team row adds or removes the team.
            if model.results.indices.contains(index), case .team(let team) = model.results[index] {
                Self.teamHint(isPicked: model.isTeamPicked(team))
            } else {
                "Select: watch · Left: keyboard · Back: keyboard"
            }
        }
    }

    /// M7l L12, 8c: the hint on a team result.
    nonisolated static func teamHint(isPicked: Bool) -> String {
        isPicked ? "Select: remove from My Teams · Left: keyboard" : "Select: add to My Teams · Left: keyboard"
    }

    @ViewBuilder
    private var results: some View {
        VStack(alignment: .leading, spacing: Theme.settingsRowSpacing) {
            if !model.isSearching {
                message("Type a channel, team or show")
            } else if model.results.isEmpty {
                message("No channels or programmes match")
            } else {
                let results = model.results
                ForEach(model.visibleResultRange, id: \.self) { index in
                    row(results[index], isFocused: model.focus == .results(index))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .glassPanel()
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(Theme.settingsRowFont)
            .foregroundStyle(Theme.secondaryText)
            .padding(20)
    }

    private func row(_ result: LiveSearchModel.Result, isFocused: Bool) -> some View {
        HStack(spacing: 20) {
            if let logo = result.channel?.logoURL {
                ChannelLogoView(url: logo)
                    .frame(width: Theme.guideLogoSize, height: Theme.guideLogoSize)
            } else {
                Image(systemName: result.channel == nil ? "sportscourt" : "tv")
                    .font(Theme.searchRowTitleFont)
                    .frame(width: Theme.guideLogoSize, height: Theme.guideLogoSize)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title(result))
                    .font(Theme.searchRowTitleFont)
                    .foregroundStyle(isFocused ? Theme.focusedRowText : Theme.primaryText)
                    .lineLimit(1)
                if let detail = detail(result) {
                    Text(detail)
                        .font(Theme.searchRowDetailFont)
                        .foregroundStyle(isFocused ? Theme.focusedRowSecondaryText : Theme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if case .team(let team) = result, model.isTeamPicked(team) {
                Text(TeamPicker.pickedValue)
                    .font(Theme.searchRowDetailFont)
                    .foregroundStyle(isFocused ? Theme.focusedRowSecondaryText : Theme.secondaryText)
            }
        }
        .foregroundStyle(isFocused ? Theme.focusedRowText : Theme.primaryText)
        .padding(.horizontal, 20)
        .frame(height: Theme.searchRowHeight)
        .background(isFocused ? Theme.focusedRowFill : Color.clear,
                    in: RoundedRectangle(cornerRadius: Theme.guideCellCornerRadius, style: .continuous))
        .scaleEffect(isFocused ? Theme.settingsRowFocusScale : 1)
        .animation(Theme.focusAnimation, value: isFocused)
    }

    /// "On Now · ESPN · NBA Basketball", "9:00 PM · ESPN · NBA Basketball"; a channel shows its name.
    private func title(_ result: LiveSearchModel.Result) -> String {
        switch result {
        case .channel(let channel):
            return channel.name
        case .programme(let channel, let programme):
            let when = model.isOnNow(programme) ? "On Now" : Self.startLabel(programme.start)
            return [when, channel.name, programme.title].joined(separator: " · ")
        case .team(let team):
            return team.pickTitle
        }
    }

    private func detail(_ result: LiveSearchModel.Result) -> String? {
        switch result {
        case .channel(let channel):
            // M7j: an antenna channel leads with its GuideNumber: "5.1 · Antenna".
            if let guideNumber = channel.guideNumber {
                return "\(guideNumber) · \(channel.group)"
            }
            return channel.group.isEmpty ? "Channel" : "Channel · \(channel.group)"
        case .programme(_, let programme):
            return programme.subtitle ?? programme.episode
        case .team(let team):
            // A pro team has no conference: its league.
            return team.conference ?? team.league.title
        }
    }

    /// "9:00 PM" today, "Tue 9:00 PM" on another day.
    static func startLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
