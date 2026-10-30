import BrowShared
import XCTest
@testable import Brow

/// Hook events in the shape Claude Code sends them, checked against live logs.
/// If Claude's format changes, these document what brow relies on.
final class LiveEventsTests: XCTestCase {
    private var store: SessionStore!
    private var openFDs: [Int32] = []

    override func setUp() {
        store = SessionStore(sessions: [])
    }

    override func tearDown() {
        store.releaseAll()
        openFDs.forEach { close($0) }
        openFDs = []
    }

    /// Feeds one event in; returns the socket end the hook would read its answer from.
    @discardableResult
    private func send(_ event: [String: Any], entrypoint: String = "cli") -> Int32 {
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds), 0)
        var on: Int32 = 1
        setsockopt(fds[0], SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        BrowSocket.setTimeouts(fds[1], seconds: 1)
        openFDs.append(fds[1])
        store.apply(["event": event, "env": ["CLAUDE_CODE_ENTRYPOINT": entrypoint]], responder: Responder(fd: fds[0]))
        return fds[1]
    }

    private func answer(_ fd: Int32) throws -> [String: Any] {
        let line = try XCTUnwrap(BrowSocket.readLine(fd))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any])
    }

    private func decision(_ output: [String: Any]) throws -> [String: Any] {
        let specific = try XCTUnwrap(output["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(specific["hookEventName"] as? String, "PermissionRequest")
        return try XCTUnwrap(specific["decision"] as? [String: Any])
    }

    private func stop(_ id: String = "s", message: String = "Done") -> [String: Any] {
        ["session_id": id, "hook_event_name": "Stop", "cwd": "/tmp/project", "last_assistant_message": message]
    }

    private func permission(_ id: String = "s", command: String = "npm test") -> [String: Any] {
        ["session_id": id, "hook_event_name": "PermissionRequest", "cwd": "/tmp/project", "tool_name": "Bash",
         "tool_input": ["command": command]]
    }

    private func question(_ id: String = "s") -> [String: Any] {
        ["session_id": id, "hook_event_name": "PermissionRequest", "cwd": "/tmp/project", "tool_name": "AskUserQuestion",
         "tool_input": ["questions": [["question": "Color?", "header": "C", "multiSelect": false,
                                       "options": [["label": "Blue", "description": "b"], ["label": "Green", "description": "g"]]]]]]
    }

    // MARK: Sessions

    func testNewSessionTakesProjectFromFolderAndTitleFromPrompt() {
        send(["session_id": "s", "hook_event_name": "UserPromptSubmit", "cwd": "/work/api-server", "prompt": "Fix login\nand tests"])
        let session = store.sessions[0]
        XCTAssertEqual(session.project, "api-server")
        XCTAssertEqual(session.title, "Fix login")
        XCTAssertEqual(session.state, .working)
        XCTAssertEqual(session.client, .terminal)
    }

    func testDesktopEntrypointIsRecognized() {
        send(["session_id": "s", "hook_event_name": "SessionStart", "cwd": "/w/a"], entrypoint: "claude-desktop")
        XCTAssertEqual(store.sessions[0].client, .desktop)
    }

    func testSessionEndRemovesSessionAndLetsItsHookGo() throws {
        let fd = send(stop())
        send(["session_id": "s", "hook_event_name": "SessionEnd"])
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertEqual(try answer(fd).count, 0)
    }

    func testToolCallsShowActivityWithoutReorderingTheList() {
        send(["session_id": "a", "hook_event_name": "UserPromptSubmit", "cwd": "/w/a"])
        send(["session_id": "b", "hook_event_name": "UserPromptSubmit", "cwd": "/w/b"])
        send(["session_id": "a", "hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": ["command": "make"]])
        XCTAssertEqual(store.sessions[0].id, "b")
        XCTAssertEqual(store.sessions[1].activity?.detail, "make")
        XCTAssertEqual(store.sessions[1].state, .working)
    }

    func testLongSilenceGraysOutThenAnEventRevives() {
        send(["session_id": "s", "hook_event_name": "UserPromptSubmit", "cwd": "/w/a"])
        store.sweep(now: .now.addingTimeInterval(31 * 60))
        XCTAssertTrue(store.sessions[0].stale)
        send(["session_id": "s", "hook_event_name": "PostToolUse", "tool_name": "Bash", "tool_input": [:]])
        XCTAssertFalse(store.sessions[0].stale)
    }

    func testVeryOldSessionsGoUnlessMessagesAreQueued() {
        send(["session_id": "old", "hook_event_name": "UserPromptSubmit", "cwd": "/w/a"])
        send(["session_id": "queued", "hook_event_name": "UserPromptSubmit", "cwd": "/w/b"])
        store.enqueue("next", for: store.sessions.first { $0.id == "queued" }!)
        store.sweep(now: .now.addingTimeInterval(7 * 3600))
        XCTAssertEqual(store.sessions.map(\.id), ["queued"])
    }

    // MARK: Replies

    func testStopIsHeldAndAReplyBlocksIt() throws {
        let fd = send(stop(message: "All done"))
        XCTAssertNotNil(store.holds["s"])
        XCTAssertEqual(store.sessions[0].state, .waiting)
        XCTAssertEqual(store.sessions[0].lastMessage, "All done")

        store.send("add tests", to: store.sessions[0])
        let output = try answer(fd)
        XCTAssertEqual(output["decision"] as? String, "block")
        let reason = try XCTUnwrap(output["reason"] as? String)
        XCTAssertTrue(reason.hasSuffix("add tests"))
        XCTAssertTrue(reason.contains("user"), "Claude must be told the reply is from the user")
        XCTAssertEqual(store.sessions[0].state, .working)
    }

    func testReleasedStopPrintsNothingAndIsDone() throws {
        let fd = send(stop())
        store.release("s")
        XCTAssertEqual(try answer(fd).count, 0)
        XCTAssertEqual(store.sessions[0].state, .done)
    }

    func testTypingInTheAppLetsAHeldStopGo() throws {
        let fd = send(stop())
        send(["session_id": "s", "hook_event_name": "UserPromptSubmit", "cwd": "/tmp/project"])
        XCTAssertEqual(try answer(fd).count, 0)
    }

    func testOtherEventsAreAnsweredAtOnce() throws {
        let fd = send(["session_id": "s", "hook_event_name": "SessionStart", "cwd": "/w/a"])
        XCTAssertEqual(try answer(fd).count, 0)
    }

    func testHoldingOffStillTracksTheSession() throws {
        store.prefs.holdReplies = false
        defer { store.prefs.holdReplies = true }
        let fd = send(stop())
        XCTAssertEqual(try answer(fd).count, 0)
        XCTAssertEqual(store.sessions[0].state, .done)
    }

    func testStopOfferingACommandFindsIt() {
        send(stop(message: "Now run:\n\n```bash\ngit push origin main\n```\n"))
        XCTAssertEqual(store.sessions[0].command, "git push origin main")
    }

    func testWrapUpButtonsSkipAppOnlyActions() {
        send(["session_id": "s", "hook_event_name": "PreToolUse", "tool_name": "mcp__ccd_turn__wrap_up", "cwd": "/w",
              "tool_input": ["recap": "r", "ask": "Fix it?",
                             "actions": [["label": "Yes", "message": "Yes, fix"], ["label": "Short"], ["action": "commit"]]]])
        let wrapUp = store.sessions[0].wrapUp
        XCTAssertEqual(wrapUp?.actions, [WrapAction(label: "Yes", message: "Yes, fix"), WrapAction(label: "Short", message: "Short")])
        XCTAssertEqual(wrapUp?.ask, "Fix it?")
    }

    // MARK: Questions

    func testQuestionAnswerKeepsInputAndAddsAnswers() throws {
        let fd = send(question())
        XCTAssertEqual(store.sessions[0].questions.first?.options.map(\.label), ["Blue", "Green"])
        store.answer(["Color?": "Green"], to: store.sessions[0])
        let decision = try decision(try answer(fd))
        XCTAssertEqual(decision["behavior"] as? String, "allow")
        let input = try XCTUnwrap(decision["updatedInput"] as? [String: Any])
        XCTAssertEqual(input["answers"] as? [String: String], ["Color?": "Green"])
        XCTAssertNotNil(input["questions"])
    }

    func testQuestionAnsweredInTheAppLetsTheHookGo() throws {
        let fd = send(question())
        send(["session_id": "s", "hook_event_name": "PostToolUse", "tool_name": "AskUserQuestion", "tool_input": [:]])
        XCTAssertEqual(try answer(fd).count, 0)
        XCTAssertTrue(store.sessions[0].questions.isEmpty)
    }

    // MARK: Permissions

    func testAllowAndDeny() throws {
        let allowFD = send(permission("a"))
        XCTAssertEqual(store.sessions[0].permission?.detail, "npm test")
        store.decide(allow: true, session: store.sessions[0])
        XCTAssertEqual(try decision(try answer(allowFD))["behavior"] as? String, "allow")

        let denyFD = send(permission("d"))
        store.send("too risky", to: store.sessions.first { $0.id == "d" }!)
        let denied = try decision(try answer(denyFD))
        XCTAssertEqual(denied["behavior"] as? String, "deny")
        XCTAssertEqual(denied["message"] as? String, "too risky")
    }

    func testParallelPermissionsComeOneAtATime() throws {
        let first = send(permission(command: "one"))
        let second = send(permission(command: "two"))
        XCTAssertEqual(store.sessions[0].permission?.detail, "one")
        store.decide(allow: true, session: store.sessions[0])
        XCTAssertEqual(try decision(try answer(first))["behavior"] as? String, "allow")
        XCTAssertEqual(store.sessions[0].permission?.detail, "two")
        XCTAssertEqual(store.sessions[0].state, .waiting)
        store.decide(allow: false, session: store.sessions[0])
        XCTAssertEqual(try decision(try answer(second))["behavior"] as? String, "deny")
    }

    func testPermissionGivenInTheAppSettlesTheCard() throws {
        let fd = send(permission(command: "one"))
        send(["session_id": "s", "hook_event_name": "PostToolUse", "tool_name": "Bash", "tool_input": ["command": "one"]])
        XCTAssertEqual(try answer(fd).count, 0)
        XCTAssertNil(store.sessions[0].permission)
        XCTAssertEqual(store.sessions[0].state, .working)
    }

    func testAnotherToolFinishingLeavesThePermissionOpen() {
        send(permission(command: "one"))
        send(["session_id": "s", "hook_event_name": "PostToolUse", "tool_name": "Bash", "tool_input": ["command": "other"]])
        XCTAssertEqual(store.sessions[0].permission?.detail, "one")
        XCTAssertEqual(store.sessions[0].state, .waiting)
    }

    func testIdleNoticeClearsARefusedPermissionButAPromptNoticeDoesNot() throws {
        let fd = send(permission())
        send(["session_id": "s", "hook_event_name": "Notification", "notification_type": "permission_prompt", "message": "m"])
        XCTAssertNotNil(store.sessions[0].permission)
        send(["session_id": "s", "hook_event_name": "Notification", "notification_type": "idle_prompt", "message": "m"])
        XCTAssertNil(store.sessions[0].permission)
        XCTAssertEqual(try answer(fd).count, 0)
    }

    func testAKeyNeverApprovesAPermissionByAccident() throws {
        send(permission())
        store.expanded = true
        store.selectedID = "s"
        _ = store.handle(.digit(1))
        _ = store.handle(.enter)
        XCTAssertNotNil(store.holds["s"], "digits and Enter must not answer a permission")
        _ = store.handle(.commandEnter)
        XCTAssertNil(store.holds["s"])
    }

    // MARK: Queue

    func testQueueGoesOutTogetherAtStop() throws {
        send(["session_id": "s", "hook_event_name": "UserPromptSubmit", "cwd": "/w/a"])
        store.enqueue("first", for: store.sessions[0])
        store.enqueue("second", for: store.sessions[0])
        store.enqueue("", for: store.sessions[0])
        let fd = send(stop())
        let output = try answer(fd)
        XCTAssertEqual(output["decision"] as? String, "block")
        XCTAssertTrue(try XCTUnwrap(output["reason"] as? String).hasSuffix("first\n\nsecond"))
        XCTAssertTrue(store.sessions[0].queued.isEmpty)
        XCTAssertEqual(store.sessions[0].state, .working)
    }

    // MARK: Alerts

    func testOneRequestAlertsOnceAndAnotherSessionSumsUp() {
        send(["session_id": "a", "hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion", "cwd": "/w/a",
              "tool_input": question("a")["tool_input"]!])
        XCTAssertEqual(store.peek?.sessionID, "a")
        store.hidePeek()
        send(question("a"))
        XCTAssertNil(store.peek, "the same question must not alert twice")
        send(permission("b"))
        XCTAssertEqual(store.peek?.sessionID, "b")
        send(permission("c"))
        XCTAssertNil(store.peek?.sessionID, "a second session sums up")
    }

    func testAlertsCanBeTurnedOff() {
        store.prefs.peekAlerts = false
        defer { store.prefs.peekAlerts = true }
        send(permission())
        XCTAssertNil(store.peek)
    }
}
