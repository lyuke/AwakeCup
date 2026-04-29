import AppKit
import Foundation
import SwiftUI

@MainActor
protocol MenuBarOverlayControlling: AnyObject {
    func updateHiddenMask(for hiddenItems: [MenuBarItemRecord])
    func hideHiddenMask()
    func presentExpandedStrip(
        for hiddenItems: [MenuBarItemRecord],
        onPress: @escaping (MenuBarItemRecord) -> Void
    )
    func dismissExpandedStrip()
}

@MainActor
final class MenuBarOverlayController: MenuBarOverlayControlling {
    private let overlayWindowLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
    private var hiddenMaskWindows: [NSWindow] = []
    private var expandedStripPanel: NSPanel?

    deinit {
        let hiddenMaskWindows = hiddenMaskWindows
        let expandedStripPanel = expandedStripPanel
        Task { @MainActor in
            hiddenMaskWindows.forEach { $0.orderOut(nil) }
            expandedStripPanel?.orderOut(nil)
        }
    }

    func updateHiddenMask(for hiddenItems: [MenuBarItemRecord]) {
        let frames = hiddenItems.hiddenMaskFrames
        guard !frames.isEmpty else {
            hideHiddenMask()
            return
        }

        syncHiddenMaskWindows(to: frames)
    }

    func hideHiddenMask() {
        hiddenMaskWindows.forEach { $0.orderOut(nil) }
        hiddenMaskWindows.removeAll(keepingCapacity: true)
    }

    func presentExpandedStrip(
        for hiddenItems: [MenuBarItemRecord],
        onPress: @escaping (MenuBarItemRecord) -> Void
    ) {
        guard let frame = hiddenItems.boundingFrame else {
            dismissExpandedStrip()
            return
        }

        let panel = expandedStripPanel ?? makeExpandedStripPanel(frame: frame)
        panel.setFrame(frame, display: true)
        panel.contentView = makeExpandedStripContentView(
            hiddenItems: hiddenItems,
            bounds: contentBounds(for: frame),
            onPress: onPress
        )
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
        window.level = overlayWindowLevel
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = makeHiddenMaskContentView(bounds: contentBounds(for: frame))
        return window
    }

    private func makeExpandedStripPanel(frame: CGRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = overlayWindowLevel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.contentView = makeExpandedStripContentView(
            hiddenItems: [],
            bounds: contentBounds(for: frame),
            onPress: { _ in }
        )
        return panel
    }

    private func makeHiddenMaskContentView(bounds: CGRect) -> NSView {
        let view = NSView(frame: bounds)
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        return view
    }

    private func syncHiddenMaskWindows(to frames: [CGRect]) {
        while hiddenMaskWindows.count < frames.count {
            hiddenMaskWindows.append(makeHiddenMaskWindow(frame: frames[hiddenMaskWindows.count]))
        }

        while hiddenMaskWindows.count > frames.count {
            hiddenMaskWindows.removeLast().orderOut(nil)
        }

        for (window, frame) in zip(hiddenMaskWindows, frames) {
            window.setFrame(frame, display: true)
            window.contentView = makeHiddenMaskContentView(bounds: contentBounds(for: frame))
            window.orderFrontRegardless()
        }
    }

    private func makeExpandedStripContentView(
        hiddenItems: [MenuBarItemRecord],
        bounds: CGRect,
        onPress: @escaping (MenuBarItemRecord) -> Void
    ) -> NSView {
        let hostingView = NSHostingView(
            rootView: MenuBarExpandedStripView(
                hiddenItems: hiddenItems,
                onPress: onPress
            )
        )
        hostingView.frame = bounds
        hostingView.autoresizingMask = [.width, .height]
        return hostingView
    }

    private func contentBounds(for frame: CGRect) -> CGRect {
        CGRect(origin: .zero, size: frame.size)
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

    var hiddenMaskFrames: [CGRect] {
        compactMap { item in
            guard item.hasKnownFrame else {
                return nil
            }
            return item.frame.integral
        }
    }
}

private struct MenuBarExpandedStripView: View {
    let hiddenItems: [MenuBarItemRecord]
    let onPress: (MenuBarItemRecord) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(hiddenItems, id: \.id) { item in
                Button {
                    onPress(item)
                } label: {
                    Text(item.displayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
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
