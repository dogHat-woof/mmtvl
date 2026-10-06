import SwiftUI

/// Draws a tile's art (M7 L3, L4) at `size`, clipped to the rounded tile shape.
/// The icon or symbol is a `ParallaxLayer`, so it moves with the focused tile's tilt.
struct TileArtView: View {
    let art: TileArt
    var size: CGSize = Theme.tileSize
    var cornerRadius: CGFloat = Theme.tileCornerRadius
    /// The banner blurs icon art (M7 step 8).
    var blursIcon = false

    var body: some View {
        content
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        switch art {
        case .picture(let image):
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        case .gradient(let top, let bottom, let symbol):
            ZStack {
                LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                ParallaxLayer {
                    Image(systemName: symbol)
                        .font(.system(size: size.height * Theme.tileArtSymbolFraction))
                        .foregroundStyle(.white)
                }
            }
        case .designed(let top, let bottom, let accent, let icon, let symbol):
            ZStack {
                LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let accent {
                    RadialGradient(colors: [accent.opacity(0.45), accent.opacity(0)], center: .center, startRadius: 0,
                                   endRadius: size.height * 0.6)
                }
                ParallaxLayer {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(height: size.height * Theme.designedArtIconFraction)
                            .shadow(color: .black.opacity(0.35), radius: size.height * 0.05, y: size.height * 0.02)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: size.height * Theme.tileArtSymbolFraction))
                            .foregroundStyle(.white)
                    }
                }
            }
        case .icon(let icon):
            ZStack {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width * Theme.tileIconBackdropScale, height: size.width * Theme.tileIconBackdropScale)
                    .blur(radius: Theme.tileIconBackdropBlur)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                Color.black.opacity(Theme.tileIconBackdropDim)
                if !blursIcon {
                    ParallaxLayer {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(height: size.height * Theme.tileIconFraction)
                    }
                }
            }
        }
    }
}
