import AppKit
import SwiftUI
import XCTest
@testable import DocBrown

final class QuickSearchTests: XCTestCase {
    @MainActor func testPanelConsumesNavigationAndReturnButPreservesEditingShortcuts() throws {
        _ = NSApplication.shared
        let panel = SearchPanel(contentRect: .zero, styleMask: [.nonactivatingPanel], backing: .buffered, defer: true)
        var steps: [Int] = []
        var opens = 0
        panel.navigate = { steps.append($0) }
        panel.choose = { opens += 1 }
        func event(_ code: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                          timestamp: 0, windowNumber: 0, context: nil,
                                          characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
        }
        XCTAssertTrue(panel.handleSearchKey(try event(125)))
        XCTAssertTrue(panel.handleSearchKey(try event(126)))
        XCTAssertEqual(steps, [1, -1])
        XCTAssertTrue(panel.handleSearchKey(try event(36)))
        XCTAssertEqual(opens, 1)
        XCTAssertFalse(panel.handleSearchKey(try event(125, modifiers: .command)))
        XCTAssertFalse(panel.handleSearchKey(try event(126, modifiers: .shift)))
        XCTAssertFalse(panel.handleSearchKey(try event(0)))
        XCTAssertFalse(panel.isVisible)
    }

    @MainActor func testFieldCommandsMoveSelectionInsteadOfScrolling() {
        var steps: [Int] = []
        var opens = 0
        var dismisses = 0
        let field = QuickSearchField(text: .constant("cache"), focusToken: UUID(),
                                     onNavigate: { steps.append($0) },
                                     onSubmit: { opens += 1 }, onDismiss: { dismisses += 1 })
        let delegate = field.makeCoordinator()
        let control = NSTextField()
        let editor = NSTextView()
        XCTAssertTrue(delegate.control(control, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        XCTAssertTrue(delegate.control(control, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        XCTAssertTrue(delegate.control(control, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:))))
        XCTAssertEqual(steps, [1, 1, -1])
        XCTAssertTrue(delegate.control(control, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(opens, 1)
        XCTAssertTrue(delegate.control(control, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(dismisses, 1)
        XCTAssertFalse(delegate.control(control, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
        XCTAssertFalse(delegate.control(control, textView: editor, doCommandBy: #selector(NSResponder.deleteBackward(_:))))
    }
}
