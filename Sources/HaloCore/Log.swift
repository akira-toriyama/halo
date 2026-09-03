import Foundation

// Two-channel logger. Lives in Core so every layer calls it without
// crossing the dependency rule (the family shape — perch / glance).
//
//   Log.line(...)   always on  — operational events.
//   Log.debug(...)  gated      — enabled by the HALO_DEBUG env var at
//                                startup (the family <APP>_DEBUG
//                                convention; run.sh sets it, a plain
//                                `open` / brew run stays silent).
//
// Both APPEND a timestamped line to /tmp/halo.log; HALO_DEBUG also
// mirrors to stderr so a foreground run shows events live and
// `2>&1 | tee` captures them. No stored FileHandle: each write opens,
// seeks to the end and closes, so the type holds nothing non-Sendable.
public enum Log {
    public static let path = "/tmp/halo.log"

    /// Read once from the environment; a launch-time constant.
    public static let enabled = ProcessInfo.processInfo.environment["HALO_DEBUG"] != nil

    /// Always-on operational line.
    public static func line(_ s: String) { emit(prefix: "", s) }

    /// Gated by HALO_DEBUG — one bool check when off.
    public static func debug(_ s: String) {
        guard enabled else { return }
        emit(prefix: "[debug] ", s)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private static func emit(prefix: String, _ s: String) {
        let data = Data("\(formatter.string(from: Date())) \(prefix)\(s)\n".utf8)
        if let h = FileHandle(forWritingAtPath: path) {
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
            try? h.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: data)
        }
        if enabled { FileHandle.standardError.write(data) }
    }
}
