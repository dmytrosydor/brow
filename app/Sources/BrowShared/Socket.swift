import Foundation

/// Where brow listens for hook events: one newline-terminated JSON object per
/// connection. For events brow can answer, it writes one line back.
public enum BrowSocket {
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("brow", isDirectory: true)
    }

    public static var path: String { directory.appendingPathComponent("brow.sock").path }

    /// Longest brow may hold a session; the hooks' own timeout must be above it.
    public static let maxHoldSeconds = 30 * 60

    /// Events whose hook waits for brow's answer.
    public static func waitsForAnswer(_ event: String?) -> Bool {
        event == "Stop" || event == "PermissionRequest"
    }

    /// Builds a sockaddr_un for `path`; nil if the path does not fit.
    public static func address(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return addr
    }

    /// Sets send/receive timeouts so neither side can hang on a stuck peer.
    public static func setTimeouts(_ fd: Int32, seconds: Int) {
        var tv = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    public static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let n = write(fd, raw.baseAddress! + sent, raw.count - sent)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }

    /// Reads up to the first newline (not included) or EOF; nil on error or timeout.
    public static func readLine(_ fd: Int32) -> Data? {
        var data = Data()
        var byte: UInt8 = 0
        while true {
            let n = read(fd, &byte, 1)
            if n == 0 { return data }
            if n < 0 { return nil }
            if byte == 0x0A { return data }
            data.append(byte)
        }
    }
}
