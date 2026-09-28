import AppKit
import SwiftUI

enum PromptPresentation {
    static func date(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh_CN")))
        if calendar.isDateInToday(date) { return "今天 \(time)" }
        if calendar.isDateInYesterday(date) { return "昨天 \(time)" }
        return date.formatted(.dateTime.month().day().locale(Locale(identifier: "zh_CN")))
    }

    static func preview(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
            .map { line in
                line.replacingOccurrences(of: #"^\s{0,3}(?:#{1,6}|>|[-*+]\s|\d+\.)\s*"#,
                                          with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"[\*_\x60]+"#, with: "",
                                          options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        return lines.prefix(6).joined(separator: "\n")
    }

    static func croppedImage(for prompt: Prompt) -> NSImage? {
        guard let path = prompt.coverPath,
              let source = PromptStorage.loadCover(at: path) else { return nil }
        return crop(source, to: prompt.coverCrop)
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
    let prompt: Prompt
    let selected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onFavorite: () -> Void

    private var image: NSImage? { PromptPresentation.croppedImage(for: prompt) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            media
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipped()
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(prompt.title.isEmpty ? "未命名 Prompt" : prompt.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(PromptPresentation.date(prompt.updatedAt))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                HStack(spacing: 4) {
                    ForEach(Array(prompt.tagNames.prefix(3)), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                    if prompt.tagNames.count > 3 {
                        Text("+\(prompt.tagNames.count - 3)")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 22)
            }
            .padding(.horizontal, 9).padding(.vertical, 11)
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(selected ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.6),
                              lineWidth: selected ? 2 : 0.5)
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
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    Rectangle().fill(Color(red: 0.10, green: 0.11, blue: 0.12))
                    Text(PromptPresentation.preview(prompt.content).isEmpty
                         ? "空白 Prompt" : PromptPresentation.preview(prompt.content))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineSpacing(3)
                        .lineLimit(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(13)
                }
                if prompt.deletedAt == nil {
                    HStack {
                        Button(action: onFavorite) {
                            Image(systemName: prompt.isFavorite ? "star.fill" : "star")
                                .foregroundStyle(prompt.isFavorite ? Color.yellow : image == nil ? Color.white : Color.primary)
                        }
                        .accessibilityLabel(prompt.isFavorite ? "取消收藏" : "收藏")
                        Spacer()
                        Button(action: onCopy) {
                            Image(systemName: "doc.on.doc")
                                .foregroundStyle(image == nil ? Color.white : Color.primary)
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

private struct MediaButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 23, height: 23)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct PromptListRow: View {
    let prompt: Prompt
    let folderName: String
    let selected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onCopy: () -> Void
    let onFavorite: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image = PromptPresentation.croppedImage(for: prompt) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: prompt.format == .markdown ? "doc.richtext" : "doc.text")
                        .font(.system(size: 20)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .textBackgroundColor))
                }
            }
            .frame(width: 72, height: 47).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 4) {
                Text(prompt.title.isEmpty ? "未命名 Prompt" : prompt.title)
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(PromptPresentation.preview(prompt.content))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 10)
            Text(folderName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            Text(PromptPresentation.date(prompt.updatedAt))
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize()
            if prompt.deletedAt == nil {
                Button(action: onFavorite) {
                    Image(systemName: prompt.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(prompt.isFavorite ? Color.yellow : Color.secondary)
                }
                .accessibilityLabel(prompt.isFavorite ? "取消收藏" : "收藏")
                Button(action: onCopy) { Image(systemName: "doc.on.doc") }
                    .accessibilityLabel("复制 Prompt")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10).frame(height: 65)
        .background(selected ? Color.accentColor.opacity(0.13) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onOpen)
        .onTapGesture(perform: onSelect)
    }
}
