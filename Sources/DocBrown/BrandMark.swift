import SwiftUI
#if canImport(DocBrownCore)
import DocBrownCore
#endif

struct BrandMark: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 1024
            let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: (size.width - 1024 * scale) / 2, ty: (size.height + 1024 * scale) / 2)
            for layer in BrandGeometry.layers {
                var matrix = transform
                if let cgPath = layer.path.copy(using: &matrix) {
                    context.fill(Path(cgPath), with: .color(Color(red: layer.color.0, green: layer.color.1, blue: layer.color.2, opacity: layer.color.3)))
                }
            }
        }.accessibilityLabel("DocBrown time machine with flaming tire tracks")
    }
}

/// Render the shared artwork at menu-bar size, retaining Retina resolution and color.
enum BrandAssets {
    static let menuBarImage: NSImage = {
        let layers = BrandGeometry.layers
        let bounds = layers.reduce(CGRect.null) { $0.union($1.path.boundingBoxOfPath) }
        let image = NSImage(size: NSSize(width: 26, height: 22), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let scale = min((rect.width - 2) / bounds.width, (rect.height - 2) / bounds.height)
            context.saveGState()
            defer { context.restoreGState() }
            context.interpolationQuality = .high
            context.setShouldAntialias(true)
            context.translateBy(x: rect.midX - bounds.midX * scale, y: rect.midY - bounds.midY * scale)
            context.scaleBy(x: scale, y: scale)
            for layer in layers {
                context.addPath(layer.path)
                context.setFillColor(CGColor(red: layer.color.0, green: layer.color.1, blue: layer.color.2, alpha: layer.color.3))
                context.fillPath()
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "DocBrown — car with flaming tire tracks"
        return image
    }()
}
