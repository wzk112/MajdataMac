import Foundation

extension Bundle {
    /// A SwiftPM resource bundle copied into an app's `Contents/Resources`.
    /// The accessor SwiftPM generates only looks beside the app and in the folder it was built in,
    /// so a packaged app would otherwise run on the machine that built it and nowhere else.
    public static func packaged(_ name: String) -> Bundle? {
        Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent(name + ".bundle")) }
    }
    static let majdataCore = packaged("MajdataMac_MajdataCore") ?? .module
}
