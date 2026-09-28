import CoreGraphics
@testable import LayoutPilotCore
import XCTest

final class AgentPromptTrackerTests: XCTestCase {
    private let us: Set<String> = ["com.apple.keylayout.US", "com.apple.keylayout.ABC"]
    private let russian = "com.apple.keylayout.RussianWin"

    private func press(
        _ tracker: inout AgentPromptTracker,
        keyCode: Int64,
        flags: CGEventFlags = [],
        text: String?,
        pane: String = "w1:p1",
        sourceID: String? = nil
    ) -> AgentPromptTracker.Action {
        let key = AgentPromptTracker.classify(keyCode: keyCode, flags: flags, text: text)
        return tracker.handle(
            key,
            keyCode: keyCode,
            flags: flags,
            paneID: pane,
            sourceID: sourceID ?? russian,
            usSourceIDs: us
        )
    }

    private func submit(_ tracker: inout AgentPromptTracker, pane: String = "w1:p1") {
        XCTAssertEqual(press(&tracker, keyCode: 36, text: "\r", pane: pane), .none)
    }

    private func slashKey(_ tracker: inout AgentPromptTracker, pane: String = "w1:p1", sourceID: String? = nil) -> AgentPromptTracker.Action {
        press(&tracker, keyCode: AgentPromptTracker.slashKeyCode, text: ".", pane: pane, sourceID: sourceID)
    }

    func testSlashNeedsAPromptKnownToBeEmpty() {
        var tracker = AgentPromptTracker()
        XCTAssertEqual(slashKey(&tracker), .none, "a pane never seen submitting may hold a draft")

        submit(&tracker)
        XCTAssertEqual(slashKey(&tracker), .insertSlash)
    }

    func testCommandWordEndsAtFirstSpaceAndRestoresPaneLayout() {
        var tracker = AgentPromptTracker()
        submit(&tracker)
        XCTAssertEqual(slashKey(&tracker), .insertSlash)
        for (keyCode, text) in [(11 as Int64, "b"), (17, "t"), (13, "w")] {
            XCTAssertEqual(press(&tracker, keyCode: keyCode, text: text, sourceID: "com.apple.keylayout.US"), .none)
        }
        XCTAssertEqual(press(&tracker, keyCode: 49, text: " "), .restoreLayout(sourceID: russian))
        XCTAssertEqual(press(&tracker, keyCode: 49, text: " "), .none, "restores once")
        XCTAssertEqual(tracker.state(for: "w1:p1"), .typed(count: 6))
    }

    func testSubmittingABareCommandRestoresPaneLayout() {
        var tracker = AgentPromptTracker()
        submit(&tracker)
        XCTAssertEqual(slashKey(&tracker), .insertSlash)
        XCTAssertEqual(press(&tracker, keyCode: 36, text: "\r"), .restoreLayout(sourceID: russian))
        XCTAssertEqual(tracker.state(for: "w1:p1"), .empty)
    }

    func testDeletingTheSlashRestoresPaneLayout() {
        var tracker = AgentPromptTracker()
        submit(&tracker)
        XCTAssertEqual(slashKey(&tracker), .insertSlash)
        XCTAssertEqual(press(&tracker, keyCode: 51, text: "\u{8}"), .restoreLayout(sourceID: russian))
        XCTAssertEqual(slashKey(&tracker), .insertSlash, "the prompt is empty again")
    }

    func testPeriodInsideAPromptStaysAPeriod() {
        var tracker = AgentPromptTracker()
        submit(&tracker)
        XCTAssertEqual(press(&tracker, keyCode: 15, text: "к"), .none)
        XCTAssertEqual(slashKey(&tracker), .none)

        XCTAssertEqual(press(&tracker, keyCode: 51, text: "\u{8}"), .none)
        XCTAssertEqual(press(&tracker, keyCode: 51, text: "\u{8}"), .none)
        XCTAssertEqual(slashKey(&tracker), .insertSlash, "backspacing to empty re-enables the slash")
    }

    func testEditsTheTrackerCannotFollowKeepThePeriod() {
        let untrackable: [(Int64, CGEventFlags)] = [
            (9, .maskCommand),    // paste
            (126, []),            // history recall
            (36, .maskShift),     // newline in the prompt
            (51, .maskAlternate), // delete word
            (13, .maskControl),   // Control-W
        ]
        for (keyCode, flags) in untrackable {
            var tracker = AgentPromptTracker()
            submit(&tracker)
            XCTAssertEqual(press(&tracker, keyCode: keyCode, flags: flags, text: nil), .none)
            XCTAssertEqual(slashKey(&tracker), .none, "keyCode \(keyCode)")
        }
    }

