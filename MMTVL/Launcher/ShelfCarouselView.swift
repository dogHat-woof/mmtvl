import SwiftUI

/// M7c L14 (D37): the Plex carousel's full-screen art. One page at a time, crossfading, with a slow zoom
/// (none with Reduce Motion). While a page's image loads, the previous page stays; on the first page, the tile's art.
struct ShelfCarouselBackdrop<Fallback: View>: View {
    let cards: [ShelfCard]
    let page: Int
    let images: ShelfImageLoader
    @ViewBuilder let fallback: () -> Fallback

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Shown?

    private struct Shown {
        var id: String
        var image: NSImage
    }

    var body: some View {
        let card = cards.indices.contains(page) ? cards[page] : nil
        let loaded = card.flatMap(Self.backdropImage(images))
        ZStack {
            if shown == nil { fallback() }
            if let shown {
                ZoomingImage(image: shown.image, zooms: !reduceMotion)
                    .id(shown.id)
                    .transition(.opacity)
            }
        }
        .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height)
        .clipped()
        .onChange(of: LoadedKey(cardID: card?.id, image: loaded), initial: true) {
            guard let card, let loaded, shown?.id != card.id else { return }
            withAnimation(Theme.carouselCrossfade) { shown = Shown(id: card.id, image: loaded) }
        }
    }

    private struct LoadedKey: Equatable {
        var cardID: String?
        var image: ObjectIdentifier?

        init(cardID: String?, image: NSImage?) {
            self.cardID = cardID
            self.image = image.map(ObjectIdentifier.init)
        }
    }

    /// The 1920 backdrop, else the card image scaled to fill.
    static func backdropImage(_ images: ShelfImageLoader) -> (ShelfCard) -> NSImage? {
        { card in
            if let backdrop = card.backdrop {
                return images.image(for: backdrop, maxPixelWidth: Theme.carouselImagePixelWidth)
            }
            return images.image(for: card.image)
        }
    }
}

/// Fills the canvas and zooms from 1 to `Theme.carouselZoom` over one page's time.
private struct ZoomingImage: View {
    let image: NSImage
    let zooms: Bool
    @State private var zoomed = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height)
            .scaleEffect(zoomed ? Theme.carouselZoom : 1)
            .clipped()
            .onAppear {
                guard zooms else { return }
                withAnimation(.linear(duration: Theme.carouselIntervalSeconds)) { zoomed = true }
            }
    }
}

/// M7c L14, L20 (D38): the page's logo or title, subtitle and time left at the top-left, always shown while the tile
/// is focused; the page dots centered just above the dock. With focus (Up from the first row) the text sits on a
/// glass panel with a hint. Live TV pages show the channel logo above the programme title.
struct ShelfCarouselInfo: View {
    let cards: [ShelfCard]
    let page: Int
    let isFocused: Bool
    let images: ShelfImageLoader
    let onActivate: (Int) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if cards.indices.contains(page) {
                info(cards[page])
                    .padding(isFocused ? 32 : 0)
                    .background {
                        if isFocused { Color.clear.glassPanel() }
                    }
                    .offset(x: Theme.carouselInfoOrigin.x - (isFocused ? 32 : 0),
                            y: Theme.carouselInfoOrigin.y - (isFocused ? 32 : 0))
                    .contentShape(Rectangle())
                    .onTapGesture { onActivate(page) }
                    .animation(Theme.focusAnimation, value: isFocused)
            }
            if cards.count > 1 {
                dots
                    .frame(width: Theme.canvasSize.width)
                    .offset(y: HomeLayout.dockFrame.minY - Theme.carouselDotsAboveDock - Theme.carouselDotSize)
            }
        }
        .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height, alignment: .topLeading)
    }

    private func info(_ card: ShelfCard) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            title(card)
                .id(card.id)
                .transition(.opacity)
            if !card.subtitle.isEmpty {
                Text(card.subtitle)
                    .font(Theme.carouselSubtitleFont)
                    .foregroundStyle(Theme.primaryText.opacity(0.85))
                    .frame(maxWidth: Theme.carouselInfoMaxWidth, alignment: .leading)
            }
            if card.minutesLeft != nil || card.progress != nil {
                HStack(spacing: 16) {
                    if let progress = card.progress {
                        CarouselProgressBar(value: progress)
                            .frame(width: Theme.carouselProgressWidth, height: Theme.shelfProgressHeight)
                    }
                    if let minutes = card.minutesLeft {
                        Text("\(minutes) min left")
                            .font(Theme.shelfDetailFont)
                            .foregroundStyle(Theme.primaryText.opacity(0.85))
                    }
                }
            }
            if isFocused {
                Text(hint(for: card))
                    .font(Theme.shelfDetailFont)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .lineLimit(1)
        .shadow(color: .black.opacity(0.6), radius: 8)
        // Hugs the text (each line is capped at `carouselInfoMaxWidth`), so the focused panel isn't wider than it.
        .fixedSize(horizontal: true, vertical: false)
    }

    private func hint(for card: ShelfCard) -> String {
        if case .playChannel = card.action { return "Select: Watch · Left/Right: Change Channel" }
        return "Select: Resume in Plex"
    }

    @ViewBuilder
    private func title(_ card: ShelfCard) -> some View {
        if let logo = card.logo, let image = images.image(for: logo, maxPixelWidth: Theme.carouselImagePixelWidth) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: Theme.carouselLogoMaxSize.width, maxHeight: Theme.carouselLogoMaxSize.height,
                       alignment: .bottomLeading)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if case .channelLogo(let url?) = card.image {
                    ChannelLogoView(url: url)
                        .frame(maxWidth: Theme.carouselChannelLogoMaxSize.width,
                               maxHeight: Theme.carouselChannelLogoMaxSize.height, alignment: .leading)
                }
                Text(card.title)
                    .font(Theme.carouselTitleFont)
                    .foregroundStyle(Theme.primaryText)
                    .frame(maxWidth: Theme.carouselInfoMaxWidth, alignment: .leading)
            }
        }
    }

    private var dots: some View {
        HStack(spacing: Theme.carouselDotSize) {
            ForEach(cards.indices, id: \.self) { index in
                Circle()
                    .fill(Color.white.opacity(index == page ? 1 : 0.4))
                    .frame(width: Theme.carouselDotSize, height: Theme.carouselDotSize)
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 4)
    }
}

/// A thin 0…1 bar.
private struct CarouselProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.shelfProgressTrack)
                Capsule().fill(Theme.shelfProgressFill)
                    .frame(width: geometry.size.width * min(max(value, 0), 1))
            }
        }
    }
}
