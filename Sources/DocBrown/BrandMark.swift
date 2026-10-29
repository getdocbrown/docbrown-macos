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
