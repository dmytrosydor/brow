import BrowShared
import Foundation

/// The open connection of one hook call. brow answers it exactly once: with
/// the hook output that carries a reply, or with `release()` (prints nothing).
final class Responder {
    private let fd: Int32
    private let lock = NSLock()
    private var done = false

    init(fd: Int32) {
        self.fd = fd
    }

    func send(_ output: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: output)) ?? Data("{}".utf8)
        finish(data)
    }

    func release() {
        finish(Data("{}".utf8))
    }

    private func finish(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        _ = BrowSocket.writeAll(fd, data + Data([0x0A]))
        close(fd)
    }

    deinit { release() }
}

/// Listens on the brow socket and hands each received JSON object, with its
/// responder, to `onEvent` on the main queue.
final class EventServer {
    private let onEvent: ([String: Any], Responder) -> Void
    private let queue = DispatchQueue(label: "brow.events")
    private var listener: Int32 = -1
    private var source: DispatchSourceRead?

    init(onEvent: @escaping ([String: Any], Responder) -> Void) {
        self.onEvent = onEvent
    }

    func start() throws {
        try FileManager.default.createDirectory(at: BrowSocket.directory, withIntermediateDirectories: true)
        let path = BrowSocket.path
        unlink(path)

        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0, var addr = BrowSocket.address(path) else { throw POSIXError(.EINVAL) }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        chmod(path, 0o600)
        guard listen(listener, 16) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }

        let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptOne() }
        source.resume()
        self.source = source
    }

    private func acceptOne() {
        let client = accept(listener, nil, nil)
        guard client >= 0 else { return }
        var on: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        BrowSocket.setTimeouts(client, seconds: 2)
        let responder = Responder(fd: client)
        guard let line = BrowSocket.readLine(client),
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            responder.release()
            return
        }
        DispatchQueue.main.async { self.onEvent(object, responder) }
    }
}
