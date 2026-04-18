import AppKit
import Foundation
import SwiftUI

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
        window.contentView = makeHiddenMaskContentView(frame: frame)
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
        panel.contentView = makeExpandedStripContentView(hiddenItems: hiddenItems, frame: frame)
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
        window.contentView = makeHiddenMaskContentView(frame: frame)
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
        panel.contentView = makeExpandedStripContentView(hiddenItems: [], frame: frame)
        return panel
    }

    private func makeHiddenMaskContentView(frame: CGRect) -> NSView {
        let materialView = NSVisualEffectView(frame: frame)
        materialView.autoresizingMask = [.width, .height]
        materialView.material = .underWindowBackground
        materialView.blendingMode = .withinWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = 8
        materialView.layer?.masksToBounds = true
        return materialView
    }

    private func makeExpandedStripContentView(hiddenItems: [MenuBarItemRecord], frame: CGRect) -> NSView {
        let hostingView = NSHostingView(rootView: MenuBarExpandedStripView(hiddenItems: hiddenItems))
        hostingView.frame = frame
        hostingView.autoresizingMask = [.width, .height]
        return hostingView
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

private struct MenuBarExpandedStripView: View {
    let hiddenItems: [MenuBarItemRecord]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(hiddenItems, id: \.id) { item in
                Text(item.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}
