import AppKit
import Foundation

@MainActor
protocol MenuBarOverlayControlling: AnyObject {
    func updateHiddenMask(for hiddenItems: [MenuBarItemRecord])
    func hideHiddenMask()
    func presentExpandedStrip(for hiddenItems: [MenuBarItemRecord])
    func dismissExpandedStrip()
}

@MainActor
final class MenuBarOverlayController: MenuBarOverlayControlling {
    private var hiddenMaskWindow: NSWindow?
    private var expandedStripPanel: NSPanel?

    func updateHiddenMask(for hiddenItems: [MenuBarItemRecord]) {
        guard let frame = hiddenItems.boundingFrame else {
            hideHiddenMask()
            return
        }

        let window = hiddenMaskWindow ?? makeHiddenMaskWindow(frame: frame)
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        hiddenMaskWindow = window
    }

    func hideHiddenMask() {
        hiddenMaskWindow?.orderOut(nil)
    }

    func presentExpandedStrip(for hiddenItems: [MenuBarItemRecord]) {
        guard let frame = hiddenItems.boundingFrame else {
            dismissExpandedStrip()
            return
        }

        let panel = expandedStripPanel ?? makeExpandedStripPanel(frame: frame)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        expandedStripPanel = panel
    }

    func dismissExpandedStrip() {
        expandedStripPanel?.orderOut(nil)
    }

    private func makeHiddenMaskWindow(frame: CGRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSView(frame: frame)
        return window
    }

    private func makeExpandedStripPanel(frame: CGRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.contentView = NSView(frame: frame)
        return panel
    }
}

private extension Array where Element == MenuBarItemRecord {
    var boundingFrame: CGRect? {
        guard var frame = first?.frame else {
            return nil
        }

        for item in dropFirst() {
            frame = frame.union(item.frame)
        }
        return frame
    }
}