    func testShortcutsThatLeaveThePromptAloneKeepItEmpty() {
        let harmless: [(Int64, CGEventFlags)] = [
            (8, .maskCommand),  // copy
            (48, .maskCommand), // Command-Tab
            (53, []),           // Escape
            (116, []),          // Page Up
        ]
        var tracker = AgentPromptTracker()
        submit(&tracker)
        for (keyCode, flags) in harmless {
            XCTAssertEqual(press(&tracker, keyCode: keyCode, flags: flags, text: nil), .none)
        }
        XCTAssertEqual(slashKey(&tracker), .insertSlash)
    }

    func testInterruptAndClearLineEmptyThePrompt() {
        var tracker = AgentPromptTracker()
        submit(&tracker)
        _ = press(&tracker, keyCode: 15, text: "к")
        XCTAssertEqual(press(&tracker, keyCode: 8, flags: .maskControl, text: "\u{3}"), .none)
        XCTAssertEqual(slashKey(&tracker), .insertSlash)

        var cleared = AgentPromptTracker()
        submit(&cleared)
        _ = press(&cleared, keyCode: 15, text: "к")
        XCTAssertEqual(press(&cleared, keyCode: 51, flags: .maskCommand, text: nil), .none)
        XCTAssertEqual(slashKey(&cleared), .insertSlash)
    }

    func testKeyAfterHerdrPrefixIsAHerdrCommandNotPromptText() {
        var tracker = AgentPromptTracker()
        submit(&tracker)
        XCTAssertEqual(press(&tracker, keyCode: 11, flags: .maskControl, text: "\u{2}"), .none)
        XCTAssertEqual(press(&tracker, keyCode: 37, text: "l"), .none)
        XCTAssertEqual(slashKey(&tracker), .insertSlash)
    }

    func testSlashIsLeftAloneOnUSOrWithModifiers() {
        var tracker = AgentPromptTracker()
        submit(&tracker)
        XCTAssertEqual(slashKey(&tracker, sourceID: "com.apple.keylayout.US"), .none)

        var shifted = AgentPromptTracker()
        submit(&shifted)
        XCTAssertEqual(press(&shifted, keyCode: AgentPromptTracker.slashKeyCode, flags: .maskShift, text: ","), .none)
    }

    func testPanesAreTrackedIndependently() {
        var tracker = AgentPromptTracker()
        submit(&tracker, pane: "w1:p1")
        XCTAssertEqual(slashKey(&tracker, pane: "w1:p2"), .none)
        XCTAssertEqual(slashKey(&tracker, pane: "w1:p1"), .insertSlash)
    }

    func testFocusChangeCancelsPendingRestore() {
        var tracker = AgentPromptTracker()
        submit(&tracker)
        XCTAssertEqual(slashKey(&tracker), .insertSlash)
        tracker.focusChanged()
        XCTAssertEqual(press(&tracker, keyCode: 49, text: " "), .none)
    }
}

final class HerdrProtocolTests: XCTestCase {
    private func line(_ string: String) -> Data { Data(string.utf8) }

