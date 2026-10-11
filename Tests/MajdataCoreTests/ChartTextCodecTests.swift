import Testing
import Foundation
@testable import MajdataCore

struct ChartTextCodecTests {
    private let source = "&title=晨光序曲｜中文显示测试\r\n&artist=作曲者 · 简体繁體\r\n&des=谱师「星河」× 日本語 🎵\r\n&inote_5=(120){4}1,2,E\r\n"
    @Test func unicodeEncodingsPreserveMetadataAndSaveAsUTF8() throws {
        let formats: [([UInt8], String.Encoding, String)] = [
            ([], .utf8, "UTF-8"), ([0xEF, 0xBB, 0xBF], .utf8, "UTF-8 BOM"),
            ([0xFF, 0xFE], .utf16LittleEndian, "UTF-16LE"), ([0xFE, 0xFF], .utf16BigEndian, "UTF-16BE"),
            ([0xFF, 0xFE, 0, 0], .utf32LittleEndian, "UTF-32LE"), ([0, 0, 0xFE, 0xFF], .utf32BigEndian, "UTF-32BE")
        ]
        for (bom, encoding, label) in formats {
            let bytes = Data(bom) + (try #require(source.data(using: encoding)))
            let result = try ChartTextCodec.decode(bytes)
            #expect(result.text == source && result.encoding == label)
            let document = ChartDocument(text: result.text)
            #expect(document.title == "晨光序曲｜中文显示测试")
            #expect(document.designer == "谱师「星河」× 日本語 🎵")
            let saved = try ChartTextCodec.decode(Data(document.serialized.utf8))
            #expect(saved.encoding == "UTF-8")
            #expect(ChartDocument(text: saved.text).fields == document.fields)
        }
    }
    @Test func malformedAndUnmarkedLegacyBytesAreRejected() {
        let cases: [[UInt8]] = [[0xE4, 0xB8], [0xD6, 0xD0, 0xCE, 0xC4], [0xFF, 0xFE, 0x41],
                               [0xFF, 0xFE, 0, 0xD8], [0, 0, 0xFE, 0xFF, 0, 0x11, 0, 0], [0x26, 0, 0x74, 0]]
        for bytes in cases {
            #expect(throws: ChartTextCodec.Failure.self) { try ChartTextCodec.decode(Data(bytes)) }
        }
    }
}
