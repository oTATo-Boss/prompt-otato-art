import AppKit
import SwiftUI

struct EditorInsertion: Equatable {
    let id = UUID()
    let text: String
}

enum MarkdownFormatAction: Equatable {
    case heading1, heading2, bold, italic, bullet, quote, code, link
}

struct EditorCommand: Equatable {
    let id = UUID()
    let action: MarkdownFormatAction
}

/// NSTextStorage always contains the original Markdown. The layout manager
/// suppresses syntax glyphs while keeping their source character indexes, so
/// editing, selection, undo, IME composition, and copying never round-trip
/// through an attributed-string Markdown serializer.
struct NativeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: Double
    var wrapLines: Bool
    var insertion: EditorInsertion?
    var command: EditorCommand? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.wantsLayer = true
        scroll.layer?.masksToBounds = true
        scroll.focusRingType = .none
        scroll.hasVerticalRuler = false
        scroll.rulersVisible = false
        guard let editor = scroll.documentView as? NSTextView else { return scroll }
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.usesFindBar = true
        editor.drawsBackground = false
        editor.wantsLayer = true
        // Keep laid-out text in its backing layer while scrolling. TextKit
        // only needs to lay out newly visible paragraphs of a long prompt.
        editor.layoutManager?.allowsNonContiguousLayout = true
        editor.focusRingType = .none
        editor.textContainerInset = NSSize(width: 15, height: 14)
        editor.font = .systemFont(ofSize: CGFloat(fontSize))
        editor.string = text
        editor.delegate = context.coordinator
        context.coordinator.editor = editor
        editor.layoutManager?.delegate = context.coordinator
        editor.textStorage?.delegate = context.coordinator
        configure(editor, in: scroll)
        context.coordinator.refreshAll(in: editor)
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        // NSTextView can retain the end position from assigning its initial
        // string. New documents should open at the beginning after layout.
        DispatchQueue.main.async {
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text, !editor.hasMarkedText() {
            let selection = editor.selectedRange()
            context.coordinator.isExternalUpdate = true
            editor.string = text
            context.coordinator.isExternalUpdate = false
            editor.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length),
                                            length: 0))
            context.coordinator.refreshAll(in: editor)
        }
        if editor.font?.pointSize != CGFloat(fontSize) {
            context.coordinator.isExternalUpdate = true
            editor.font = .systemFont(ofSize: CGFloat(fontSize))
            context.coordinator.isExternalUpdate = false
            context.coordinator.refreshAll(in: editor)
        }
        configure(editor, in: scroll)
        if let insertion, context.coordinator.lastInsertionID != insertion.id {
            context.coordinator.lastInsertionID = insertion.id
            editor.insertText(insertion.text, replacementRange: editor.selectedRange())
            scroll.window?.makeFirstResponder(editor)
        }
        if let command, context.coordinator.lastCommandID != command.id {
            context.coordinator.lastCommandID = command.id
            context.coordinator.apply(command.action, in: editor)
            if command.action != .link { scroll.window?.makeFirstResponder(editor) }
        }
    }

    private func configure(_ editor: NSTextView, in scroll: NSScrollView) {
        // AppKit setters can invalidate text layout even when their value is
        // unchanged. Parent-view updates must not reconfigure the whole editor.
        if scroll.hasHorizontalScroller != !wrapLines { scroll.hasHorizontalScroller = !wrapLines }
        if editor.isHorizontallyResizable != !wrapLines { editor.isHorizontallyResizable = !wrapLines }
        if !editor.isVerticallyResizable { editor.isVerticallyResizable = true }
        let mask: NSView.AutoresizingMask = wrapLines ? [.width] : []
        if editor.autoresizingMask != mask { editor.autoresizingMask = mask }
        if editor.minSize != .zero { editor.minSize = .zero }
        let maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if editor.maxSize != maxSize { editor.maxSize = maxSize }
        guard let container = editor.textContainer else { return }
        if container.widthTracksTextView != wrapLines { container.widthTracksTextView = wrapLines }
        if container.heightTracksTextView { container.heightTracksTextView = false }
        let width = max(scroll.contentSize.width, 1)
        let size = NSSize(
            width: wrapLines ? width : CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        if container.containerSize != size { container.containerSize = size }
        if wrapLines, editor.frame.size.width != width { editor.frame.size.width = width }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate, NSLayoutManagerDelegate {
        var parent: NativeTextEditor
        weak var editor: NSTextView?
        var lastInsertionID: UUID?
        var lastCommandID: UUID?
        var isExternalUpdate = false

        // These indexes are UTF-16 source offsets, the same coordinate system
        // used by NSTextView and NSLayoutManager. A hidden marker has a null
        // glyph but still occupies its original source index.
        private let hiddenMarkers = NSMutableIndexSet()
        private let bulletMarkers = NSMutableIndexSet()
        private let fenceMarkers = NSMutableIndexSet()
        private var pendingRefreshRange: NSRange?
        private var refreshScheduled = false
        private var pendingFenceParity = 0
        private var isNormalizingEdit = false
        private var isApplyingCommand = false
        private var isAdjustingSelection = false
        private var lastSelectionLocation: Int?

        init(_ parent: NativeTextEditor) { self.parent = parent }

        func layoutManager(_ layoutManager: NSLayoutManager,
                           shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                           properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                           characterIndexes indexes: UnsafePointer<Int>,
                           font: NSFont,
                           forGlyphRange glyphRange: NSRange) -> Int {
            guard glyphRange.length > 0 else { return 0 }
            var changed = false
            for offset in 0..<glyphRange.length {
                let character = indexes[offset]
                if hiddenMarkers.contains(character) || bulletMarkers.contains(character) {
                    changed = true
                    break
                }
            }
            guard changed else { return 0 }
            var generated = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
            var properties = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
            var characters = Array(UnsafeBufferPointer(start: indexes, count: glyphRange.length))
            for offset in 0..<glyphRange.length {
                let character = characters[offset]
                if hiddenMarkers.contains(character) {
                    properties[offset] = .null
                } else if bulletMarkers.contains(character) {
                    generated[offset] = CGGlyph(truncatingIfNeeded: font.glyph(withName: "bullet"))
                }
            }
            layoutManager.setGlyphs(&generated, properties: &properties,
                                    characterIndexes: &characters, font: font,
                                    forGlyphRange: glyphRange)
            return glyphRange.length
        }

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters), !isExternalUpdate,
                  let editor else { return }
            let oldLength = max(0, editedRange.length - delta)
            let oldRange = NSRange(location: editedRange.location, length: oldLength)
            pendingFenceParity ^= fenceMarkers.countOfIndexes(in: oldRange) % 2
            if let pending = pendingRefreshRange {
                func mapped(_ offset: Int) -> Int {
                    if offset <= oldRange.location { return offset }
                    if offset >= NSMaxRange(oldRange) { return offset + delta }
                    return NSMaxRange(editedRange)
                }
                let start = mapped(pending.location)
                let end = mapped(NSMaxRange(pending))
                pendingRefreshRange = NSRange(location: start, length: max(0, end - start))
            }
            for indexes in [hiddenMarkers, bulletMarkers, fenceMarkers] {
                indexes.remove(in: oldRange)
                indexes.shiftIndexesStarting(at: NSMaxRange(oldRange), by: delta)
            }
            let source = editor.string as NSString
            let scope = affectedLineRange(in: source, around: editedRange)
            hiddenMarkers.remove(in: scope)
            bulletMarkers.remove(in: scope)
            queueRefresh(scope, editor: editor)
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            if !editor.hasMarkedText(), pendingRefreshRange != nil { scheduleRefresh(editor: editor) }
            // A marked string is IME pre-edit text. Keep it inside NSTextView
            // until the input method commits so autosave never persists pinyin.
            if !editor.hasMarkedText(), parent.text != editor.string {
                parent.text = editor.string
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isAdjustingSelection, let editor = notification.object as? NSTextView,
                  !editor.hasMarkedText() else { return }
            let selection = editor.selectedRange()
            defer { lastSelectionLocation = editor.selectedRange().location }
            guard selection.length == 0,
                  selection.location < (editor.string as NSString).length,
                  hiddenMarkers.contains(selection.location),
                  let previous = lastSelectionLocation,
                  previous != selection.location else { return }
            var beginning = selection.location
            while beginning > 0 && hiddenMarkers.contains(beginning - 1) { beginning -= 1 }
            var end = selection.location
            while hiddenMarkers.contains(end) { end += 1 }
            let target = selection.location > previous ? end : beginning
            guard target != selection.location else { return }
            isAdjustingSelection = true
            editor.setSelectedRange(NSRange(location: target, length: 0))
            isAdjustingSelection = false
        }

        private func queueRefresh(_ range: NSRange, editor: NSTextView) {
            if let pending = pendingRefreshRange {
                let start = min(pending.location, range.location)
                let end = max(NSMaxRange(pending), NSMaxRange(range))
                pendingRefreshRange = NSRange(location: start, length: end - start)
            } else {
                pendingRefreshRange = range
            }
            if !editor.hasMarkedText() { scheduleRefresh(editor: editor) }
        }

        private func scheduleRefresh(editor: NSTextView) {
            guard !refreshScheduled else { return }
            refreshScheduled = true
            DispatchQueue.main.async { [weak self, weak editor] in
                guard let self else { return }
                self.refreshScheduled = false
                guard let editor, let pending = self.pendingRefreshRange else { return }
                // Composition commits schedule the pending refresh from textDidChange.
                // Avoid polling and changing glyphs while the input method owns them.
                guard !editor.hasMarkedText() else { return }
                self.processStyleChunk(pending, editor: editor)

            }
        }

        private func processStyleChunk(_ pending: NSRange, editor: NSTextView) {
            let source = editor.string as NSString
            let scope = affectedLineRange(in: source, around: pending)
            guard scope.length > 0 else { pendingRefreshRange = nil; pendingFenceParity = 0; return }
            // Format whole lines, in bounded run-loop turns for large pastes or
            // fence changes. Source text and native undo remain untouched.
            let boundary = min(NSMaxRange(scope), scope.location + 8_192)
            let lineEnd = NSMaxRange(source.lineRange(for: NSRange(location: boundary, length: 0)))
            let end = min(NSMaxRange(scope), lineEnd)
            let chunk = NSRange(location: scope.location, length: end - scope.location)
            let oldFenceCount = fenceMarkers.countOfIndexes(in: chunk)
            restyle(in: chunk, editor: editor)
            pendingFenceParity ^= (oldFenceCount - fenceMarkers.countOfIndexes(in: chunk)) & 1
            if end < NSMaxRange(scope) {
                pendingRefreshRange = NSRange(location: end, length: NSMaxRange(scope) - end)
            } else if pendingFenceParity != 0 && end < source.length {
                pendingFenceParity = 0
                pendingRefreshRange = NSRange(location: end, length: source.length - end)
            } else {
                pendingFenceParity = 0
                pendingRefreshRange = nil
            }
            if pendingRefreshRange != nil { scheduleRefresh(editor: editor) }
            if !editor.hasMarkedText(), parent.text != editor.string { parent.text = editor.string }
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            guard !isExternalUpdate, !isNormalizingEdit, !isApplyingCommand,
                  !textView.hasMarkedText(),
                  textView.undoManager?.isUndoing != true,
                  textView.undoManager?.isRedoing != true,
                  (replacementString ?? "").isEmpty,
                  affectedCharRange.length > 0 else { return true }
            let source = textView.string as NSString
            guard NSMaxRange(affectedCharRange) <= source.length else { return true }
            let selected = textView.selectedRange()
            let touchesHidden = hiddenMarkers.intersects(in: affectedCharRange)
                || bulletMarkers.intersects(in: affectedCharRange)
            let touchesLineBreak = source.substring(with: affectedCharRange).contains("\n")
            guard touchesHidden || touchesLineBreak || selected.length > 0 else { return true }

            let candidates = formattingTokens(in: source, around: affectedCharRange)
            let tokens = candidates.filter { token in
                let touchedMarker = token.markerRanges.contains {
                    NSIntersectionRange($0, affectedCharRange).length > 0
                }
                let selectedAllContent = selected.length > 0
                    && token.visibleRange.length > 0
                    && selected.location <= token.visibleRange.location
                    && NSMaxRange(selected) >= NSMaxRange(token.visibleRange)
                return touchedMarker || selectedAllContent
            }.sorted { $0.fullRange.location > $1.fullRange.location }
            guard !tokens.isEmpty else { return true }

            // Strip each affected wrapper as a single source edit before doing
            // the requested deletion. The selected visible characters keep
            // their positions through an explicit source-offset mapping.
            let undo = textView.undoManager
            undo?.beginUndoGrouping()
            isNormalizingEdit = true
            defer {
                isNormalizingEdit = false
                undo?.endUndoGrouping()
            }
            var start = affectedCharRange.location
            var end = NSMaxRange(affectedCharRange)
            for token in tokens {
                textView.insertText(token.replacement, replacementRange: token.fullRange)
                start = token.mapSourceOffset(start)
                end = token.mapSourceOffset(end)
            }
            let transformed = NSRange(location: start, length: max(0, end - start))
            if selected.length > 0, transformed.length > 0 {
                textView.insertText("", replacementRange: transformed)
                textView.setSelectedRange(NSRange(location: transformed.location, length: 0))
            } else {
                textView.setSelectedRange(NSRange(location: start, length: 0))
            }
            return false
        }

        private struct FormattingToken {
            let fullRange: NSRange
            let visibleRange: NSRange
            let replacement: String
            let markerRanges: [NSRange]

            func mapSourceOffset(_ offset: Int) -> Int {
                let end = NSMaxRange(fullRange)
                let replacementLength = (replacement as NSString).length
                if offset <= fullRange.location { return offset }
                if offset >= end { return offset + replacementLength - fullRange.length }
                if visibleRange.length == 0 { return fullRange.location }
                if offset <= visibleRange.location { return fullRange.location }
                if offset >= NSMaxRange(visibleRange) { return fullRange.location + replacementLength }
                return fullRange.location + offset - visibleRange.location
            }
        }

        private func formattingTokens(in source: NSString, around range: NSRange) -> [FormattingToken] {
            let scope = affectedLineRange(in: source, around: range)
            var tokens: [FormattingToken] = []
            var cursor = scope.location
            while cursor < NSMaxRange(scope) {
                var start = 0
                var end = 0
                var contentsEnd = 0
                source.getLineStart(&start, end: &end, contentsEnd: &contentsEnd,
                                    for: NSRange(location: cursor, length: 0))
                guard end > cursor else { break }
                let contentRange = NSRange(location: start, length: contentsEnd - start)
                let line = source.substring(with: contentRange)
                let local = NSRange(location: 0, length: (line as NSString).length)
                if MarkdownPattern.fence.firstMatch(in: line, range: local) != nil {
                    let preceding = fenceMarkers.countOfIndexes(in: NSRange(location: 0, length: start))
                    let opening = preceding.isMultiple(of: 2) ? start : fenceMarkers.indexLessThanIndex(start)
                    let closing = preceding.isMultiple(of: 2) ? fenceMarkers.indexGreaterThanIndex(start) : start
                    if opening != NSNotFound, closing != NSNotFound,
                       opening < closing, !tokens.contains(where: { $0.fullRange.location == opening }) {
                        let first = source.lineRange(for: NSRange(location: opening, length: 0))
                        let last = source.lineRange(for: NSRange(location: closing, length: 0))
                        let full = NSRange(location: first.location,
                                           length: NSMaxRange(last) - first.location)
                        let visible = NSRange(location: NSMaxRange(first),
                                              length: last.location - NSMaxRange(first))
                        let beforeClosing = last.location > NSMaxRange(first)
                            ? NSRange(location: last.location - 1, length: 1)
                            : NSRange(location: last.location, length: 0)
                        tokens.append(FormattingToken(fullRange: full, visibleRange: visible,
                                                      replacement: source.substring(with: visible),
                                                      markerRanges: [first, beforeClosing, last]))
                    } else if closing == NSNotFound || opening == NSNotFound {
                        let full = NSRange(location: start, length: end - start)
                        tokens.append(FormattingToken(fullRange: full,
                                                      visibleRange: NSRange(location: end, length: 0),
                                                      replacement: "", markerRanges: [full]))
                    }
                    cursor = end
                    continue
                }
                if fenceMarkers.countOfIndexes(in: NSRange(location: 0, length: start)) % 2 == 1 {
                    cursor = end
                    continue
                }
                if let prefix = [MarkdownPattern.heading, MarkdownPattern.bullet,
                                 MarkdownPattern.ordered, MarkdownPattern.quote]
                    .compactMap({ $0.firstMatch(in: line, range: local) }).first {
                    let full = NSRange(location: start, length: prefix.range.length)
                    tokens.append(FormattingToken(fullRange: full,
                                                  visibleRange: NSRange(location: NSMaxRange(full), length: 0),
                                                  replacement: "", markerRanges: [full]))
                }
                let claimed = NSMutableIndexSet()
                for pattern in [MarkdownPattern.code, MarkdownPattern.link,
                                MarkdownPattern.boldStars, MarkdownPattern.boldUnderscores,
                                MarkdownPattern.italicStars, MarkdownPattern.italicUnderscores] {
                    for match in pattern.matches(in: line, range: local) {
                        guard !claimed.intersects(in: match.range) else { continue }
                        claimed.add(in: match.range)
                        let visible = match.range(at: 1)
                        guard visible.location != NSNotFound else { continue }
                        let full = NSRange(location: start + match.range.location,
                                           length: match.range.length)
                        let content = NSRange(location: start + visible.location,
                                              length: visible.length)
                        let before = NSRange(location: full.location,
                                             length: content.location - full.location)
                        let after = NSRange(location: NSMaxRange(content),
                                            length: NSMaxRange(full) - NSMaxRange(content))
                        tokens.append(FormattingToken(fullRange: full, visibleRange: content,
                                                      replacement: source.substring(with: content),
                                                      markerRanges: [before, after]))
                    }
                }
                cursor = end
            }
            return tokens
        }

        func refreshAll(in editor: NSTextView) {
            hiddenMarkers.removeAllIndexes()
            bulletMarkers.removeAllIndexes()
            fenceMarkers.removeAllIndexes()
            pendingRefreshRange = nil
            pendingFenceParity = 0
            lastSelectionLocation = editor.selectedRange().location
            let source = editor.string as NSString
            guard source.length > 0 else { return }
            processStyleChunk(NSRange(location: 0, length: source.length), editor: editor)
        }

        private func affectedLineRange(in source: NSString, around edit: NSRange) -> NSRange {
            guard source.length > 0 else { return NSRange(location: 0, length: 0) }
            let start = max(0, min(edit.location - 1, source.length))
            let end = max(0, min(NSMaxRange(edit) + 1, source.length))
            let first = source.lineRange(for: NSRange(location: start, length: 0))
            let last = source.lineRange(for: NSRange(location: end, length: 0))
            return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        }

        private func clearSyntax(in range: NSRange, editor: NSTextView) {
            guard range.length > 0, let layout = editor.layoutManager else { return }
            hiddenMarkers.remove(in: range)
            bulletMarkers.remove(in: range)
            fenceMarkers.remove(in: range)
            for key in Self.temporaryKeys { layout.removeTemporaryAttribute(key, forCharacterRange: range) }
        }

        private func restyle(in requestedRange: NSRange, editor: NSTextView) {
            let source = editor.string as NSString
            guard source.length > 0, let layout = editor.layoutManager else { return }
            let range = NSIntersectionRange(requestedRange, NSRange(location: 0, length: source.length))
            guard range.length > 0 else { return }
            clearSyntax(in: range, editor: editor)
            var inFence = fenceMarkers.countOfIndexes(in: NSRange(location: 0, length: range.location)) % 2 == 1
            var cursor = range.location
            while cursor < NSMaxRange(range) {
                var start = 0
                var end = 0
                var contentsEnd = 0
                source.getLineStart(&start, end: &end, contentsEnd: &contentsEnd,
                                    for: NSRange(location: cursor, length: 0))
                guard end > cursor else { break }
                let contentRange = NSRange(location: start, length: contentsEnd - start)
                let line = source.substring(with: contentRange)
                if MarkdownPattern.fence.firstMatch(in: line,
                                                    range: NSRange(location: 0, length: (line as NSString).length)) != nil {
                    fenceMarkers.add(start)
                    hiddenMarkers.add(in: contentRange)
                    inFence.toggle()
                } else if inFence {
                    styleCodeBlock(contentRange, layout: layout)
                } else {
                    styleLine(line, sourceStart: start, contentRange: contentRange, layout: layout)
                }
                cursor = end
            }
            layout.invalidateGlyphs(forCharacterRange: range, changeInLength: 0,
                                    actualCharacterRange: nil)
        }

        private func styleLine(_ line: String, sourceStart: Int, contentRange: NSRange,
                               layout: NSLayoutManager) {
            guard contentRange.length > 0 else { return }
            let localRange = NSRange(location: 0, length: (line as NSString).length)
            var prefixLength = 0
            let size = CGFloat(parent.fontSize)
            var inlineSize = size
            if let heading = MarkdownPattern.heading.firstMatch(in: line, range: localRange) {
                let hashes = heading.range(at: 1).length
                prefixLength = heading.range.length
                hiddenMarkers.add(in: NSRange(location: sourceStart, length: prefixLength))
                let headingSize = size + CGFloat(max(0, 7 - hashes * 2))
                inlineSize = headingSize
                layout.addTemporaryAttributes([
                    .font: NSFont.systemFont(ofSize: headingSize, weight: .semibold),
                    .foregroundColor: NSColor.labelColor
                ], forCharacterRange: contentRange)
            } else if let bullet = MarkdownPattern.bullet.firstMatch(in: line, range: localRange) {
                let marker = bullet.range(at: 1).location + sourceStart
                prefixLength = bullet.range.length
                if marker > sourceStart {
                    hiddenMarkers.add(in: NSRange(location: sourceStart, length: marker - sourceStart))
                }
                bulletMarkers.add(marker)
                let suffixStart = marker + 1
                if sourceStart + prefixLength > suffixStart {
                    hiddenMarkers.add(in: NSRange(location: suffixStart,
                                                  length: sourceStart + prefixLength - suffixStart))
                }
                layout.addTemporaryAttribute(.paragraphStyle, value: paragraphStyle(indent: 22),
                                             forCharacterRange: contentRange)
            } else if let ordered = MarkdownPattern.ordered.firstMatch(in: line, range: localRange) {
                prefixLength = ordered.range.length
                let visibleEnd = NSMaxRange(ordered.range(at: 1))
                hiddenMarkers.add(in: NSRange(location: sourceStart + visibleEnd,
                                              length: prefixLength - visibleEnd))
                layout.addTemporaryAttribute(.paragraphStyle, value: paragraphStyle(indent: 27),
                                             forCharacterRange: contentRange)
            } else if let quote = MarkdownPattern.quote.firstMatch(in: line, range: localRange) {
                prefixLength = quote.range.length
                hiddenMarkers.add(in: NSRange(location: sourceStart, length: prefixLength))
                layout.addTemporaryAttributes([
                    .paragraphStyle: paragraphStyle(indent: 19, firstLine: 19),
                    .foregroundColor: NSColor.secondaryLabelColor
                ], forCharacterRange: contentRange)
            }

            // Unsupported constructs stay as editable source text. In particular,
            // inline styling must not hide characters in tables or raw HTML.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("<") || trimmed.contains("|") { return }
            guard line.contains("`") || line.contains("[") || line.contains("*") || line.contains("_") else { return }
            let claimed = NSMutableIndexSet(indexesIn: NSRange(location: 0, length: prefixLength))
            styleInline(MarkdownPattern.code, in: line, sourceStart: sourceStart,
                        claimed: claimed, layout: layout, kind: .code, size: inlineSize)
            styleInline(MarkdownPattern.link, in: line, sourceStart: sourceStart,
                        claimed: claimed, layout: layout, kind: .link, size: inlineSize)
            styleInline(MarkdownPattern.boldStars, in: line, sourceStart: sourceStart,
                        claimed: claimed, layout: layout, kind: .bold, size: inlineSize)
            styleInline(MarkdownPattern.boldUnderscores, in: line, sourceStart: sourceStart,
                        claimed: claimed, layout: layout, kind: .bold, size: inlineSize)
            styleInline(MarkdownPattern.italicStars, in: line, sourceStart: sourceStart,
                        claimed: claimed, layout: layout, kind: .italic, size: inlineSize)
            styleInline(MarkdownPattern.italicUnderscores, in: line, sourceStart: sourceStart,
                        claimed: claimed, layout: layout, kind: .italic, size: inlineSize)
        }

        private enum InlineKind { case code, link, bold, italic }

        private func styleInline(_ pattern: NSRegularExpression, in line: String, sourceStart: Int,
                                 claimed: NSMutableIndexSet, layout: NSLayoutManager, kind: InlineKind,
                                 size: CGFloat) {
            let whole = NSRange(location: 0, length: (line as NSString).length)
            for match in pattern.matches(in: line, range: whole) {
                guard !claimed.intersects(in: match.range) else { continue }
                let visible = match.range(at: 1)
                guard visible.location != NSNotFound else { continue }
                claimed.add(in: match.range)
                hiddenMarkers.add(in: NSRange(location: sourceStart + match.range.location,
                                              length: visible.location - match.range.location))
                let after = NSMaxRange(visible)
                hiddenMarkers.add(in: NSRange(location: sourceStart + after,
                                              length: NSMaxRange(match.range) - after))
                let content = NSRange(location: sourceStart + visible.location, length: visible.length)
                guard content.length > 0 else { continue }
                switch kind {
                case .code:
                    layout.addTemporaryAttributes([
                        .font: NSFont.monospacedSystemFont(ofSize: size * 0.94, weight: .medium),
                        .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.16)
                    ], forCharacterRange: content)
                case .link:
                    layout.addTemporaryAttributes([
                        .foregroundColor: NSColor.labelColor,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ], forCharacterRange: content)
                case .bold:
                    layout.addTemporaryAttribute(.font,
                                                 value: NSFont.systemFont(ofSize: size, weight: .bold),
                                                 forCharacterRange: content)
                case .italic:
                    let italic = NSFontManager.shared.convert(NSFont.systemFont(ofSize: size),
                                                              toHaveTrait: .italicFontMask)
                    layout.addTemporaryAttribute(.font, value: italic, forCharacterRange: content)
                }
            }
        }

        private func styleCodeBlock(_ range: NSRange, layout: NSLayoutManager) {
            guard range.length > 0 else { return }
            layout.addTemporaryAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: CGFloat(parent.fontSize) * 0.94,
                                                  weight: .regular),
                .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.13),
                .paragraphStyle: paragraphStyle(indent: 12, firstLine: 12)
            ], forCharacterRange: range)
        }

        private func paragraphStyle(indent: CGFloat, firstLine: CGFloat = 0) -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = firstLine
            style.headIndent = indent
            style.paragraphSpacing = 4
            return style
        }

        private static let temporaryKeys: [NSAttributedString.Key] = [
            .font, .foregroundColor, .backgroundColor, .underlineStyle, .paragraphStyle
        ]

        func apply(_ action: MarkdownFormatAction, in editor: NSTextView) {
            let source = editor.string as NSString
            let selection = editor.selectedRange()
            guard selection.location <= source.length, NSMaxRange(selection) <= source.length else { return }
            isApplyingCommand = true
            defer { isApplyingCommand = false }
            switch action {
            case .heading1: changeLinePrefix(in: editor, selection: selection,
                                             pattern: MarkdownPattern.heading, prefix: "# ")
            case .heading2: changeLinePrefix(in: editor, selection: selection,
                                             pattern: MarkdownPattern.heading, prefix: "## ")
            case .bullet: changeLinePrefix(in: editor, selection: selection,
                                           pattern: MarkdownPattern.bullet, prefix: "- ")
            case .quote: changeLinePrefix(in: editor, selection: selection,
                                          pattern: MarkdownPattern.quote, prefix: "> ")
            case .bold: wrapSelection(in: editor, selection: selection,
                                      opening: "**", closing: "**", placeholder: "加粗文字")
            case .italic: wrapSelection(in: editor, selection: selection,
                                        opening: "*", closing: "*", placeholder: "斜体文字")
            case .code:
                let multiline = source.substring(with: selection).contains("\n")
                if multiline {
                    wrapSelection(in: editor, selection: selection, opening: "```\n",
                                  closing: "\n```", placeholder: "代码")
                } else {
                    wrapSelection(in: editor, selection: selection, opening: "`",
                                  closing: "`", placeholder: "代码")
                }
            case .link:
                editLink(in: editor, selection: selection)
            }
        }

        private func wrapSelection(in editor: NSTextView, selection: NSRange,
                                   opening: String, closing: String, placeholder: String) {
            let source = editor.string as NSString
            let inner = selection.length > 0 ? source.substring(with: selection) : placeholder
            editor.insertText(opening + inner + closing, replacementRange: selection)
            if selection.length == 0 {
                editor.setSelectedRange(NSRange(location: selection.location + (opening as NSString).length,
                                                length: (placeholder as NSString).length))
            }
        }

        private func changeLinePrefix(in editor: NSTextView, selection: NSRange,
                                      pattern: NSRegularExpression, prefix: String) {
            let source = editor.string as NSString
            let lineRange = source.lineRange(for: NSRange(location: min(selection.location, source.length),
                                                         length: 0))
            let line = source.substring(with: lineRange)
            let match = pattern.firstMatch(in: line, range: NSRange(location: 0,
                                                                  length: (line as NSString).length))
            let oldPrefixLength = match?.range.length ?? 0
            let existing = source.substring(with: NSRange(location: lineRange.location,
                                                          length: oldPrefixLength))
            let replacement = existing == prefix ? "" : prefix
            editor.insertText(replacement, replacementRange: NSRange(location: lineRange.location,
                                                                      length: oldPrefixLength))
            let delta = (replacement as NSString).length - oldPrefixLength
            editor.setSelectedRange(NSRange(location: max(lineRange.location,
                                                          selection.location + delta),
                                            length: selection.length))
        }

        private func editLink(in editor: NSTextView, selection: NSRange) {
            let source = editor.string as NSString
            let lineRange = source.lineRange(for: NSRange(location: selection.location, length: 0))
            let line = source.substring(with: lineRange)
            var target = selection
            var label = selection.length > 0 ? source.substring(with: selection) : "链接文字"
            var address = "https://"
            for match in MarkdownPattern.link.matches(
                in: line, range: NSRange(location: 0, length: (line as NSString).length)
            ) {
                let visible = NSRange(location: lineRange.location + match.range(at: 1).location,
                                      length: match.range(at: 1).length)
                if selection.location >= visible.location && selection.location <= NSMaxRange(visible) {
                    target = NSRange(location: lineRange.location + match.range.location,
                                     length: match.range.length)
                    label = source.substring(with: visible)
                    address = (line as NSString).substring(with: match.range(at: 2))
                    break
                }
            }
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 330, height: 24))
            field.stringValue = address
            field.placeholderString = "https://"
            let alert = NSAlert()
            alert.messageText = "链接地址"
            alert.accessoryView = field
            alert.addButton(withTitle: "完成")
            alert.addButton(withTitle: "取消")
            let replace = { [weak editor] (response: NSApplication.ModalResponse) in
                guard response == .alertFirstButtonReturn, let editor else { return }
                let replacement = "[\(label)](\(field.stringValue))"
                editor.insertText(replacement, replacementRange: target)
                if selection.length == 0 && target == selection {
                    editor.setSelectedRange(NSRange(location: target.location + 1,
                                                    length: (label as NSString).length))
                }
                editor.window?.makeFirstResponder(editor)
            }
            if let window = editor.window {
                alert.beginSheetModal(for: window, completionHandler: replace)
                DispatchQueue.main.async { alert.window.makeFirstResponder(field) }
            } else {
                replace(alert.runModal())
            }
        }
    }
}

