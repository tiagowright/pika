import AppKit

/// The pika head from `AppIcon.svg` as a flat silhouette with the eyes
/// cut out: the menu bar icon, and the same mark in the switcher's query
/// row so the two read as one app. Drawn from the SVG's own path data
/// rather than a bitmap, so it stays crisp at any scale.
enum PikaGlyph {
    /// Ears and face, copied from AppIcon.svg (512×512, y down). The tuft
    /// is left out: it crosses itself, and it's invisible at 18pt anyway.
    private static let silhouette = [
        "M134 231C106 215 91 181 97 151C102 124 119 110 142 113C176 116 198 154 190 195Z",
        "M322 195C314 154 336 116 370 113C393 110 410 124 415 151C421 181 406 215 378 231Z",
        "M256 172C180 172 132 209 114 265C104 288 96 313 101 339C110 389 174 418 256 418C338 418 402 389 411 339C416 313 408 288 398 265C380 209 332 172 256 172Z",
    ]
    /// The SVG's eyes (rx 16, ry 21), enlarged so they survive at 16pt.
    private static let eyes = [NSPoint(x: 189, y: 278), NSPoint(x: 323, y: 278)]
    private static let eyeRadii = NSSize(width: 26, height: 34)
    private static let artBounds = NSRect(x: 91, y: 110, width: 330, height: 308)

    /// Paths are parsed once; drawing only transforms copies.
    private static let shapes: [NSBezierPath] = silhouette.map(path(fromSVG:))
    private static let eyeShapes: [NSBezierPath] = eyes.map { eye in
        NSBezierPath(ovalIn: NSRect(x: eye.x - eyeRadii.width, y: eye.y - eyeRadii.height,
                                    width: eyeRadii.width * 2, height: eyeRadii.height * 2))
    }

    /// Draws the head centred in `rect`, `side` points across, in a
    /// flipped (y-down) context. `eyes` fills the eyes with a colour;
    /// nil clears them to transparent, which only makes sense in an image.
    static func draw(in rect: NSRect, side: CGFloat, color: NSColor, eyes eyeColor: NSColor?) {
        let scale = side / max(artBounds.width, artBounds.height)
        var transform = AffineTransform(
            translationByX: rect.minX + (rect.width - artBounds.width * scale) / 2 - artBounds.minX * scale,
            byY: rect.minY + (rect.height - artBounds.height * scale) / 2 - artBounds.minY * scale
        )
        transform.scale(scale)

        // Fill each shape on its own: as one path, the shapes' opposite
        // windings would cancel where they overlap.
        color.setFill()
        for shape in shapes {
            let copy = shape.copy() as! NSBezierPath
            copy.transform(using: transform)
            copy.fill()
        }

        let context = NSGraphicsContext.current
        if let eyeColor { eyeColor.setFill() } else { context?.compositingOperation = .clear }
        for eye in eyeShapes {
            let copy = eye.copy() as! NSBezierPath
            copy.transform(using: transform)
            copy.fill()
        }
        context?.compositingOperation = .sourceOver
    }

    /// The status item image. `badged` adds an orange dot: something needs
    /// the user's attention. A badged image can't be a template (the dot
    /// must stay orange), so it draws the head in the label colour itself.
    static func menuBarImage(badged: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            draw(in: rect, side: 16, color: badged ? .labelColor : .black, eyes: nil)
            if badged {
                let context = NSGraphicsContext.current
                let dot = NSRect(x: rect.maxX - 6, y: rect.maxY - 6, width: 6, height: 6)
                context?.compositingOperation = .clear
                NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill() // gap around the dot
                context?.compositingOperation = .sourceOver
                NSColor.systemOrange.setFill()
                NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        image.isTemplate = !badged
        image.accessibilityDescription = badged ? "Pika — needs attention" : "Pika"
        return image
    }

    /// Absolute M, L, C, and Z commands only — all AppIcon.svg uses.
    private static func path(fromSVG d: String) -> NSBezierPath {
        let path = NSBezierPath()
        var numbers: [CGFloat] = []
        var command: Character = "M"

        func flush() {
            switch command {
            case "M" where numbers.count >= 2:
                path.move(to: NSPoint(x: numbers[0], y: numbers[1]))
            case "L" where numbers.count >= 2:
                path.line(to: NSPoint(x: numbers[0], y: numbers[1]))
            case "C":
                var i = 0
                while i + 5 < numbers.count {
                    path.curve(to: NSPoint(x: numbers[i + 4], y: numbers[i + 5]),
                               controlPoint1: NSPoint(x: numbers[i], y: numbers[i + 1]),
                               controlPoint2: NSPoint(x: numbers[i + 2], y: numbers[i + 3]))
                    i += 6
                }
            case "Z":
                path.close()
            default:
                break
            }
            numbers = []
        }

        var token = ""
        for c in d + " " {
            if c.isLetter {
                if let n = Double(token) { numbers.append(CGFloat(n)) }
                token = ""
                flush()
                command = c
            } else if c == " " || c == "," {
                if let n = Double(token) { numbers.append(CGFloat(n)) }
                token = ""
            } else {
                token.append(c)
            }
        }
        flush()
        return path
    }
}
