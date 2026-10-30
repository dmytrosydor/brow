import Foundation

/// How full a session's context is, and how much Claude has written in it.
struct ContextUsage: Equatable {
    var used: Int
    /// A best guess: the transcript does not say how big the window is.
    var window: Int
    var written: Int

    var fraction: Double { min(1, Double(used) / Double(window)) }
    var percent: Int { Int((fraction * 100).rounded()) }

    static func short(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            let millions = Double(tokens) / 1_000_000
            return millions == millions.rounded() ? "\(Int(millions))M" : String(format: "%.1fM", millions)
        }
        return tokens >= 1000 ? "\(tokens / 1000)K" : "\(tokens)"
    }
}

/// Reads token use from a session's transcript (the `transcript_path` of hook
/// events). The format is Claude Code's own and may change; anything that does
/// not parse just leaves the session without a bar.
///
/// Transcripts reach tens of megabytes, so it works off the main thread and
/// reads only what was appended since the last call.
final class TranscriptUsage {
    private struct Progress {
        var offset: UInt64 = 0
        var written: [String: Int] = [:]
        var used = 0
        var model = ""
    }

    private let queue = DispatchQueue(label: "brow.transcripts", qos: .utility)
    private var progress: [String: Progress] = [:]
    private static let usageKey = Data("\"usage\"".utf8)
    /// On a first read, enough for the current context; older totals are skipped.
    private static let firstReadLimit: UInt64 = 128 * 1024 * 1024

    func read(session id: String, path: String, then done: @escaping (ContextUsage) -> Void) {
        queue.async { [self] in
            guard let usage = update(id, path) else { return }
            DispatchQueue.main.async { done(usage) }
        }
    }

    func forget(session id: String) {
        queue.async { [self] in progress[id] = nil }
    }

    private func update(_ id: String, _ path: String) -> ContextUsage? {
        guard let file = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? file.close() }
        var state = progress[id] ?? Progress()
        guard let size = try? file.seekToEnd() else { return nil }
        if size < state.offset { state = Progress() }
        if state.offset == 0, size > Self.firstReadLimit { state.offset = size - Self.firstReadLimit }
        guard (try? file.seek(toOffset: state.offset)) != nil,
              let data = try? file.readToEnd() else { return usage(state) }

        // A last line without a newline is still being written: leave it for next time.
        guard let end = data.lastIndex(of: 0x0A) else { return usage(state) }
        var start = data.startIndex
        while start < end {
            let stop = data[start...end].firstIndex(of: 0x0A) ?? end
            let line = data[start..<stop]
            start = stop + 1
            if line.range(of: Self.usageKey) != nil { parse(line, into: &state) }
        }
        state.offset += UInt64(end - data.startIndex + 1)
        progress[id] = state
        return usage(state)
    }

    private func parse(_ line: Data, into state: inout Progress) {
        guard let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              entry["type"] as? String == "assistant",
              entry["isSidechain"] as? Bool != true,
              let message = entry["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else { return }
        let count: (String) -> Int = { usage[$0] as? Int ?? 0 }
        state.used = count("input_tokens") + count("cache_read_input_tokens") + count("cache_creation_input_tokens")
        // One reply is logged in several lines with the same id.
        if let id = message["id"] as? String { state.written[id] = count("output_tokens") }
        state.model = entry["requestedModel"] as? String ?? message["model"] as? String ?? state.model
    }

    private func usage(_ state: Progress) -> ContextUsage? {
        guard state.used > 0 else { return nil }
        return ContextUsage(used: state.used, window: Self.window(model: state.model, used: state.used),
                            written: state.written.values.reduce(0, +))
    }

    /// The window is not in the transcript, so this reads the signs: an explicit
    /// [1m], use past 200K, or an Opus model, which runs with 1M on the plans seen so far.
    static func window(model: String, used: Int) -> Int {
        let big = model.contains("[1m]") || used > 200_000 || model.contains("opus")
        return big ? 1_000_000 : 200_000
    }
}
