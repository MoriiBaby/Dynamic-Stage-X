import XCTest
import UIKit

// Include production Presentation sources and Core/DXGeometry.swift in the iOS
// XCTest target (or use @testable import DynamicStageX in an importable build).
// The real DXSystemBridge.h/.m are linked, not redefined as Swift fixtures.
final class DXPresentationTests: XCTestCase {
    private func onMain(_ body: () -> Void) {
        if Thread.isMainThread { body() } else { DispatchQueue.main.sync(execute: body) }
    }

    func testBothRealViewInstancesAreClippedWithTheSameHitPath() {
        onMain {
            let stage = DXStageViewController()
            stage.loadViewIfNeeded()
            stage.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            stage.setFrames(top: CGRect(x: 8, y: 60, width: 374, height: 340),
                            bottom: CGRect(x: 8, y: 448, width: 374, height: 340),
                            topRadius: 28, bottomRadius: 28, animated: false, duration: 0, curve: .linear)
            for pane in [stage.topPane, stage.bottomPane] {
                let host = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
                let nativeMask = CAShapeLayer()
                host.layer.mask = nativeMask
                pane.install(host)
                XCTAssertTrue(pane.hostedView === host)
                XCTAssertTrue(host.superview === pane)
                XCTAssertTrue(host.layer.mask === nativeMask) // UI did not mutate the host's own mask.
                XCTAssertTrue(pane.clipsToBounds)
                XCTAssertEqual(host.bounds.size, pane.bounds.size)
                guard let path = (pane.layer.mask as? CAShapeLayer)?.path else {
                    XCTFail("Missing clipping path"); return
                }
                for x in stride(from: CGFloat(0.5), to: pane.bounds.width, by: 7) {
                    for y in stride(from: CGFloat(0.5), to: pane.bounds.height, by: 7) {
                        let point = CGPoint(x: x, y: y)
                        XCTAssertEqual(pane.point(inside: point, with: nil), path.contains(point))
                    }
                }
                XCTAssertFalse(pane.point(inside: CGPoint(x: 0.1, y: 0.1), with: nil))
                XCTAssertTrue(pane.point(inside: CGPoint(x: 28, y: 1), with: nil))
                pane.detach()
                XCTAssertNil(host.superview)
                XCTAssertTrue(host.layer.mask === nativeMask)
            }
        }
    }

    func testDetachRestoresOnlyOurOwnedLayoutAndIsIdempotent() {
        onMain {
            let host = UIView(frame: CGRect(x: 12, y: 24, width: 50, height: 80))
            host.bounds.origin = CGPoint(x: 3, y: 4)
            host.translatesAutoresizingMaskIntoConstraints = false
            host.autoresizingMask = [.flexibleLeftMargin]
            let originalBounds = host.bounds, originalCenter = host.center
            let pane = DXRoundedPane(frame: CGRect(x: 0, y: 0, width: 160, height: 240))
            pane.install(host)
            pane.install(host)
            XCTAssertEqual(pane.subviews.count, 1)
            pane.detach()
            pane.detach()
            XCTAssertNil(pane.hostedView)
            XCTAssertEqual(host.bounds, originalBounds)
            XCTAssertEqual(host.center, originalCenter)
            XCTAssertFalse(host.translatesAutoresizingMaskIntoConstraints)
            XCTAssertEqual(host.autoresizingMask, [.flexibleLeftMargin])
        }
    }

