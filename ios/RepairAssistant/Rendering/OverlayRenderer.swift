import SwiftUI

/// Photo with an aspect-fit image plus an overlay area that matches the image rect exactly.
struct PhotoStage<Overlay: View>: View {
    let image: UIImage
    var cornerRadius: CGFloat = 24
    var dim: Double = 0
    @ViewBuilder var overlay: (CGSize) -> Overlay

    var body: some View {
        GeometryReader { geo in
            let fit = AspectFit.rect(content: image.size, in: geo.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height).clipped()
                    .blur(radius: 24).overlay(Color.black.opacity(0.45))
                Image(uiImage: image).resizable()
                    .frame(width: fit.width, height: fit.height)
                    .overlay(Color.black.opacity(dim))
                    .position(x: fit.midX, y: fit.midY)
                overlay(fit.size)
                    .frame(width: fit.width, height: fit.height)
                    .position(x: fit.midX, y: fit.midY)
            }
        }
        .aspectRatio(min(1.5, max(0.9, image.size.width / max(image.size.height, 1))), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}

