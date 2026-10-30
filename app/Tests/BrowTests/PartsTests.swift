import XCTest
@testable import Brow

final class MarkdownTests: XCTestCase {
    func testBlocks() {
        let blocks = MarkdownBlock.parse("# Title\n\nText **bold**\nmore\n\n- item\n1. first\n\n---\n\n```bash\nls\n```")
        XCTAssertEqual(blocks, [.heading("Title"), .paragraph("Text **bold**\nmore"), .bullet("item"),
                                .numbered("1.", "first"), .rule, .code("ls")])
    }

    func testPlainDropsSyntax() {
        XCTAssertEqual(MarkdownBlock.plain("**Bold** and `code`\n\n- item"), "Bold and code item")
    }

    func testUnclosedCodeBlockKeepsItsText() {
        XCTAssertEqual(MarkdownBlock.parse("```\nabc"), [.code("abc")])
    }
}

final class TranscriptUsageTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    private func line(id: String, used: Int, output: Int, model: String = "claude-sonnet-5-5", sidechain: Bool = false) throws -> Data {
        let entry: [String: Any] = ["type": "assistant", "isSidechain": sidechain, "requestedModel": model,
                                    "message": ["id": id, "usage": ["input_tokens": 1, "cache_read_input_tokens": used - 1,
                                                                    "cache_creation_input_tokens": 0, "output_tokens": output]]]
        return try JSONSerialization.data(withJSONObject: entry) + Data([0x0A])
    }

    private func append(_ data: Data) throws {
        let file = try FileHandle(forWritingTo: url)
        try file.seekToEnd()
        try file.write(contentsOf: data)
        try file.close()
    }

    private func read(_ reader: TranscriptUsage, _ id: String = "s") throws -> ContextUsage? {
        var result: ContextUsage?
        var answered = false
        reader.read(session: id, path: url.path) { result = $0; answered = true }
        // A file that cannot be read never calls back.
        let deadline = Date.now.addingTimeInterval(1)
        while !answered, Date.now < deadline { RunLoop.main.run(until: .now.addingTimeInterval(0.02)) }
        return result
    }

    func testUsesTheLastReplyAndCountsEachReplyOnce() throws {
        try append(line(id: "a", used: 100, output: 5))
        try append(line(id: "a", used: 100, output: 7))
        try append(line(id: "b", used: 150_000, output: 3))
        let usage = try XCTUnwrap(read(TranscriptUsage()))
        XCTAssertEqual(usage.used, 150_000)
        XCTAssertEqual(usage.written, 10)
        XCTAssertEqual(usage.window, 200_000)
        XCTAssertEqual(usage.percent, 75)
    }

    func testReadsOnlyWhatIsNewAndWaitsForAHalfWrittenLine() throws {
        let reader = TranscriptUsage()
        try append(line(id: "a", used: 100, output: 1))
        XCTAssertEqual(try read(reader)?.used, 100)
        let next = try line(id: "b", used: 200, output: 1)
        try append(next.prefix(10))
        XCTAssertEqual(try read(reader)?.used, 100)
        try append(next.dropFirst(10))
        XCTAssertEqual(try read(reader)?.used, 200)
        XCTAssertEqual(try read(reader)?.written, 2)
    }

    func testSubagentsDoNotCountAsTheSessionsContext() throws {
        try append(line(id: "a", used: 100, output: 1))
        try append(line(id: "b", used: 900, output: 1, sidechain: true))
        XCTAssertEqual(try read(TranscriptUsage())?.used, 100)
    }

    func testNoFileMeansNoBar() throws {
        try FileManager.default.removeItem(at: url)
        XCTAssertNil(try read(TranscriptUsage()))
    }

    func testWindowGuess() {
        XCTAssertEqual(TranscriptUsage.window(model: "claude-sonnet-5-5", used: 100), 200_000)
        XCTAssertEqual(TranscriptUsage.window(model: "claude-sonnet-5-5", used: 200_001), 1_000_000)
        XCTAssertEqual(TranscriptUsage.window(model: "claude-sonnet-5-5[1m]", used: 100), 1_000_000)
        XCTAssertEqual(TranscriptUsage.window(model: "claude-opus-5-5", used: 100), 1_000_000)
    }
}

final class HookInstallerTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("settings.json")
        setenv("BROW_CLAUDE_SETTINGS", url.path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("BROW_CLAUDE_SETTINGS")
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private func settings() throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func write(_ text: String) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testInstallKeepsEverythingElseAndDoesNotDuplicate() throws {
        try write(#"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say hi"}]}]}}"#)
        HookInstaller.install(ask: false)
        HookInstaller.install(ask: false)
        let result = try settings()
        XCTAssertEqual(result["model"] as? String, "opus")
        let hooks = try XCTUnwrap(result["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), Set(HookInstaller.events.map(\.name)))
        XCTAssertEqual((hooks["Stop"] as? [[String: Any]])?.count, 2)
        XCTAssertTrue(HookInstaller.isInstalled())
        XCTAssertFalse(HookInstaller.isOutdated)
        XCTAssertEqual(HookInstaller.installedHookPath(), HookInstaller.hookPath)
    }

    func testUninstallLeavesOnlyWhatWasThere() throws {
        try write(#"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say hi"}]}]}}"#)
        HookInstaller.install(ask: false)
        HookInstaller.uninstall(ask: false)
        let hooks = try XCTUnwrap(try settings()["hooks"] as? [String: Any])
        XCTAssertEqual(Array(hooks.keys), ["Stop"])
        XCTAssertFalse(HookInstaller.isInstalled())
    }

    func testBackupIsKept() throws {
        try write(#"{"model":"opus"}"#)
        HookInstaller.install(ask: false)
        let files = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        XCTAssertTrue(files.contains { $0.contains("brow-backup") })
    }

    func testBrokenSettingsAreLeftAlone() throws {
        try write("not json")
        HookInstaller.install(ask: false)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "not json")
    }

    func testBarePathHooksCountAsOutdated() throws {
        try write(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"\"/x/brow-hook\""}]}]}}"#)
        XCTAssertTrue(HookInstaller.isOutdated)
        XCTAssertEqual(HookInstaller.installedHookPath(), "/x/brow-hook")
    }

    func testCommandStaysQuietWhenTheHookIsGone() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", HookInstaller.command(for: "/nonexistent/brow-hook")]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(output.fileHandleForReading.readDataToEndOfFile().isEmpty)
    }
}
