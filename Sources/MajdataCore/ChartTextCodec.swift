import Foundation

/// Do not guess legacy encodings: a wrong guess can produce valid but garbled text.
/// BOM-marked Unicode files are supported; saves use the existing UTF-8 format.
public enum ChartTextCodec {
    public struct Decoded: Sendable {
        public let text: String
        public let encoding: String
    }
    public enum Failure: LocalizedError {
        case invalid(String)
        public var errorDescription: String? {
            switch self {
            case .invalid(let encoding): "谱面不是有效的 \(encoding) 文本。请将 maidata.txt 转为 UTF-8 后重新打开；不会猜测编码或替换损坏字符。"
            }
        }
    }
    public static func decode(_ data: Data) throws -> Decoded {
        // UTF-32LE shares its first two bytes with UTF-16LE, so check it first.
        let formats: [(bom: [UInt8], encoding: String.Encoding, label: String, unit: Int)] = [
            ([0xFF, 0xFE, 0, 0], .utf32LittleEndian, "UTF-32LE", 4),
            ([0, 0, 0xFE, 0xFF], .utf32BigEndian, "UTF-32BE", 4),
            ([0xFF, 0xFE], .utf16LittleEndian, "UTF-16LE", 2),
            ([0xFE, 0xFF], .utf16BigEndian, "UTF-16BE", 2),
            ([0xEF, 0xBB, 0xBF], .utf8, "UTF-8 BOM", 1)
        ]
        for format in formats where data.starts(with: format.bom) {
            let payload = data.dropFirst(format.bom.count)
            guard payload.count % format.unit == 0, let text = String(data: payload, encoding: format.encoding),
                  text.data(using: format.encoding) == payload, !text.contains("\0") else {
                throw Failure.invalid(format.label)
            }
            return Decoded(text: text, encoding: format.label)
        }
        guard let text = String(data: data, encoding: .utf8), !data.contains(0) else { throw Failure.invalid("UTF-8") }
        return Decoded(text: text, encoding: "UTF-8")
    }
}
