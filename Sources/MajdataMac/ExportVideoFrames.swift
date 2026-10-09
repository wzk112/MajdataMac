@preconcurrency import AVFoundation
import CoreImage
import Metal

/// Export advances monotonically. Decode each PV sample once instead of seeking for every frame.
/// The actor keeps decoder work off the UI thread; only two samples and one converted image are retained.
actor ExportVideoFrames {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private let context: CIContext
    private let transform: CGAffineTransform
    private let maximumSize: CGSize
    private let duration: Double
    private var current: CMSampleBuffer?
    private var next: CMSampleBuffer?
    private var image: CGImage?
    private var started = false
    private var lastTime = -Double.infinity

    init(url: URL, startTime: Double, maximumSize: CGSize) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportFailure.failure("背景视频没有视频轨道")
        }
        duration = try await asset.load(.duration).seconds
        let videoTransform = try await track.load(.preferredTransform)
        // Track transforms use top-left coordinates; Core Image uses bottom-left coordinates.
        transform = CGAffineTransform(a: videoTransform.a, b: -videoTransform.b, c: -videoTransform.c,
                                      d: videoTransform.d, tx: videoTransform.tx, ty: -videoTransform.ty)
        self.maximumSize = maximumSize
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else {
            context = CIContext(options: [.cacheIntermediates: false])
        }
        reader = try AVAssetReader(asset: asset)
        output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ExportFailure.failure("无法解码背景视频") }
        reader.add(output)
        // Include the previous source frame at the first export timestamp.
        let start = max(0, min(startTime - 1, max(0, duration - 1)))
        reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 60000), end: CMTime(seconds: duration, preferredTimescale: 60000))
    }

    func frame(at time: Double) throws -> CGImage? {
        try Task.checkCancellation()
        guard time >= lastTime else { throw ExportFailure.failure("背景视频导出时间必须递增") }
        lastTime = time
        guard time >= 0, time < duration else { return nil }
        if !started {
            guard reader.startReading() else { throw reader.error ?? ExportFailure.failure("无法读取背景视频") }
            started = true
            next = output.copyNextSampleBuffer()
        }
        var changed = false
        while let sample = next, sample.presentationTimeStamp.seconds <= time + 0.000001 {
            current = sample
            changed = true
            next = output.copyNextSampleBuffer()
            try Task.checkCancellation()
        }
        if reader.status == .failed { throw reader.error ?? ExportFailure.failure("背景视频解码失败") }
        guard changed || image == nil else { return image }
        guard let current, let buffer = current.imageBuffer else { return nil }
        var source = CIImage(cvPixelBuffer: buffer).transformed(by: transform)
        source = source.transformed(by: CGAffineTransform(translationX: -source.extent.minX, y: -source.extent.minY))
        let scale = min(1, maximumSize.width / source.extent.width, maximumSize.height / source.extent.height)
        source = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        image = context.createCGImage(source, from: source.extent, format: .BGRA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        guard image != nil else { throw ExportFailure.failure("无法转换背景视频帧") }
        return image
    }

    func cancel() {
        if reader.status == .reading { reader.cancelReading() }
        current = nil; next = nil; image = nil
    }
}