    func testParsesEventsThatChangeFocusOrAgents() {
        XCTAssertEqual(
            HerdrProtocol.parseEventLine(line(#"{"data":{"pane_id":"w1:p2","type":"pane_focused","workspace_id":"w1"},"event":"pane_focused"}"#)),
            .paneFocused(paneID: "w1:p2")
        )
        XCTAssertEqual(
            HerdrProtocol.parseEventLine(line(#"{"data":{"agent":"omp","pane_id":"w1:p2","type":"pane_agent_detected","workspace_id":"w1"},"event":"pane_agent_detected"}"#)),
            .agentChanged(paneID: "w1:p2", agent: "omp")
        )
        XCTAssertEqual(
            HerdrProtocol.parseEventLine(line(#"{"data":{"final_status":"unknown","pane_id":"w1:p2","released":true,"type":"pane_agent_detected","workspace_id":"w1"},"event":"pane_agent_detected"}"#)),
            .agentChanged(paneID: "w1:p2", agent: nil)
        )
        XCTAssertEqual(
            HerdrProtocol.parseEventLine(line(#"{"data":{"pane_id":"w1:p3","type":"pane_closed","workspace_id":"w1"},"event":"pane_closed"}"#)),
            .paneRemoved(paneID: "w1:p3")
        )
        XCTAssertNil(HerdrProtocol.parseEventLine(line(#"{"data":{"tab_id":"w1:t1","type":"tab_focused","workspace_id":"w1"},"event":"tab_focused"}"#)))
        XCTAssertTrue(HerdrProtocol.isSubscriptionStarted(line(#"{"id":"s","result":{"type":"subscription_started"}}"#)))
        XCTAssertFalse(HerdrProtocol.isSubscriptionStarted(line(#"{"id":"","error":{"code":"invalid_request","message":"missing field"}}"#)))
    }

    func testSessionStateFollowsFocusAgentsAndClosedPanes() throws {
        let list = try XCTUnwrap(HerdrProtocol.parsePaneList(line(
            #"{"id":"r","result":{"type":"pane_list","panes":[{"pane_id":"w1:p1","focused":true,"agent":"claude","agent_status":"working"},{"pane_id":"w1:p2","focused":false,"agent_status":"unknown"}]}}"#
        )))
        var state = HerdrSessionState()
        state.apply(.panesListed(list))
        XCTAssertEqual(state.focusedPane?.paneID, "w1:p1")
        XCTAssertEqual(state.focusedPane?.agent, "claude")

        state.apply(.paneFocused(paneID: "w1:p2"))
        XCTAssertEqual(state.focusedPane?.paneID, "w1:p2")
        XCTAssertNil(state.focusedPane?.agent, "a plain shell")

        state.apply(.agentChanged(paneID: "w1:p2", agent: "omp"))
        XCTAssertEqual(state.focusedPane?.agent, "omp")
        state.apply(.agentChanged(paneID: "w1:p2", agent: nil))
        XCTAssertNil(state.focusedPane?.agent, "the agent exited")

        state.apply(.paneRemoved(paneID: "w1:p2"))
        XCTAssertNil(state.focusedPane)
    }
}

final class HerdrWindowTitleTests: XCTestCase {
    func testDefaultTemplateRecognizesHerdrWindowsOnThisHostOnly() throws {
        let matcher = try XCTUnwrap(HerdrWindowTitleMatcher(
            template: HerdrWindowTitleMatcher.defaultTemplate,
            hostname: "izarlion.local"
        ))
        XCTAssertTrue(matcher.matches("izarlion.local: SummerEngineWorkspace"))
        XCTAssertTrue(matcher.matches("izarlion.local: ~"))
        XCTAssertFalse(matcher.matches("~/Projects — zsh"))
        XCTAssertFalse(matcher.matches("velizard@izarlion: ~"), "zsh's user@host title")
        XCTAssertFalse(matcher.matches("other.local: SummerEngineWorkspace"))
        XCTAssertFalse(matcher.matches("izarlionXlocal: ws"), "the host name is not a pattern")
    }

    func testCustomTemplatesKeepLiteralTextAndBraces() throws {
        let matcher = try XCTUnwrap(HerdrWindowTitleMatcher(template: "herdr {{{tab}}} · {pane}", hostname: "h"))
        XCTAssertTrue(matcher.matches("herdr {t1} · shell"))
        XCTAssertFalse(matcher.matches("herdr t1 · shell"))
        XCTAssertFalse(matcher.matches("zsh"))
    }

    func testTemplatesThatCannotIdentifyHerdrMatchNothing() {
        XCTAssertNil(HerdrWindowTitleMatcher(template: "", hostname: "h"), "herdr leaves the title alone")
        XCTAssertNil(HerdrWindowTitleMatcher(template: "{workspace}", hostname: "h"), "any title would match")
        XCTAssertNil(HerdrWindowTitleMatcher(template: "{workspace} {terminal_title}", hostname: "h"))
    }

    func testReadsWindowTitleFromTheUITableOnly() {
        XCTAssertEqual(HerdrConfig.windowTitle(inTOML: "[ui]\naccent = \"#c4a7e7\"\n"), .unset)
        XCTAssertEqual(
            HerdrConfig.windowTitle(inTOML: "[ui]\nwindow_title = \"herdr \\u00B7 {workspace}\" # set\n"),
            .template("herdr · {workspace}")
        )
        XCTAssertEqual(HerdrConfig.windowTitle(inTOML: "[ui]\nwindow_title = ''\n"), .template(""))
        XCTAssertEqual(
            HerdrConfig.windowTitle(inTOML: "[theme]\nwindow_title = \"x\"\n[[keys.command]]\nwindow_title = \"y\"\n"),
            .unset
        )
        XCTAssertEqual(HerdrConfig.windowTitle(inTOML: "[ui]\nwindow_title_extra = \"x\"\n"), .unset)
        XCTAssertEqual(HerdrConfig.windowTitle(inTOML: "[ui]\nwindow_title = \"\"\"\nx\"\"\"\n"), .unreadable)
    }
}

final class HerdrAgentPaneExclusionTests: XCTestCase {
    func testAgentPaneIsNotATerminalButShellPaneStaysExcluded() {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("learning.json")
        let service = SmartInputService(learningStore: SmartInputLearningStore(fileURL: storeURL))
        let ghostty = "com.mitchellh.ghostty"
        let agentPane = SmartInputService.InputContextSnapshot(
            bundleID: ghostty,
            focusedElementKind: .text,
            terminalPane: TerminalPaneFocus(hostBundleID: ghostty, paneID: "w1:p1", agent: "omp")
        )
        XCTAssertTrue(service.shouldCaptureTraceText(in: agentPane))

        var shellPane = agentPane
        shellPane.terminalPane?.agent = nil
        XCTAssertFalse(service.shouldCaptureTraceText(in: shellPane))

        var otherTerminal = agentPane
        otherTerminal.bundleID = "com.apple.Terminal"
        XCTAssertFalse(service.shouldCaptureTraceText(in: otherTerminal), "a pane of a terminal no longer in front")
    }
}
