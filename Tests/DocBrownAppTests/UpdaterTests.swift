import Sparkle
import XCTest
@testable import DocBrown

final class UpdaterTests: XCTestCase {
    @MainActor func testScheduledUpdatesNeverRequestFocusEvenAtLaunch() throws {
        let updater = AppUpdater()
        let item = try XCTUnwrap(SUAppcastItem(dictionary: [
            "title": "DocBrown update",
            "enclosure": ["url": "https://example.com/DocBrown.zip", "sparkle:version": "5"]
        ]))
        XCTAssertTrue(updater.supportsGentleScheduledUpdateReminders)
        XCTAssertFalse(updater.standardUserDriverShouldHandleShowingScheduledUpdate(item, andInImmediateFocus: true))
        XCTAssertFalse(updater.standardUserDriverShouldHandleShowingScheduledUpdate(item, andInImmediateFocus: false))
    }
}
