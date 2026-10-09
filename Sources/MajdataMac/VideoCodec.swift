import AVFoundation

enum VideoCodec: String, CaseIterable, Sendable {
    case hevc, h264
    var avCodec: AVVideoCodecType { self == .hevc ? .hevc : .h264 }
    var name: String { self == .hevc ? "HEVC" : "H.264" }
    var title: String { self == .hevc ? "HEVC / H.265 · 较快，适合 Mac" : "H.264 · 兼容性更广" }
}
