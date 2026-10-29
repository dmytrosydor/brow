import BrowShared
import Foundation

/// Listens on the brow socket and hands each received JSON object to `onEvent`
/// on the main queue.
final class EventServer {
    private let onEvent: ([String: Any]) -> Void
    private let queue = DispatchQueue(label: "brow.events")
    private var listener: Int32 = -1
    private var source: DispatchSourceRead?

    init(onEvent: @escaping ([String: Any]) -> Void) {
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
        BrowSocket.setTimeouts(client, seconds: 2)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = read(client, &buffer, buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        close(client)

        for line in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            DispatchQueue.main.async { self.onEvent(object) }
        }
    }
}
