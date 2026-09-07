import CoreGraphics
import XCTest
@testable import NotchCompressorCore

final class NotchTests: XCTestCase {
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
