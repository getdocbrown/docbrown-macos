import CoreGraphics

/// Original polygonal time-machine artwork. Shared by the app and icon generator.
public enum BrandGeometry {
    public struct Layer {
        public let path: CGPath
        public let color: (CGFloat, CGFloat, CGFloat, CGFloat)
    }
    public static var layers: [Layer] {
        let rotation = CGAffineTransform(translationX: 650, y: 650).rotated(by: -.pi / 4)
        func polygon(_ points: [(CGFloat, CGFloat)], _ color: (CGFloat,CGFloat,CGFloat,CGFloat)) -> Layer {
            let p = CGMutablePath()
            for (index, point) in points.enumerated() {
                if index == 0 { p.move(to: CGPoint(x: point.0, y: point.1)) }
                else { p.addLine(to: CGPoint(x: point.0, y: point.1)) }
            }
            p.closeSubpath()
            var transform = rotation
            return Layer(path: p.copy(using: &transform) ?? p, color: color)
        }
        var result: [Layer] = []
        for x: CGFloat in [-112, 112] {
            result.append(polygon([(x-38,-210),(x+40,-218),(x+36,-315),(x+60,-378),(x+26,-365),(x+38,-480),(x+6,-443),(x+10,-663),(x-28,-610),(x-18,-724),(x-59,-648),(x-48,-540),(x-74,-574),(x-50,-433),(x-68,-449),(x-48,-329)], (1,0.22,0.08,0.95)))
            result.append(polygon([(x-22,-217),(x+21,-217),(x+18,-337),(x+34,-376),(x+6,-372),(x+15,-485),(x-6,-463),(x-21,-620),(x-27,-522),(x-43,-540),(x-24,-401),(x-36,-410)], (1,0.56,0.12,1)))
            result.append(polygon([(x-7,-216),(x+9,-217),(x+6,-338),(x+15,-361),(x-5,-427),(x-12,-528),(x-19,-438),(x-12,-338)], (1,0.89,0.48,1)))
        }
        // Four exposed tires and the wedge-shaped stainless-steel body.
        for x: CGFloat in [-171, 139] {
            for y: CGFloat in [-182, 106] {
                result.append(polygon([(x,y),(x+34,y),(x+34,y+90),(x,y+90)], (0.035,0.055,0.07,1)))
            }
        }
        result.append(polygon([(-144,-238),(144,-238),(166,-96),(147,177),(92,259),(-92,259),(-147,177),(-166,-96)], (0.37,0.46,0.54,1)))
        result.append(polygon([(-124,-220),(122,-220),(140,-85),(125,173),(83,237),(-83,237),(-125,173),(-140,-85)], (0.78,0.84,0.88,1)))
        result.append(polygon([(-124,-220),(-140,-85),(-125,173),(-83,237),(-68,154),(-91,-55),(-76,-205)], (0.92,0.96,0.97,1)))
        result.append(polygon([(76,-205),(91,-55),(68,154),(83,237),(125,173),(140,-85),(122,-220)], (0.49,0.59,0.66,1)))
        result.append(polygon([(-105,82),(105,82),(83,164),(-83,164)], (0.06,0.16,0.21,1)))
        result.append(polygon([(-84,103),(84,103),(69,148),(-69,148)], (0.17,0.35,0.40,1)))
        result.append(polygon([(-91,-81),(91,-81),(105,62),(-105,62)], (0.10,0.20,0.25,1)))
        result.append(polygon([(-67,-63),(67,-63),(75,43),(-75,43)], (0.53,0.63,0.69,1)))
        result.append(polygon([(-104,-187),(104,-187),(93,-111),(-93,-111)], (0.13,0.20,0.25,1)))
        for y: CGFloat in [-171,-153,-135] {
            result.append(polygon([(-82,y),(82,y),(82,y+5),(-82,y+5)], (0.48,0.62,0.68,1)))
        }
        result.append(polygon([(-109,-215),(-22,-215),(-22,-204),(-109,-204)], (1,0.30,0.14,1)))
        result.append(polygon([(22,-215),(109,-215),(109,-204),(22,-204)], (1,0.30,0.14,1)))
        result.append(polygon([(-81,194),(81,194),(73,214),(-73,214)], (0.95,0.99,1,1)))
        return result
    }
}
