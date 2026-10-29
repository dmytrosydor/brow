import BrowShared
import Foundation

// brow-hook: a Claude Code command hook that forwards the event to brow.
// It must never get in Claude's way: if brow is not running, or anything
// goes wrong, it exits 0 at once and prints nothing.

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let event = try? JSONSerialization.jsonObject(with: input) else { exit(0) }

let env = ProcessInfo.processInfo.environment
let keys = ["CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_HOST_SESSION_ID", "TERM_PROGRAM"]
let payload: [String: Any] = [
    "event": event,
    "env": keys.reduce(into: [String: String]()) { $0[$1] = env[$1] },
]
guard var data = try? JSONSerialization.data(withJSONObject: payload) else { exit(0) }
data.append(0x0A)

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0, var addr = BrowSocket.address(BrowSocket.path) else { exit(0) }
BrowSocket.setTimeouts(fd, seconds: 1)
let connected = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
if connected == 0 {
    data.withUnsafeBytes { raw in
        var sent = 0
        while sent < raw.count {
            let n = write(fd, raw.baseAddress! + sent, raw.count - sent)
            if n <= 0 { break }
            sent += n
        }
    }
}
close(fd)
exit(0)
