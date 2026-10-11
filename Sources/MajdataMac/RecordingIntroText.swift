import AppKit
import CoreText

/// Freeze each label before rendering any animation frames. CoreText performs Unicode
/// shaping and font fallback once; Canvas only transforms the resulting owned bitmap.
@MainActor final class RecordingIntroText {
    struct Label {
        let image: CGImage
        let bounds: CGRect
    }
    let labels: [String: Label]

    init(info: StageChartInfo, height: Int) throws {
        let assets = RecordingIntroAssets.shared
        // Cover the largest entry scale (1.2) and level badge scale (1.5).
        let scale = Double(height) / 108 * 1.8
        var prepared: [String: Label] = [:]
        for node in assets.manifest.nodes {
            guard let field = node.field else { continue }
            let value: String
            switch field {
            case "level": value = info.level.isEmpty ? "—" : info.level
            case "difficulty": value = info.difficultyName
            case "title": value = info.title
            case "artist": value = info.artist
            case "designer": value = info.designer
            default: value = field
            }
            let width = field == "level" ? min(7.6, node.width) : (field == "difficulty" ? min(14.8, node.width) : node.width)
            let maximum = field == "level" ? min(3.6, node.fontSize) : node.fontSize
            let size = CGSize(width: width * scale, height: node.height * scale)
            let alignment: CTTextAlignment = switch node.alignment % 3 {
            case 0: .left
            case 2: .right
            default: .center
            }
            func string(_ fontSize: Double) -> NSAttributedString {
                let font = HarmonyOSFont.coreText(size: fontSize * scale, bold: field == "title" || field == "level" || field == "difficulty")
                var alignment = alignment
                let paragraph = withUnsafePointer(to: &alignment) {
                    let setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: $0)
                    return CTParagraphStyleCreate([setting], 1)
                }
                return NSAttributedString(string: value, attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): NSColor.white.cgColor,
                    NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph
                ])
            }
            func measure(_ text: NSAttributedString, wrapped: Bool) -> CGSize {
                CTFramesetterSuggestFrameSizeWithConstraints(CTFramesetterCreateWithAttributedString(text),
                    CFRange(), nil, CGSize(width: wrapped ? size.width : .greatestFiniteMagnitude, height: .greatestFiniteMagnitude), nil)
            }
            let wrapped = field == "title" && measure(string(maximum), wrapped: false).width > size.width
            var lower = 0.01, upper = maximum
            for _ in 0..<16 {
                let candidate = (lower + upper) / 2
                let measured = measure(string(candidate), wrapped: wrapped)
                if measured.width <= size.width && measured.height <= size.height { lower = candidate } else { upper = candidate }
            }
            let text = string(lower)
            let measured = measure(text, wrapped: wrapped)
            // Transparent padding preserves antialiased edges at the card boundary.
            let padding = 2.0
            let pixelWidth = Int(ceil(size.width + 2 * padding)), pixelHeight = Int(ceil(size.height + 2 * padding))
            guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw ExportFailure.failure("无法生成录制开场文字")
            }
            let vertical = Double(node.alignment / 3) / 2
            let textHeight = min(size.height, ceil(measured.height))
            let rect = CGRect(x: padding, y: padding + (size.height - textHeight) * (1 - vertical), width: size.width, height: textHeight)
            let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(text), CFRange(), CGPath(rect: rect, transform: nil), nil)
            context.textMatrix = .identity
            CTFrameDraw(frame, context)
            guard let image = context.makeImage() else { throw ExportFailure.failure("无法保存录制开场文字") }
            let horizontal = Double(node.alignment % 3) / 2
            prepared[node.path] = Label(image: image, bounds: CGRect(
                x: (horizontal - 0.5) * (node.width - width) - width / 2 - padding / scale + (field == "level" ? 0.74 : 0),
                y: -node.height / 2 - padding / scale, width: Double(pixelWidth) / scale, height: Double(pixelHeight) / scale))
        }
        labels = prepared
    }
}
