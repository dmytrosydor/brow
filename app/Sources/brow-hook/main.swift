import BrowShared
import Foundation

// brow-hook: a Claude Code command hook that forwards the event to brow.
// For Stop and PermissionRequest it then waits for brow's answer and prints
// it as the hook output, so a reply from the notch reaches Claude.
// It must never get in Claude's way: if brow is not running, or anything
// goes wrong, it exits 0 and prints nothing.

signal(SIGPIPE, SIG_IGN)
let input = FileHandle.standardInput.readDataToEndOfFile()
guard let event = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else { exit(0) }

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
var on: Int32 = 1
setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
BrowSocket.setTimeouts(fd, seconds: 1)
let connected = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard connected == 0, BrowSocket.writeAll(fd, data) else {
    close(fd)
    exit(0)
}

if BrowSocket.waitsForAnswer(event["hook_event_name"] as? String) {
    // brow answers at once when it does not hold the session, otherwise when
    // the user replies or the hold runs out (always before the hook timeout).
    BrowSocket.setTimeouts(fd, seconds: BrowSocket.maxHoldSeconds + 30)
    if let answer = BrowSocket.readLine(fd), !answer.isEmpty, answer != Data("{}".utf8) {
        FileHandle.standardOutput.write(answer)
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}
close(fd)
exit(0)