private enum MarkdownPattern {
    static let fence = try! NSRegularExpression(pattern: "^ {0,3}`{3,}.*$")
    static let heading = try! NSRegularExpression(pattern: "^(#{1,6})[ \\t]+")
    static let bullet = try! NSRegularExpression(pattern: "^[ \\t]*([-+*])[ \\t]+")
    static let ordered = try! NSRegularExpression(pattern: "^([0-9]+\\.)[ \\t]+")
    static let quote = try! NSRegularExpression(pattern: "^[ \\t]*>[ \\t]+")
    static let code = try! NSRegularExpression(pattern: "(?<!\\\\)`([^`\\n]+)`")
    static let link = try! NSRegularExpression(pattern: "(?<![!\\\\])\\[([^]\\n]+)\\]\\(([^)\\n]*)\\)")
    static let boldStars = try! NSRegularExpression(pattern: "(?<!\\\\)\\*\\*([^*\\n]+)\\*\\*")
    static let boldUnderscores = try! NSRegularExpression(pattern: "(?<!\\\\)__([^_\\n]+)__")
    static let italicStars = try! NSRegularExpression(pattern: "(?<!\\\\)(?<!\\*)\\*([^*\\n]+)\\*(?!\\*)")
    static let italicUnderscores = try! NSRegularExpression(pattern: "(?<!\\\\)(?<!_)_([^_\\n]+)_(?!_)")
}
