import Foundation

/// Where brow listens for hook events: one newline-terminated JSON object per connection.
public enum BrowSocket {
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("brow", isDirectory: true)
    }

    public static var path: String { directory.appendingPathComponent("brow.sock").path }

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
}