    func testTransferBetweenPanesAndForeignReparentOwnership() {
        onMain {
            let a = DXRoundedPane(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
            let b = DXRoundedPane(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
            let host = UIView()
            a.install(host)
            b.install(host)
            XCTAssertNil(a.hostedView)
            XCTAssertTrue(b.hostedView === host)
            let foreignOwner = UIView()
            foreignOwner.addSubview(host)
            host.bounds = CGRect(x: 2, y: 3, width: 91, height: 93)
            host.center = CGPoint(x: 70, y: 80)
            let bounds = host.bounds, center = host.center
            b.detach()
            XCTAssertTrue(host.superview === foreignOwner)
            XCTAssertEqual(host.bounds, bounds)
            XCTAssertEqual(host.center, center)
        }
    }

    func testPassiveObserverCannotDelayCancelOrPreventAppGestures() {
        onMain {
            let pane = DXRoundedPane(frame: .zero)
            guard let observer = pane.gestureRecognizers?.first as? DXInteractionObserver else {
                XCTFail("Missing production observer"); return
            }
            XCTAssertFalse(observer.cancelsTouchesInView)
            XCTAssertFalse(observer.delaysTouchesBegan)
            XCTAssertFalse(observer.delaysTouchesEnded)
            let appPan = UIPanGestureRecognizer()
            XCTAssertFalse(observer.canPrevent(appPan))
            XCTAssertFalse(observer.canBePrevented(by: appPan))
        }
    }

    func testContinuousRadiusClampAndAnimationTopology() {
        onMain {
            let size = CGSize(width: 40, height: 80)
            let zero = DXContinuousCornerPath.make(size: size, radius: 0)
            let round = DXContinuousCornerPath.make(size: size, radius: 500)
            XCTAssertEqual(DXContinuousCornerPath.sampledRadius(in: round), 20)
            XCTAssertEqual(DXContinuousCornerPath.radius(.nan, in: size), 0)
            var a: [CGPathElementType] = [], b: [CGPathElementType] = []
            zero.applyWithBlock { a.append($0.pointee.type) }
            round.applyWithBlock { b.append($0.pointee.type) }
            XCTAssertEqual(a, b)
            XCTAssertTrue(zero.contains(CGPoint(x: 0.1, y: 0.1)))
            XCTAssertFalse(round.contains(CGPoint(x: 0.1, y: 0.1)))
        }
    }

    func testRepeatedLayoutDoesNotEraseInFlightCornerAnimation() {
        onMain {
            let pane = DXRoundedPane(frame: CGRect(x: 0, y: 0, width: 100, height: 200))
            let old = pane.capturePresentation()
            pane.apply(frame: CGRect(x: 0, y: 0, width: 200, height: 300), radius: 40,
                       alpha: 1, from: old.path, duration: 0.4, curve: .linear)
            pane.setNeedsLayout()
            pane.layoutIfNeeded()
            XCTAssertNotNil(pane.layer.mask?.animation(forKey: "DX.cornerPath"))
            let state = pane.capturePresentation()
            pane.freeze(state)
            XCTAssertNil(pane.layer.mask?.animation(forKey: "DX.cornerPath"))
            XCTAssertEqual(pane.frame, state.frame)
        }
    }

    func testInputModeRestoresMostRecentSplitTargetsWithoutDetachingHosts() {
        onMain {
            let stage = DXStageViewController()
            stage.loadViewIfNeeded()
            let topHost = UIView(), bottomHost = UIView()
            stage.topPane.install(topHost)
            stage.bottomPane.install(bottomHost)
            let top = CGRect(x: 8, y: 60, width: 374, height: 320)
            let bottom = CGRect(x: 8, y: 428, width: 374, height: 320)
            stage.setFrames(top: top, bottom: bottom, topRadius: 28, bottomRadius: 30,
                            animated: false, duration: 0, curve: .linear)
            let focused = CGRect(x: 8, y: 60, width: 374, height: 500)
            stage.setInputFocused(.bottom, frame: focused, animated: false, duration: 0, curve: .linear)
            XCTAssertTrue(stage.topPane.isHidden)
            XCTAssertFalse(stage.bottomPane.isHidden)
            XCTAssertEqual(stage.bottomPane.frame, focused)
            XCTAssertTrue(topHost.superview === stage.topPane)
            let newBottom = bottom.offsetBy(dx: 0, dy: 12)
            stage.setFrames(top: top, bottom: newBottom, topRadius: 24, bottomRadius: 26,
                            animated: false, duration: 0, curve: .linear)
            XCTAssertEqual(stage.bottomPane.frame, focused)
            stage.setInputFocused(nil, frame: nil, animated: false, duration: 0, curve: .linear)
            XCTAssertEqual(stage.topPane.frame, top)
            XCTAssertEqual(stage.bottomPane.frame, newBottom)
            XCTAssertFalse(stage.topPane.isHidden)
            XCTAssertFalse(stage.bottomPane.isHidden)
            XCTAssertTrue(bottomHost.superview === stage.bottomPane)
        }
    }

    func testInvalidInputFramePreservesCurrentLayout() {
        onMain {
            let stage = DXStageViewController()
            let top = CGRect(x: 8, y: 60, width: 320, height: 260)
            let bottom = CGRect(x: 8, y: 380, width: 320, height: 260)
            stage.setFrames(top: top, bottom: bottom, topRadius: 28, bottomRadius: 28,
                            animated: false, duration: 0, curve: .linear)
            stage.setInputFocused(.top, frame: .zero, animated: false, duration: 0, curve: .linear)
            XCTAssertNil(stage.inputFocusedSlot)
            XCTAssertEqual(stage.topPane.frame, top)
            stage.setFrames(top: .null, bottom: bottom, topRadius: 28, bottomRadius: 28,
                            animated: false, duration: 0, curve: .linear)
            XCTAssertEqual(stage.topPane.frame, top)
        }
    }

    func testRootPassesThroughGapsAndRejectsVisibleRoundedCorners() {
        onMain {
            let stage = DXStageViewController()
            stage.loadViewIfNeeded()
            stage.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            stage.setFrames(top: CGRect(x: 8, y: 60, width: 374, height: 320),
                            bottom: CGRect(x: 8, y: 428, width: 374, height: 320),
                            topRadius: 28, bottomRadius: 28, animated: false, duration: 0, curve: .linear)
            let topHost = UIView()
            stage.topPane.install(topHost)
            XCTAssertNil(stage.view.hitTest(CGPoint(x: 3, y: 403), with: nil))
            XCTAssertNil(stage.view.hitTest(CGPoint(x: 8.1, y: 60.1), with: nil))
            XCTAssertTrue(stage.view.hitTest(CGPoint(x: 100, y: 150), with: nil) === topHost)
            let overlay = DXOverlayWindow(frame: stage.view.bounds)
            overlay.rootViewController = stage
            XCTAssertFalse(overlay.permitsBackgroundHitTesting)
            XCTAssertFalse(overlay.canBecomeKey)
            overlay.isContextEnabled = false
            XCTAssertNil(overlay.hitTest(CGPoint(x: 100, y: 150), with: nil))
        }
    }

    func testPickerEmptyListAndInvalidationDoNotFabricateSelection() {
        onMain {
            let stage = DXStageViewController()
            var selected = false
            let overlay = DXOverlayWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            overlay.rootViewController = stage
            stage.showPicker(applications: [], excluding: nil) { _ in selected = true }
            XCTAssertTrue(stage.hasApplicationPicker)
            XCTAssertFalse(overlay.canBecomeKey)
            stage.filterPickerApplications(query: "Reader")
            stage.dismissPicker()
            stage.dismissPicker()
            XCTAssertFalse(stage.hasApplicationPicker)
            XCTAssertFalse(selected)
            let picker = DXApplicationPickerViewController(applications: [], excluding: nil,
                selection: { _ in selected = true }, cancellation: {})
            picker.loadViewIfNeeded()
            XCTAssertEqual(picker.tableView(UITableView(), numberOfRowsInSection: 0), 0)
            picker.filterApplications(query: "Reader")
            XCTAssertNil(picker.sectionIndexTitles(for: UITableView()))
            func hasTextInput(_ root: UIView) -> Bool {
                return root is UITextField || root is UITextView || root is UISearchBar ||
                    root.subviews.contains(where: hasTextInput)
            }
            XCTAssertFalse(hasTextInput(picker.view))
            picker.tableView(UITableView(), didSelectRowAt: IndexPath(row: 0, section: 0))
            picker.invalidate()
            XCTAssertFalse(selected)
        }
    }

    func testProductionSearchMatchesNameIdentifierAndAllTerms() {
        XCTAssertTrue(DXApplicationSearch.matches(query: "cafe EXAMPLE", name: "Café 阅读器",
                                                  bundleIdentifier: "com.example.Reader"))
        XCTAssertTrue(DXApplicationSearch.matches(query: "阅读", name: "Café 阅读器", bundleIdentifier: "com.reader"))
        XCTAssertTrue(DXApplicationSearch.matches(query: " \n ", name: "Safari", bundleIdentifier: "com.apple.mobilesafari"))
        XCTAssertFalse(DXApplicationSearch.matches(query: "cafe absent", name: "Café", bundleIdentifier: "com.example.Reader"))
    }

    func testEdgeRegionAndDeliberatePanPolicyRejectAccidents() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        let safe = UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
        let right = DXEdgeTriggerPolicy.region(bounds: bounds, safeArea: safe, side: "right")
        let left = DXEdgeTriggerPolicy.region(bounds: bounds, safeArea: safe, side: "left")
        XCTAssertEqual(right.size, CGSize(width: 64, height: 88))
        XCTAssertEqual(left.minX, 0)
        XCTAssertEqual(right.maxX, 390)
        XCTAssertLessThan(right.maxY, bounds.maxY - safe.bottom)
        XCTAssertFalse(right.contains(CGPoint(x: 195, y: 700)))
        // Starting admission defers directional intent to release, including zero/zero
        // samples that UIKit may expose while transitioning out of possible.
        XCTAssertTrue(DXEdgeTriggerPolicy.mayBegin(translation: .zero, velocity: .zero))
        XCTAssertTrue(DXEdgeTriggerPolicy.mayBegin(translation: CGPoint(x: 40, y: -2), velocity: CGPoint(x: 250, y: -10)))
        XCTAssertFalse(DXEdgeTriggerPolicy.mayBegin(translation: CGPoint(x: .nan, y: 0), velocity: .zero))
        XCTAssertTrue(DXEdgeTriggerPolicy.mayBegin(translation: CGPoint(x: 0, y: -8), velocity: .zero))
        XCTAssertTrue(DXEdgeTriggerPolicy.mayFinish(translation: CGPoint(x: 8, y: -48), velocity: .zero, elapsed: 0.4))
        XCTAssertTrue(DXEdgeTriggerPolicy.mayFinish(translation: CGPoint(x: 0, y: -96), velocity: CGPoint(x: 0, y: -500), elapsed: 0.2))
        XCTAssertTrue(DXEdgeTriggerPolicy.mayFinish(translation: CGPoint(x: 0, y: -64), velocity: CGPoint(x: 0, y: -800), elapsed: 0.02))
        XCTAssertFalse(DXEdgeTriggerPolicy.mayFinish(translation: CGPoint(x: 0, y: 64), velocity: .zero, elapsed: 0.3))
        XCTAssertFalse(DXEdgeTriggerPolicy.mayFinish(translation: CGPoint(x: 0, y: -20), velocity: .zero, elapsed: 0.6))
        XCTAssertFalse(DXEdgeTriggerPolicy.mayFinish(translation: CGPoint(x: 100, y: -48), velocity: .zero, elapsed: 0.4))
        XCTAssertFalse(DXEdgeTriggerPolicy.mayFinish(translation: CGPoint(x: 0, y: -96), velocity: .zero, elapsed: 3))
        XCTAssertFalse(DXEdgeTriggerPolicy.mayFinish(translation: CGPoint(x: 0, y: -CGFloat.infinity), velocity: .zero, elapsed: 0.6))
        onMain {
            let edge = DXEdgeTriggerWindow(frame: bounds)
            edge.triggerSide = "LEFT"
            XCTAssertEqual(edge.triggerSide, "left")
            edge.triggerSide = "invalid"
            XCTAssertEqual(edge.triggerSide, "right")
            XCTAssertFalse(edge.canBecomeKey)
            edge.isContextEnabled = false
            XCTAssertNil(edge.hitTest(CGPoint(x: right.midX, y: right.midY), with: nil))
        }
    }
}
