import CoreGraphics
import XCTest
@testable import NotchCompressorCore

final class NotchTests: XCTestCase {
    func testTransitionKeepsActualPersistentWidthAndCameraOffset() {
        let expanded = CGRect(x: 480, y: 720, width: 480, height: 180)
        // A wide physical cutout plus two information regions can exceed 480pt.
        let idle = CGRect(x: 440, y: 868, width: 560, height: 32)
        let layout = NotchTransitionGeometry(expanded: expanded, collapsed: idle)
        XCTAssertEqual(layout.canvas, CGRect(x: 440, y: 720, width: 560, height: 180))
        XCTAssertEqual(layout.expanded, CGRect(x: 40, y: 0, width: 480, height: 180))
        XCTAssertEqual(layout.collapsed, CGRect(x: 0, y: 0, width: 560, height: 32))
        XCTAssertEqual(layout.canvas.minX + layout.collapsed.minX, idle.minX)
        XCTAssertEqual(layout.canvas.maxY - layout.collapsed.minY, idle.maxY)
    }

    func testTransitionPreservesIdlePositionBelowUnknownCamera() {
        let expanded = CGRect(x: -800, y: 620, width: 480, height: 180)
        let idle = CGRect(x: -700, y: 740, width: 240, height: 28)
        let layout = NotchTransitionGeometry(expanded: expanded, collapsed: idle)
        XCTAssertEqual(layout.canvas, expanded)
        XCTAssertEqual(layout.collapsed, CGRect(x: 100, y: 32, width: 240, height: 28))
        XCTAssertEqual(layout.expanded.origin, .zero)
    }

