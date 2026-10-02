import AppKit
import SwiftUI

enum PromptPresentation {
    private static let previewPrefix = try! NSRegularExpression(
        pattern: #"^\s{0,3}(?:#{1,6}|>|[-*+]\s|\d+\.)\s*"#)
    private static let previewMarkers = try! NSRegularExpression(pattern: #"[\*_\x60]+"#)
    static func date(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh_CN")))
        if calendar.isDateInToday(date) { return "今天 \(time)" }
        if calendar.isDateInYesterday(date) { return "昨天 \(time)" }
        return date.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN")))
    }

    static func preview(_ content: String) -> String {
        var lines: [String] = []
        content.enumerateSubstrings(in: content.startIndex..<content.endIndex, options: .byLines) {
            line, _, _, stop in
            guard let line else { return }
            let stripped = previewPrefix.stringByReplacingMatches(
                in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "")
            let visible = previewMarkers.stringByReplacingMatches(
                in: stripped, range: NSRange(stripped.startIndex..., in: stripped), withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !visible.isEmpty { lines.append(visible) }
            stop = lines.count == 6
        }
        return lines.joined(separator: "\n")
    }

    static func croppedImage(for prompt: Prompt) -> NSImage? {
        guard let path = prompt.coverPath,
              let source = PromptStorage.loadCover(at: path) else { return nil }
        // Older libraries retain crop metadata for archive compatibility. The
        // presentation always uses the complete source image now.
        return source
    }

    static func crop(_ image: NSImage, to crop: CoverCrop) -> NSImage {
        guard crop != .full,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let width = CGFloat(cg.width), height = CGFloat(cg.height)
        let rect = CGRect(x: CGFloat(crop.x) * width, y: CGFloat(crop.y) * height,
                          width: CGFloat(crop.width) * width, height: CGFloat(crop.height) * height)
            .integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cut = cg.cropping(to: rect), !rect.isEmpty else { return image }
        return NSImage(cgImage: cut, size: NSSize(width: rect.width, height: rect.height))
    }
}

struct PromptCardView: View {
    @Environment(\.appAccentStyle) private var accent
    let prompt: Prompt
    let selected: Bool
    var searchQuery = ""
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onFavorite: () -> Void

    var body: some View {
        let tagNames = prompt.tagNames
        VStack(alignment: .leading, spacing: 0) {
            media
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipped()
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    SearchMatchText(text: prompt.title.isEmpty ? "未命名 Prompt" : prompt.title, query: searchQuery)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(prompt.title)
                    Text(PromptPresentation.date(prompt.updatedAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                HStack(spacing: 4) {
                    ForEach(Array(tagNames.prefix(3)), id: \.self) { tag in
                        SearchMatchText(text: "#\(tag)", query: searchQuery)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(accent.controlFill, in: Capsule())
                    }
                    if tagNames.count > 3 {
                        PromptTagOverflow(names: Array(tagNames.dropFirst(3)))
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 22)
            }
            .padding(.horizontal, 9).padding(.vertical, 11)
        }
        .modifier(PromptHoverSurface(selected: selected, isCard: true))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.75)
        }
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture(count: 2, perform: onOpen)
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(prompt.title)
    }

    private var media: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                CoverThumbnail(prompt: prompt, maxPixelSize: 768, prioritizeVisible: true) {
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(Color(nsColor: .textBackgroundColor))
                        if prompt.coverPath == nil {
                            let preview = PromptPresentation.preview(prompt.content)
                            Text(preview.isEmpty ? "空白 Prompt" : preview)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(nsColor: .textColor))
                                .lineSpacing(3)
                                .lineLimit(6)
                                .padding(13)
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                if prompt.deletedAt == nil {
                    HStack {
                        Button(action: onFavorite) {
                            Image(systemName: prompt.isFavorite ? "star.fill" : "star")
                                .foregroundStyle(prompt.isFavorite ? accent.actionForeground : Color.primary)
                        }
                        .accessibilityLabel(prompt.isFavorite ? "取消收藏" : "收藏")
                        Spacer()
                        Button(action: onCopy) {
                            Image(systemName: "doc.on.doc")
                                .foregroundStyle(Color.primary)
                        }
                            .accessibilityLabel("复制 Prompt")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(MediaButtonStyle())
                    .padding(7)
                }
            }
        }
    }
}

/// Hover changes only the surface, leaving text, tags and thumbnail loading intact.
private struct PromptHoverSurface: ViewModifier {
    @Environment(\.appAccentStyle) private var accent
    @State private var isHovering = false
    let selected: Bool
    var isCard = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if isCard {
            content
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(selected ? accent.softSelection : isHovering ? accent.hoverFill : Color.clear)
                        }
                }
                .onHover { isHovering = $0 }
        } else {
            content
                .background(selected ? accent.softSelection : isHovering ? accent.hoverFill : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .onHover { isHovering = $0 }
        }
    }
}

private struct MediaButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverableMediaButton(configuration: configuration)
    }

    private struct HoverableMediaButton: View {
        let configuration: ButtonStyle.Configuration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .frame(width: 23, height: 23)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.94),
                            in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(isHovering ? 0.10 : 0))
                        .allowsHitTesting(false)
                }
                .opacity(configuration.isPressed ? 0.7 : 1)
                .onHover { isHovering = $0 }
        }
    }
}

/// Compact rows share the preloaded thumbnail cache with the other library views.
struct PromptListRow: View {
    @Environment(\.appAccentStyle) private var accent
    let prompt: Prompt
    let selected: Bool
    var searchQuery = ""
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) { row }
            .buttonStyle(.plain)
            .accessibilityLabel(prompt.title.isEmpty ? "未命名 Prompt" : prompt.title)
            .accessibilityValue(selected ? "已选择" : "未选择")
    }

    private var row: some View {
        HStack(spacing: 10) {
            if prompt.coverPath != nil {
                CoverThumbnail(prompt: prompt, maxPixelSize: 192, prioritizeVisible: true) {
                    Image(systemName: "photo")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: 64, height: 36)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    SearchMatchText(text: prompt.title.isEmpty ? "未命名 Prompt" : prompt.title, query: searchQuery)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .help(prompt.title)
                    if prompt.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(accent.actionForeground)
                            .accessibilityLabel("已收藏")
                    }
                }
                HStack(spacing: 6) {
                    Text(PromptPresentation.date(prompt.updatedAt))
                        .fixedSize()
                    Text(PromptPresentation.preview(prompt.content).replacingOccurrences(of: "\n", with: " "))
                        .lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .frame(height: 66)
        .modifier(PromptHoverSurface(selected: selected))
        .contentShape(Rectangle())
    }
}
