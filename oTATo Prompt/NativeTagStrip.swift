import AppKit
import SwiftUI

/// The tag strip has a fixed document geometry. Scrolling does not create
/// SwiftUI views, read the library, or publish an offset back to ContentView.
struct NativeTagStrip: NSViewRepresentable {
    @Environment(\.appAccentStyle) private var accent
    @Binding var filter: PromptLibraryFilter
    let tags: [PromptTagFilterOption]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NativeTagScrollView {
        let scroll = NativeTagScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .allowed
        scroll.verticalScrollElasticity = .none
        scroll.usesPredominantAxisScrolling = true
        scroll.focusRingType = .none
        scroll.wantsLayer = true
        scroll.contentView.wantsLayer = true
        scroll.documentView = NativeTagDocumentView()
        context.coordinator.update(scroll, accent: accent)
        return scroll
    }

    func updateNSView(_ scroll: NativeTagScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(scroll, accent: accent)
    }

    final class Coordinator: NSObject {
        var parent: NativeTagStrip
        private var lastTags: [PromptTagFilterOption]?
        private var lastFilter: PromptLibraryFilter?
        private var lastPalette: AppAccentPalette?
        private var lastScheme: ColorScheme?
        private var buttons: [NativeTagButton] = []

        init(_ parent: NativeTagStrip) { self.parent = parent }

        func update(_ scroll: NativeTagScrollView, accent: AppAccentStyle) {
            guard let document = scroll.documentView else { return }
            let rebuild = lastTags != parent.tags
            guard rebuild || lastFilter != parent.filter || lastPalette != accent.palette ||
                    lastScheme != accent.colorScheme else { return }
            if rebuild {
                let offset = scroll.contentView.bounds.origin
                buttons.forEach { $0.removeFromSuperview() }
                buttons = [makeButton(id: nil, name: "全部", count: nil)]
                    + parent.tags.map { makeButton(id: $0.id, name: $0.name, count: $0.promptCount) }
                var x: CGFloat = 0
                for button in buttons {
                    // Reserve the exclusion mark so selecting a tag never shifts its neighbours.
                    let widestTitle = button.tagID == nil ? button.tagName : "− \(button.tagName)"
                    let textWidth = (widestTitle as NSString).size(withAttributes: [.font: button.tagFont]).width
                    button.frame = NSRect(x: x, y: 2, width: ceil(textWidth) + 24, height: 25)
                    document.addSubview(button)
                    x += button.frame.width + 7
                }
                document.frame = NSRect(x: 0, y: 0, width: max(0, x - 7), height: 29)
                scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(
                    NSRect(origin: offset, size: scroll.contentView.bounds.size)).origin)
                scroll.reflectScrolledClipView(scroll.contentView)
                lastTags = parent.tags
            }
            for button in buttons {
                let excluded = button.tagID.map { parent.filter.excludedTagIDs.contains($0) } ?? false
                button.title = excluded ? "− \(button.tagName)" : button.tagName
                button.selected = button.tagID.map {
                    parent.filter.selectedTagIDs.contains($0) || excluded
                } ?? (parent.filter.selectedTagIDs.isEmpty && parent.filter.excludedTagIDs.isEmpty &&
                      parent.filter.tagPresence == .any)
                button.selectedFill = NSColor(accent.selectedFill)
                button.selectedText = NSColor(accent.selectedForeground)
                button.focusColor = NSColor(accent.tint)
                button.setAccessibilityValue(excluded ? "已排除" : button.selected ? "已选择" : "未选择")
                if let menuItem = button.menu?.items.first {
                    menuItem.title = excluded ? "取消排除此标签" : "排除此标签"
                }
                button.needsDisplay = true
            }
            lastFilter = parent.filter
            lastPalette = accent.palette
            lastScheme = accent.colorScheme
        }

        private func makeButton(id: UUID?, name: String, count: Int?) -> NativeTagButton {
            let button = NativeTagButton()
            button.tagID = id
            button.tagName = name
            button.title = name
            button.font = button.tagFont
            button.isBordered = false
            button.focusRingType = .none
            button.setButtonType(.momentaryPushIn)
            button.target = self
            button.action = #selector(selectTag(_:))
            button.setAccessibilityLabel(name)
            if let id, let count {
                button.toolTip = "\(count) 个提示词；点击选择或取消，右键可排除"
                let menu = NSMenu()
                let item = NSMenuItem(title: "排除此标签", action: #selector(excludeTag(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = id
                menu.addItem(item)
                button.menu = menu
            }
            return button
        }

        @objc private func selectTag(_ sender: NativeTagButton) {
            guard let id = sender.tagID else { parent.filter.clearTags(); return }
            if parent.filter.excludedTagIDs.contains(id) { parent.filter.toggleExcludedTag(id) }
            else { parent.filter.toggleTag(id) }
        }

        @objc private func excludeTag(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? UUID else { return }
            parent.filter.toggleExcludedTag(id)
        }
    }
}

final class NativeTagScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        // Horizontal trackpad gestures keep AppKit's native inertia. A vertical
        // mouse wheel also scrolls this horizontal strip, including precise deltas.
        if abs(event.scrollingDeltaX) < 0.001 && abs(event.scrollingDeltaY) > 0.001 {
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
            let maxX = max(0, (documentView?.frame.width ?? 0) - contentView.bounds.width)
            let x = min(max(0, contentView.bounds.minX - event.scrollingDeltaY * scale), maxX)
            contentView.scroll(to: NSPoint(x: x, y: 0))
            reflectScrolledClipView(contentView)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

private final class NativeTagDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class NativeTagButton: NSButton {
    var tagID: UUID?
    var tagName = ""
    let tagFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    var selected = false
    var selectedFill = NSColor.labelColor
    var selectedText = NSColor.textBackgroundColor
    var focusColor = NSColor.controlAccentColor
    private var hovering = false
    private var hoverTracking: NSTrackingArea?

    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero,
                                      options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                      owner: self, userInfo: nil)
        addTrackingArea(tracking)
        hoverTracking = tracking
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let capsule = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        (selected ? selectedFill : NSColor.labelColor.withAlphaComponent(hovering ? 0.11 : 0.06)).setFill()
        capsule.fill()
        let text = NSAttributedString(string: title, attributes: [
            .font: tagFont,
            .foregroundColor: selected ? selectedText : NSColor.labelColor
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
        if window?.firstResponder === self {
            focusColor.withAlphaComponent(0.35).setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
            ring.lineWidth = 0.75
            ring.stroke()
        }
    }
}
