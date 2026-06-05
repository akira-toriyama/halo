import Foundation

// Quiet by default; verbose under the HALO_DEBUG env var — the
// facet-family <APP>_DEBUG convention (dev launcher sets it; a plain
// `open`/brew run stays silent). Always writes /tmp/halo.log; under
// HALO_DEBUG also mirrors to stderr so a foreground run shows events
// live and `2>&1 | tee` captures them.
enum Log {
    static let enabled = ProcessInfo.processInfo.environment["HALO_DEBUG"] != nil

    private static let handle: FileHandle? = {
        let path = "/tmp/halo.log"
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()

    /// Always-on operational line.
    static func line(_ s: String) {
        let data = Data((s + "\n").utf8)
        handle?.write(data)
        if enabled { FileHandle.standardError.write(data) }
    }

    /// Gated by HALO_DEBUG — one bool check when off.
    static func debug(_ s: String) { if enabled { line(s) } }
}
