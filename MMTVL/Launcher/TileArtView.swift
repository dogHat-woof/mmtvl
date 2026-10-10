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
        case .picture(let image, .solid(let backdrop)):
            // M7c L33: a logo, inset on its own (or a contrasting) color.
            ZStack {
                backdrop
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size.width * (1 - 2 * Theme.tileLogoInset.width),
                           height: size.height * (1 - 2 * Theme.tileLogoInset.height))
            }
        case .picture(let image, .blurred):
            // M7c step 16: the whole picture, over a blurred, dimmed copy that fills what it doesn't (tvOS);
            // a 5:3 picture fills the tile as before.
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .blur(radius: Theme.tileArtFitBlur * size.width / Theme.tileSize.width, opaque: true)
                    .overlay(Color.black.opacity(Theme.tileArtFitDim))
                    .clipped()
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
            }
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
        case .glyph(let top, let bottom, let icon):
            glyph(top: top, bottom: bottom, icon: icon)
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

    /// M7c L33: the icon with its shape's edge faded out, on a gradient that continues its background: the gradient's
    /// ends sit where the icon's background was sampled, so the two meet without a seam.
    private func glyph(top: Color, bottom: Color, icon: NSImage) -> some View {
        let side = size.height * Theme.glyphArtIconFraction
        let iconTop = (size.height - side) / 2
        func y(_ band: ClosedRange<Double>) -> CGFloat {
            (iconTop + side * (band.lowerBound + band.upperBound) / 2) / size.height
        }
        return ZStack {
            LinearGradient(colors: [top, bottom], startPoint: UnitPoint(x: 0.5, y: y(IconBackground.topBand)),
                           endPoint: UnitPoint(x: 0.5, y: y(IconBackground.bottomBand)))
            ParallaxLayer {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .mask {
                        RoundedRectangle(cornerRadius: side * Theme.glyphArtMaskCornerRadius, style: .continuous)
                            .padding(side * Theme.glyphArtMaskInset)
                            .blur(radius: side * Theme.glyphArtMaskBlur)
                    }
            }
        }
    }
}
