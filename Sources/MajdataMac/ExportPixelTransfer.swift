import CoreImage
import CoreVideo
import Metal

/// Convert the completed SwiftUI image into the encoder's IOSurface using Metal.
/// Canvas still produces the image; this is not a replacement stage renderer.
final class ExportPixelTransfer {
    private let context: CIContext?
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    init(useMetal: Bool) {
        if useMetal, let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false, .workingColorSpace: NSNull()])
        } else { context = nil }
    }
    func copy(_ image: CGImage, to buffer: CVPixelBuffer) throws {
        let bounds = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        if let context {
            context.render(CIImage(cgImage: image), to: buffer, bounds: bounds, colorSpace: colorSpace)
        } else {
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            guard let destination = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(bounds.width), height: Int(bounds.height),
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue) else {
                throw ExportFailure.failure("无法创建离屏画布")
            }
            destination.draw(image, in: bounds)
        }
    }
}
