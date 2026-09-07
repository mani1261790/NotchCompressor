import CoreGraphics
import XCTest
@testable import NotchCompressorCore

final class NotchTests: XCTestCase {
    func testDelayedFileURLsActivateDuringSamePressOnly() {
        var state = FileDragState(changeCount: 1)
        state.update(changeCount: 2, leftButtonDown: true, hasFiles: false)
        XCTAssertFalse(state.active)
        state.update(changeCount: 2, leftButtonDown: true, hasFiles: true)
        XCTAssertTrue(state.active)
        state.end()
        state.update(changeCount: 2, leftButtonDown: true, hasFiles: true)
        XCTAssertFalse(state.active)

        state.update(changeCount: 3, leftButtonDown: true, hasFiles: false)
        state.update(changeCount: 3, leftButtonDown: false, hasFiles: false)
        state.update(changeCount: 3, leftButtonDown: true, hasFiles: true)
        XCTAssertFalse(state.active)
    }

    func testOrdinaryClickAndStalePasteboardDoNotActivate() {
        var state = FileDragState(changeCount: 1)
        state.update(changeCount: 1, leftButtonDown: true, hasFiles: true)
        XCTAssertFalse(state.active)
        state.update(changeCount: 2, leftButtonDown: true, hasFiles: true)
        XCTAssertTrue(state.active)
        state.update(changeCount: 2, leftButtonDown: false, hasFiles: true)
        XCTAssertFalse(state.active)
        state.update(changeCount: 2, leftButtonDown: true, hasFiles: true)
        XCTAssertFalse(state.active)
    }
    func testTextDragAndEndedDragStayClosed() {
        var state = FileDragState(changeCount: 1)
        state.update(changeCount: 2, leftButtonDown: true, hasFiles: false)
        XCTAssertFalse(state.active)
        state.update(changeCount: 3, leftButtonDown: true, hasFiles: true)
        state.end()
        state.update(changeCount: 3, leftButtonDown: true, hasFiles: true)
        XCTAssertFalse(state.active)
    }
    func testCollapsedFrameFitsNotchAndRemainsAtScreenTop() {
        let screen = CGRect(x: -1512, y: 200, width: 1512, height: 982)
        let geometry = NotchGeometry(screen: screen, topInset: 32, notchWidth: 210)
        XCTAssertEqual(geometry.collapsed, CGRect(x: screen.midX - 105, y: screen.maxY - 32, width: 210, height: 32))
        XCTAssertEqual(geometry.collapsed.maxY, geometry.panel.maxY)
        let external = NotchGeometry(screen: screen, topInset: 0)
        XCTAssertEqual(external.collapsed.size, CGSize(width: 180, height: 28))
        XCTAssertEqual(external.collapsed.maxY, screen.maxY)
    }

    func testNotchAndExternalScreenCoordinates() {
        for screen in [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: -1920, y: 200, width: 1920, height: 1080)] {
            for inset: CGFloat in [0, 32] {
                let geometry = NotchGeometry(screen: screen, topInset: inset)
                XCTAssertEqual(geometry.panel.maxY, screen.maxY)
                XCTAssertEqual(geometry.panel.midX, screen.midX)
                XCTAssertTrue(geometry.trigger.contains(CGPoint(x: screen.midX, y: screen.maxY - 50)))
                XCTAssertEqual(geometry.mode(at: CGPoint(x: 80, y: 70)), .video)
                XCTAssertEqual(geometry.mode(at: CGPoint(x: 240, y: 70)), .both)
                XCTAssertEqual(geometry.mode(at: CGPoint(x: 400, y: 70)), .audio)
                XCTAssertNil(geometry.mode(at: CGPoint(x: 240, y: 10)))
                if inset > 0 { XCTAssertNil(geometry.mode(at: CGPoint(x: 240, y: geometry.panel.height - 1))) }
            }
        }
    }
}
