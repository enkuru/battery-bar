import AppKit

/// iPhone-style battery: the fill shows the charge; the percentage and power glyph are cut out of the body.
enum BatteryIcon {
    private static let bodySize = NSSize(width: 25, height: 12)
    private static let batterySize = NSSize(width: ceil(bodySize.width + capGap + capSize.width), height: bodySize.height)
    private static let cornerRadius: CGFloat = 3.6
    private static let capSize = NSSize(width: 1.5, height: 4.5)
    private static let capGap: CGFloat = 1
    private static let trackAlpha: CGFloat = 0.4
    private static let captionFontSize: CGFloat = 10
    private static let captionGap: CGFloat = 2.5

    /// - Parameters:
    ///   - caption: Short text stacked under the battery, such as the time left.
    ///   - scale: Enlarges the drawing, for the menu's header.
    ///   - appearance: Resolves the colors for a fixed appearance; nil follows whatever draws the image.
    static func image(for state: BatteryState, caption: String? = nil, scale: CGFloat = 1,
                      appearance: NSAppearance? = nil) -> NSImage {
        let fillColor = BatteryTone(state).fill
        // Template images let the menu bar choose black or white; colored states cannot be templates.
        let ink: NSColor = fillColor == nil ? .black : .labelColor
        let caption = caption.map { Caption(text: $0) }
        let size = caption.map {
            NSSize(width: max(batterySize.width, ceil($0.bounds.width)),
                   height: batterySize.height + captionGap + ceil($0.bounds.height))
        } ?? batterySize

        let image = NSImage(size: NSSize(width: size.width * scale, height: size.height * scale), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            let draw = {
                context.scaleBy(x: scale, y: scale)
                let body = NSRect(x: (size.width - batterySize.width) / 2, y: size.height - bodySize.height,
                                  width: bodySize.width, height: bodySize.height)
                drawBattery(in: body, state: state, ink: ink, fillColor: fillColor, context: context)
                caption?.draw(centeredAt: size.width / 2, color: ink, in: context)
            }
            if let appearance { appearance.performAsCurrentDrawingAppearance(draw) } else { draw() }
            return true
        }
        image.isTemplate = fillColor == nil
        image.accessibilityDescription = ["Battery \(state.percentage)%", caption?.text].compactMap(\.self).joined(separator: ", ")
        return image
    }

    private static func glyph(named name: String, pointSize: CGFloat) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold))
    }

    private static func drawBattery(in body: NSRect, state: BatteryState, ink: NSColor, fillColor: NSColor?,
                                    context: CGContext) {
        let bodyPath = NSBezierPath(roundedRect: body, xRadius: cornerRadius, yRadius: cornerRadius)
        let cap = NSRect(x: body.maxX + capGap, y: body.midY - capSize.height / 2,
                         width: capSize.width, height: capSize.height)
        let filled = body.divided(atDistance: body.width * CGFloat(state.percentage) / 100, from: .minXEdge).slice

        ink.withAlphaComponent(trackAlpha).setFill()
        bodyPath.fill()
        NSBezierPath(roundedRect: cap, xRadius: capSize.width / 2, yRadius: capSize.width / 2).fill()

        NSGraphicsContext.saveGraphicsState()
        filled.clip()
        (fillColor ?? ink).setFill()
        bodyPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        Label.fitting(percentage: state.percentage, glyphName: state.isOnPowerAdapter ? "bolt.fill" : nil,
                      in: body, context: context)
            .knockOut(in: context)
    }

    /// One line of small text, measured by its glyphs so it sits tight under the battery.
    private struct Caption {
        let text: String
        let line: CTLine
        let bounds: CGRect

        init(text: String) {
            let font = NSFont.monospacedDigitSystemFont(ofSize: BatteryIcon.captionFontSize, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
            ]
            self.text = text
            line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        }

        /// Draws with its bottom at y = 0.
        func draw(centeredAt midX: CGFloat, color: NSColor, in context: CGContext) {
            context.saveGState()
            context.setFillColor(color.cgColor)
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: midX - bounds.width / 2 - bounds.minX, y: -bounds.minY)
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }

    /// The percentage and an optional power glyph, centered together and shrunk to fit the body.
    private struct Label {
        private static let fontSize: CGFloat = 10.5
        private static let padding: CGFloat = 2
        private static let glyphGap: CGFloat = 0.5
        private static let glyphScale: CGFloat = 0.85

        let line: CTLine
        let textPosition: CGPoint
        let glyph: NSImage?
        let glyphRect: NSRect
        let width: CGFloat

        static func fitting(percentage: Int, glyphName: String?, in body: NSRect, context: CGContext) -> Label {
            let label = Label(percentage: percentage, glyphName: glyphName, pointSize: fontSize,
                              centeredIn: body, context: context)
            let available = body.width - 2 * padding
            guard label.width > available else { return label }

            return Label(percentage: percentage, glyphName: glyphName, pointSize: fontSize * available / label.width,
                         centeredIn: body, context: context)
        }

        private init(percentage: Int, glyphName: String?, pointSize: CGFloat, centeredIn body: NSRect,
                     context: CGContext) {
            let font = NSFont.systemFont(ofSize: pointSize, weight: .semibold)
            line = CTLineCreateWithAttributedString(NSAttributedString(string: String(percentage), attributes: [.font: font]))
            context.textMatrix = .identity
            let textBounds = CTLineGetImageBounds(line, context)

            let glyph = glyphName.flatMap { BatteryIcon.glyph(named: $0, pointSize: pointSize * Self.glyphScale) }
            let glyphSize = glyph?.size ?? .zero
            width = textBounds.width + (glyph == nil ? 0 : Self.glyphGap + glyphSize.width)
            let minX = body.midX - width / 2

            textPosition = CGPoint(x: minX - textBounds.minX, y: body.midY - textBounds.midY)
            self.glyph = glyph
            glyphRect = NSRect(x: minX + textBounds.width + Self.glyphGap, y: body.midY - glyphSize.height / 2,
                               width: glyphSize.width, height: glyphSize.height)
        }

        /// Cuts the label out of the fill and the track alike, so it shows the menu bar's color in one piece.
        func knockOut(in context: CGContext) {
            context.saveGState()
            context.setBlendMode(.destinationOut)
            context.textMatrix = .identity
            context.textPosition = textPosition
            CTLineDraw(line, context)
            context.restoreGState()

            glyph?.draw(in: glyphRect, from: .zero, operation: .destinationOut, fraction: 1)
        }
    }
}
