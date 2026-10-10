import SwiftUI

/// M7 L27: the focused tile's art, full screen behind the home screen (tvOS 26/27), with scrims for the tiles and clock.
struct ShelfBackdrop: View {
    /// The focused tile.
    let item: LaunchItem?
    let art: TileArt?
    /// Cards are showing: the art is darkened so their captions read.
    let isDimmed: Bool
    /// M7c L14: a carousel replaces the tile's art (the scrims stay).
    var carousel: (cards: [ShelfCard], page: Int, images: ShelfImageLoader)?
    /// M7c L15: 0 while the Live TV preview plays behind the canvas (the scrims stay).
    var artOpacity: Double = 1

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let art {
                Group {
                    if let carousel {
                        ShelfCarouselBackdrop(cards: carousel.cards, page: carousel.page, images: carousel.images) {
                            artLayer(art)
                        }
                    } else {
                        artLayer(art)
                    }
                }
                .opacity(artOpacity)
                .animation(Theme.previewRevealAnimation, value: artOpacity)
                Color.black.opacity(isDimmed ? Theme.shelfCardsDim : 0)
                if carousel != nil {
                    // M7c L20: the hero's text sits top-left.
                    RadialGradient(colors: [.black.opacity(Theme.shelfInfoScrimOpacity), .clear],
                                   center: .topLeading, startRadius: 0, endRadius: Theme.shelfInfoScrimRadius)
                }
                LinearGradient(stops: [
                    .init(color: .clear, location: Theme.shelfScrimStart),
                    .init(color: .black.opacity(Theme.shelfScrimOpacity), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [.black.opacity(Theme.shelfClockScrimOpacity), .clear],
                               center: UnitPoint(x: 1, y: 0), startRadius: 0, endRadius: 480)
            }
        }
        .frame(width: Theme.canvasSize.width, height: Theme.canvasSize.height)
        .clipped()
        .id(item?.id)
        .transition(.opacity)
        .animation(Theme.shelfBackdropCrossfade, value: item?.id)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func artLayer(_ art: TileArt) -> some View {
        let size = Theme.canvasSize
        switch art {
        case .picture(_, .solid(let backdrop)):
            backdrop
        case .picture(let image, .blurred):
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        // M7c L13: color and blur only; the tiles keep their own icons.
        case .gradient(let top, let bottom, _):
            LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .glyph(let top, let bottom, _):
            LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
        case .designed(let top, let bottom, let accent, _, _):
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let accent {
                    RadialGradient(colors: [accent.opacity(0.4), .clear],
                                   center: UnitPoint(x: Theme.shelfBackdropGlowCenter.x / size.width,
                                                     y: Theme.shelfBackdropGlowCenter.y / size.height),
                                   startRadius: 0, endRadius: Theme.shelfBackdropGlowRadius)
                }
            }
        case .icon(let icon):
            ZStack(alignment: .topLeading) {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .blur(radius: Theme.shelfBannerBlur)
                    .clipped()
                Color.black.opacity(Theme.shelfBannerDim)
            }
        }
    }
}

/// The top shelf's cards (M7 D28, L12) over the backdrop; nothing for a banner.
struct TopShelfView: View {
    /// The focused tile.
    let item: LaunchItem?
    let content: ShelfContent
    /// nil = the tiles have focus.
    let focusedIndex: Int?
    let focusMotion: FocusMotion
    let onHoverCard: (Int) -> Void
    let onActivateCard: (Int) -> Void
    let images: ShelfImageLoader
    /// M7c L14: the carousel's page while the tiles have focus.
    var carouselPage = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            switch content {
            case .cards(let title, let cards):
                cardRow(title: title, cards: cards)
            case .carousel(_, let cards, _):
                ShelfCarouselInfo(cards: cards, page: focusedIndex ?? carouselPage, isFocused: focusedIndex != nil,
                                  images: images, onActivate: onActivateCard)
            case .banner:
                EmptyView()
            }
        }
        .frame(width: Theme.canvasSize.width, height: Theme.shelfHeight, alignment: .topLeading)
        .id(item?.id)
        .transition(.opacity)
        .animation(Theme.shelfCrossfade, value: item?.id)
    }

    // MARK: Cards

    private func cardRow(title: String, cards: [ShelfCard]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Theme.shelfTitleFont)
                .foregroundStyle(Theme.primaryText.opacity(0.85))
                .shadow(color: .black.opacity(0.6), radius: 6)
                .padding(.leading, Theme.sideMargin)
                .frame(height: Theme.shelfCardsTop - Theme.shelfTitleTop, alignment: .topLeading)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Theme.shelfCardSpacing) {
                        ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                            cardView(card, isFocused: focusedIndex == index)
                                .id(card.id)
                                .onHover { hovering in
                                    if hovering { onHoverCard(index) }
                                }
                                .onTapGesture { onActivateCard(index) }
                        }
                    }
                    .padding(.horizontal, Theme.sideMargin)
                }
                .scrollClipDisabled()
                .onChange(of: focusedIndex) {
                    guard let focusedIndex, cards.indices.contains(focusedIndex) else { return }
                    withAnimation(Theme.focusAnimation) { proxy.scrollTo(cards[focusedIndex].id, anchor: .center) }
                }
            }
        }
        .padding(.top, Theme.shelfTitleTop)
    }

    private func cardView(_ card: ShelfCard, isFocused: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.shelfCardCornerRadius, style: .continuous)
                    .fill(Theme.shelfCardFill)
                cardImage(card.image)
            }
            .frame(width: Theme.shelfCardSize.width, height: Theme.shelfCardSize.height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.shelfCardCornerRadius, style: .continuous))
            .glassRim(cornerRadius: Theme.shelfCardCornerRadius, isFocused: isFocused)
            .parallaxFocus(isFocused: isFocused, motion: focusMotion, cornerRadius: Theme.shelfCardCornerRadius)
            .animation(Theme.focusAnimation, value: isFocused)

            if let progress = card.progress {
                ProgressBar(value: progress)
                    .frame(width: Theme.shelfCardSize.width, height: Theme.shelfProgressHeight)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(Theme.shelfCaptionFont)
                    .foregroundStyle(Theme.primaryText)
                Text(card.subtitle)
                    .font(Theme.shelfDetailFont)
                    .foregroundStyle(Theme.secondaryText)
            }
            .lineLimit(1)
            .shadow(color: .black.opacity(0.6), radius: 6)
            .frame(width: Theme.shelfCardSize.width, alignment: .leading)
        }
    }

    @ViewBuilder
    private func cardImage(_ image: ShelfCard.Image) -> some View {
        switch image {
        case .channelLogo(let url):
            ChannelLogoView(url: url) {
                Image(systemName: "tv").font(.system(size: 56)).foregroundStyle(Theme.secondaryText)
            }
            .frame(width: Theme.shelfCardSize.width * 0.6, height: Theme.shelfCardSize.height * 0.5)
        case .remote:
            if let loaded = images.image(for: image) {
                Image(nsImage: loaded)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: Theme.shelfCardSize.width, height: Theme.shelfCardSize.height)
                    .clipped()
            } else {
                Image(systemName: "photo").font(.system(size: 56)).foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

/// A thin 0…1 bar.
private struct ProgressBar: View {
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