    func testTransitionWithoutWidgetsStillClosesToOriginalNotch() {
        let geometry = NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1440, height: 900), topInset: 0)
        let layout = NotchTransitionGeometry(expanded: geometry.panel, collapsed: geometry.collapsed)
        XCTAssertEqual(layout.canvas, geometry.panel)
        XCTAssertEqual(layout.collapsed, CGRect(x: 150, y: 0, width: 180, height: 28))
    }

    func testMusicConnectionSeparatesPermissionFromPlayback() {
        XCTAssertEqual(MusicConnectionState(checking: false, playing: nil, statusKey: "widgets.noTrack"), .ready)
        XCTAssertTrue(MusicConnectionState.ready.connected)
        XCTAssertEqual(MusicConnectionState(checking: false, playing: false, statusKey: nil), .paused)
        XCTAssertEqual(MusicConnectionState(checking: true, playing: true, statusKey: nil), .checking)
        XCTAssertEqual(
            MusicConnectionState(checking: false, playing: nil, statusKey: "widgets.musicPermission"), .denied)
        XCTAssertEqual(
            MusicConnectionState(checking: false, playing: nil, statusKey: "widgets.permissionNeeded"),
            .permissionNeeded)
        XCTAssertEqual(MusicConnectionState(checking: false, playing: nil, statusKey: "widgets.openMusic"), .closed)
        XCTAssertFalse(MusicConnectionState.closed.connected)
    }

    func testIndependentWidgetDisplayMigration() {
        XCTAssertEqual(NotchWidgetDisplay(savedValue: nil, legacyEnabled: false, legacyAlways: true), .off)
        XCTAssertEqual(NotchWidgetDisplay(savedValue: nil, legacyEnabled: true, legacyAlways: false), .hover)
        XCTAssertEqual(NotchWidgetDisplay(savedValue: nil, legacyEnabled: true, legacyAlways: true), .always)
        XCTAssertEqual(NotchWidgetDisplay(savedValue: "off", legacyEnabled: true, legacyAlways: true), .off)
        XCTAssertEqual(NotchWidgetDisplay(savedValue: "hover", legacyEnabled: true, legacyAlways: true), .hover)
    }
    func testDropContentMatchesTargets() {
        let samples: [([String], NotchDropContent)] = [
            (["a.MOV", "b.mp4"], .video), (["a.png", "b.JPEG"], .image),
            (["a.m4a"], .audio), (["a.png", "b.mov"], .automatic),
            (["a.pdf"], .automatic), ([], .automatic),
        ]
        for (names, expected) in samples {
            let content = NotchDropContent(urls: names.map { URL(fileURLWithPath: "/" + $0) })
            XCTAssertEqual(content, expected)
            XCTAssertNil(content.mode(for: nil))
            for mode in CompressionMode.allCases {
                XCTAssertEqual(content.mode(for: mode), content == .video ? mode : content.singleMode)
            }
        }
    }
    func testOuterScreenEdgeKeepsDropTargetAndApproachOpensBeforeTop() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let second = CGRect(x: 1920, y: -81, width: 1080, height: 1920)
        XCTAssertEqual(NotchGeometry.screenIndex(containing: CGPoint(x: 960, y: 1080), frames: [screen, second]), 0)
        XCTAssertEqual(NotchGeometry.screenIndex(containing: CGPoint(x: 1920, y: 800), frames: [screen, second]), 1)
        XCTAssertEqual(NotchGeometry.screenIndex(containing: CGPoint(x: 3000, y: 1839), frames: [screen, second]), 1)
        XCTAssertNil(NotchGeometry.screenIndex(containing: CGPoint(x: -1, y: 500), frames: [screen, second]))
        let geometry = NotchGeometry(screen: screen, topInset: 32)
        XCTAssertTrue(geometry.isInTrigger(CGPoint(x: 960, y: 1080)))
        XCTAssertTrue(geometry.isInTrigger(CGPoint(x: 960, y: 980)))
        XCTAssertFalse(geometry.isInTrigger(CGPoint(x: 960, y: 900)))
    }

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
    func testNativeDropSurvivesMouseUpUntilDeliveryButExpiresOnCancellation() {
        var session = NativeDropSession()
        XCTAssertFalse(session.holdsPanelOpen(leftButtonDown: true, now: 0))
        session.entered()
        XCTAssertTrue(session.holdsPanelOpen(leftButtonDown: true, now: 1))
        XCTAssertTrue(session.holdsPanelOpen(leftButtonDown: false, now: 2))
        XCTAssertTrue(session.holdsPanelOpen(leftButtonDown: false, now: 2.1))
        session.ended()
        XCTAssertFalse(session.holdsPanelOpen(leftButtonDown: false, now: 2.2))
        session.entered()
        XCTAssertTrue(session.holdsPanelOpen(leftButtonDown: false, now: 3))
        XCTAssertFalse(session.holdsPanelOpen(leftButtonDown: false, now: 3.5))
        XCTAssertFalse(session.holdsPanelOpen(leftButtonDown: true, now: 4))
    }

    func testCompactWidgetsKeepMenuBarHeightAtDifferentContentWidths() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        for width: CGFloat in [90, 120] {
            let layout = NotchWidgetGeometry(
                screen: screen, topInset: 32, notchWidth: 210,
                preferredSideWidth: width)
            XCTAssertEqual(layout.frame.height, 32)
            XCTAssertEqual(layout.frame.midX, screen.midX)
            XCTAssertEqual(layout.frame.maxY, screen.maxY)
            XCTAssertEqual(layout.frame.width, 210 + 2 * width)
        }
    }

    func testPersistentContentNeverIntersectsCameraIncludingOffsetScreens() {
        for screen in [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: -1728, y: 100, width: 1728, height: 1117),
        ] {
            for offset: CGFloat in [-40, 0, 40] {
                let camera = CGRect(
                    x: screen.midX + offset - 110, y: screen.maxY - 38,
                    width: 220, height: 38)
                for width: CGFloat in [120, 160] {
                    let layout = NotchWidgetGeometry(
                        screen: screen, topInset: 38, notchWidth: 180,
                        preferredSideWidth: width, cameraRect: camera, cameraPadding: 8)
                    XCTAssertEqual(layout.frame.midX, camera.midX)
                    XCTAssertLessThanOrEqual(layout.leftRegion.maxX, camera.minX - 8)
                    XCTAssertGreaterThanOrEqual(layout.rightRegion.minX, camera.maxX + 8)
                    XCTAssertFalse(layout.leftRegion.intersects(camera))
                    XCTAssertFalse(layout.rightRegion.intersects(camera))
                    XCTAssertTrue(screen.contains(layout.frame))
                }
            }
        }
    }

    func testWidgetsReserveCameraAndFitExternalDisplays() {
        for screen in [
            CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: -1920, y: 200, width: 1920, height: 1080),
        ] {
            let notch = NotchWidgetGeometry(screen: screen, topInset: 32, notchWidth: 210)
            XCTAssertEqual(notch.cameraWidth, 210)
            XCTAssertEqual(notch.frame.midX, screen.midX)
            XCTAssertEqual(notch.frame.maxY, screen.maxY)
            XCTAssertEqual(notch.frame.width, 2 * notch.sideWidth + notch.cameraWidth)
            XCTAssertTrue(screen.contains(notch.frame))
            let external = NotchWidgetGeometry(screen: screen, topInset: 0, notchWidth: 0)
            XCTAssertEqual(external.cameraWidth, 0)
            XCTAssertEqual(external.frame.maxY, screen.maxY)
            XCTAssertTrue(screen.contains(external.frame))
        }
        let narrow = NotchWidgetGeometry(
            screen: CGRect(x: 0, y: 0, width: 200, height: 300), topInset: 32, notchWidth: 210)
        XCTAssertEqual(narrow.frame.width, 200)
        XCTAssertGreaterThanOrEqual(narrow.sideWidth, 0)
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
        for screen in [
            CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: -1920, y: 200, width: 1920, height: 1080),
        ] {
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
    func testHoverNeedsDwellAndKeepsExpandedContentReachable() {
        var hover = NotchHoverState()
        hover.update(insideTrigger: true, insidePanel: false, now: 1)
        hover.update(insideTrigger: true, insidePanel: false, now: 1.1)
        XCTAssertFalse(hover.expanded)
        hover.update(insideTrigger: false, insidePanel: false, now: 1.12)
        hover.update(insideTrigger: true, insidePanel: false, now: 2)
        XCTAssertFalse(hover.expanded, "A pass over the menu bar must not open the panel")
        hover.update(insideTrigger: true, insidePanel: false, now: 2.2)
        XCTAssertTrue(hover.expanded)
        hover.update(insideTrigger: false, insidePanel: true, now: 3)
        XCTAssertTrue(hover.expanded, "Moving from the notch into its content keeps it open")
        hover.update(insideTrigger: false, insidePanel: false, now: 4)
        hover.update(insideTrigger: false, insidePanel: false, now: 4.1)
        XCTAssertTrue(hover.expanded)
        hover.update(insideTrigger: false, insidePanel: true, now: 4.2)
        hover.update(insideTrigger: false, insidePanel: false, now: 5)
        hover.update(insideTrigger: false, insidePanel: false, now: 5.3)
        XCTAssertFalse(hover.expanded)
        hover.update(insideTrigger: true, insidePanel: false, now: 6)
        hover.update(insideTrigger: true, insidePanel: false, now: 6.2)
        hover.reset()
        XCTAssertFalse(hover.expanded, "A file drag takes priority over information")
    }

}
