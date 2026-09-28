import AppKit
import SwiftUI

struct EditorInsertion: Equatable {
    let id = UUID()
    let text: String
}

/// Plain NSTextView bridge so the editor can switch line wrapping without
/// converting Markdown/TXT into a private rich-text representation.
struct NativeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: Double
    var wrapLines: Bool
    var insertion: EditorInsertion?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.wantsLayer = true
        scroll.layer?.masksToBounds = true
        guard let editor = scroll.documentView as? NSTextView else { return scroll }
        editor.string = text
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.usesFindBar = true
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 8, height: 10)
        editor.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        editor.delegate = context.coordinator
        configure(editor, in: scroll)
        let ruler = EditorLineNumberRuler(scrollView: scroll, textView: editor)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        context.coordinator.watchScrolling(in: scroll, ruler: ruler)
        context.coordinator.styleHeadings(in: editor)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text {
            let selection = editor.selectedRange()
            editor.string = text
            editor.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length),
                                            length: 0))
            (scroll.verticalRulerView as? EditorLineNumberRuler)?.reloadLines()
            context.coordinator.styleHeadings(in: editor)
        }
        if editor.font?.pointSize != CGFloat(fontSize) {
            editor.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            context.coordinator.styleHeadings(in: editor)
        }
        configure(editor, in: scroll)
        if let insertion, context.coordinator.lastInsertionID != insertion.id {
            context.coordinator.lastInsertionID = insertion.id
            context.coordinator.isUpdating = true
            editor.insertText(insertion.text, replacementRange: editor.selectedRange())
            context.coordinator.isUpdating = false
            scroll.window?.makeFirstResponder(editor)
        }
    }

    private func configure(_ editor: NSTextView, in scroll: NSScrollView) {
        scroll.hasHorizontalScroller = !wrapLines
        editor.isHorizontallyResizable = !wrapLines
        editor.isVerticallyResizable = true
        editor.autoresizingMask = wrapLines ? [.width] : []
        editor.minSize = NSSize(width: 0, height: 0)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.widthTracksTextView = wrapLines
        editor.textContainer?.heightTracksTextView = false
        editor.textContainer?.containerSize = NSSize(
            width: wrapLines ? max(scroll.contentSize.width, 1) : CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        if wrapLines {
            editor.frame.size.width = max(scroll.contentSize.width, 1)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeTextEditor
        var lastInsertionID: UUID?
        var isUpdating = false
        private var scrollObserver: NSObjectProtocol?
        init(_ parent: NativeTextEditor) { self.parent = parent }

        deinit {
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        }

        fileprivate func watchScrolling(in scroll: NSScrollView, ruler: EditorLineNumberRuler) {
            scroll.contentView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scroll.contentView,
                queue: .main
            ) { [weak ruler] _ in ruler?.needsDisplay = true }
        }

        func styleHeadings(in editor: NSTextView) {
            guard let layout = editor.layoutManager else { return }
            let source = editor.string as NSString
            let whole = NSRange(location: 0, length: source.length)
            guard whole.length > 0 else { return }
            layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
            layout.removeTemporaryAttribute(.font, forCharacterRange: whole)

            let pattern = try! NSRegularExpression(pattern: "(?m)^#{1,6}[ \\t]+[^\\r\\n]*")
            for match in pattern.matches(in: editor.string, range: whole) {
                let level = min(source.substring(with: match.range).prefix(while: { $0 == "#" }).count, 6)
                let blue = NSColor.systemBlue.blended(
                    withFraction: CGFloat(level - 1) * 0.08, of: .labelColor
                ) ?? .systemBlue
                layout.addTemporaryAttributes([
                    .foregroundColor: blue,
                    .font: NSFont.monospacedSystemFont(
                        ofSize: parent.fontSize + (level == 1 ? 1 : 0), weight: .semibold
                    )
                ], forCharacterRange: match.range)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            (editor.enclosingScrollView?.verticalRulerView as? EditorLineNumberRuler)?.reloadLines()
            styleHeadings(in: editor)
            let current = editor.string
            if parent.text != current {
                if isUpdating {
                    DispatchQueue.main.async { [weak self] in self?.parent.text = current }
                } else {
                    parent.text = current
                }
            }
        }
    }
}

/// Draws numbers beside logical lines. Wrapped visual fragments share one number.
private final class EditorLineNumberRuler: NSRulerView {
    private weak var editor: NSTextView?
    private var lineStarts: [Int] = [0]
    private let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.editor = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 42
        reloadLines()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func reloadLines() {
        guard let editor else { return }
        let units = Array(editor.string.utf16)
        lineStarts = [0]
        var index = 0
        while index < units.count {
            if units[index] == 13 {
                if index + 1 < units.count && units[index + 1] == 10 { index += 1 }
                lineStarts.append(index + 1)
            } else if units[index] == 10 {
                lineStarts.append(index + 1)
            }
            index += 1
        }
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let editor, let layout = editor.layoutManager,
              let container = editor.textContainer else { return }
        let visible = editor.visibleRect
        let origin = editor.textContainerOrigin
        let contentRect = visible.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = layout.glyphRange(forBoundingRect: contentRect, in: container)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        layout.enumerateLineFragments(forGlyphRange: glyphs) { [weak self] lineRect, _, _, glyphRange, _ in
            guard let self, glyphRange.length > 0 else { return }
            let character = layout.characterIndexForGlyph(at: glyphRange.location)
            guard let line = lineStarts.lastIndex(where: { $0 <= character }),
                  lineStarts[line] == character else { return }
            drawNumber(line + 1, at: lineRect.minY + origin.y,
                       height: lineRect.height, attributes: attributes)
        }

        if let last = lineStarts.last, last == (editor.string as NSString).length,
           layout.extraLineFragmentTextContainer != nil {
            let extra = layout.extraLineFragmentRect
            drawNumber(lineStarts.count, at: extra.minY + origin.y,
                       height: extra.height, attributes: attributes)
        }
    }

    private func drawNumber(_ number: Int, at textY: CGFloat, height: CGFloat,
                            attributes: [NSAttributedString.Key: Any]) {
        guard let editor else { return }
        let point = convert(NSPoint(x: 0, y: textY), from: editor)
        let label = String(number) as NSString
        let size = label.size(withAttributes: attributes)
        let target = NSRect(x: ruleThickness - size.width - 10,
                            y: point.y + (height - size.height) / 2,
                            width: size.width, height: size.height)
        if target.intersects(bounds) { label.draw(in: target, withAttributes: attributes) }
    }
}
