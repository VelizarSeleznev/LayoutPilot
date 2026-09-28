import XCTest
@testable import LayoutPilotCore

final class DictationGestureTests: XCTestCase {
    func testExternalDictationKeepsShortFnTapsButNeverLaunchesVibeRead() {
        var machine = DictationGestureMachine(dictationEnabled: false)
        XCTAssertEqual(machine.handleFn(isDown: true, at: 1), [])
        XCTAssertEqual(machine.handleFn(isDown: false, at: 1.1), [.switchLayout])
        XCTAssertEqual(machine.handleFn(isDown: true, at: 1.2), [])
        XCTAssertEqual(machine.handleFn(isDown: false, at: 1.3), [.switchLayout])
        XCTAssertEqual(machine.handleFn(isDown: true, at: 2), [])
        XCTAssertEqual(machine.handleFn(isDown: false, at: 3), [])
        for time in [4.0, 4.2] {
            XCTAssertEqual(machine.handleOption(keyCode: 58, isDown: true, isAlone: true, at: time), [])
            XCTAssertEqual(machine.handleOption(keyCode: 58, isDown: false, isAlone: true, at: time + 0.1), [])
        }
    }

    func testExternalHoldWaitsAndReleasesWithoutSwitchingLayout() {
        var machine = DictationGestureMachine(dictationEnabled: false, externalHoldEnabled: true)
        let token = holdToken(from: machine.handleFn(isDown: true, at: 10))
        XCTAssertEqual(machine.holdFired(token: token, at: 10.2), [])
        XCTAssertEqual(machine.holdFired(token: token, at: 10.35), [.command(.holdStart)])
        XCTAssertEqual(machine.handleFn(isDown: false, at: 11), [.command(.holdStop)])
    }

    func testExternalShortTapCancelsPendingDictation() {
        var machine = DictationGestureMachine(dictationEnabled: false, externalHoldEnabled: true)
        let token = holdToken(from: machine.handleFn(isDown: true, at: 10))
        XCTAssertEqual(machine.handleFn(isDown: false, at: 10.1), [.switchLayout])
        XCTAssertEqual(machine.holdFired(token: token, at: 10.4), [])
    }

    func testSingleFnSwitchesOnReleaseWithoutDictation() {
        var machine = DictationGestureMachine()

        let down = machine.handleFn(isDown: true, at: 10)
        XCTAssertEqual(down, [.armHold(holdToken(from: down))])
        let up = machine.handleFn(isDown: false, at: 10.12)
        XCTAssertEqual(up, [.switchLayout])
        XCTAssertTrue(machine.holdFired(token: holdToken(from: down), at: 10.4).isEmpty)
    }

    func testHoldFnDictatesUntilReleaseAndDoesNotSwitchLayout() {
        var machine = DictationGestureMachine()
        let down = machine.handleFn(isDown: true, at: 5)
        let token = holdToken(from: down)

        XCTAssertEqual(
            machine.holdFired(token: token, at: 5.34),
            [.command(.holdStart)]
        )
        XCTAssertEqual(
            machine.handleFn(isDown: false, at: 6.1),
            [.command(.holdStop)]
        )
    }

    func testDoubleFnRevertsTheLayoutAndTogglesDictation() {
        var machine = DictationGestureMachine()
        _ = machine.handleFn(isDown: true, at: 1)
        XCTAssertEqual(machine.handleFn(isDown: false, at: 1.08), [.switchLayout])

        XCTAssertEqual(
            machine.handleFn(isDown: true, at: 1.28),
            [.revertLayout, .command(.toggle)]
        )
        XCTAssertEqual(machine.handleFn(isDown: false, at: 1.36), [])
    }

    func testSlowSecondFnSwitchesAgainInsteadOfDictating() {
        var machine = DictationGestureMachine()
        _ = machine.handleFn(isDown: true, at: 1)
        _ = machine.handleFn(isDown: false, at: 1.1)
        let second = machine.handleFn(isDown: true, at: 1.6)
        XCTAssertEqual(second.count, 1)
        if case .armHold = second[0] {} else {
            XCTFail("expected a new hold arm, got \(second)")
        }
        XCTAssertEqual(machine.handleFn(isDown: false, at: 1.7), [.switchLayout])
    }

    func testDoubleOptionTogglesAndConsumesOnlyTheSecondTap() {
        var machine = DictationGestureMachine()
        XCTAssertEqual(machine.handleOption(keyCode: 58, isDown: true, isAlone: true, at: 2), [])
        XCTAssertEqual(machine.handleOption(keyCode: 58, isDown: false, isAlone: true, at: 2.08), [])
        XCTAssertEqual(
            machine.handleOption(keyCode: 61, isDown: true, isAlone: true, at: 2.25),
            [.command(.toggle), .consume]
        )
        XCTAssertEqual(
            machine.handleOption(keyCode: 61, isDown: false, isAlone: true, at: 2.32),
            [.consume]
        )
    }

    func testOptionChordDoesNotDictate() {
        var machine = DictationGestureMachine()
        _ = machine.handleOption(keyCode: 58, isDown: true, isAlone: true, at: 3)
        machine.foreignKey()
        XCTAssertEqual(machine.handleOption(keyCode: 58, isDown: false, isAlone: false, at: 3.1), [])
        XCTAssertEqual(machine.handleOption(keyCode: 58, isDown: true, isAlone: true, at: 3.2), [])
    }

    private func holdToken(from effects: [DictationGestureEffect]) -> UUID {
        for effect in effects {
            if case .armHold(let token) = effect { return token }
        }
        XCTFail("missing hold token")
        return UUID()
    }
}
