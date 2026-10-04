import SwiftUI

struct SearchMatchText: View {
    @Environment(\.appAccentStyle) private var accent
    let text: String
    let query: String
    var selected = false

    var body: some View { Text(highlighted) }

    private var highlighted: AttributedString {
        var result = AttributedString(text)
        for word in Set(query.split(whereSeparator: \.isWhitespace).map(String.init)) {
            var cursor = text.startIndex
            while cursor < text.endIndex,
                  let hit = text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive],
                                       range: cursor..<text.endIndex, locale: Locale(identifier: "en_US_POSIX")) {
                if let range = Range(hit, in: result) {
                    result[range].foregroundColor = selected ? accent.selectedForeground : accent.actionForeground
                    result[range].backgroundColor = selected
                        ? accent.selectedForeground.opacity(0.15) : accent.selectedFill.opacity(0.15)
                    result[range].inlinePresentationIntent = .stronglyEmphasized
                }
                cursor = hit.upperBound
            }
        }
        return result
    }
}

struct PromptTagOverflow: View {
    let names: [String]
    @State private var showing = false

    var body: some View {
        Button { showing.toggle() } label: {
            Text("+\(names.count)").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(names.map { "#" + $0 }.joined(separator: "、"))
        .accessibilityLabel("查看其他 \(names.count) 个标签")
        .popover(isPresented: $showing) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(names, id: \.self) { Text("#" + $0).font(.callout) }
            }.padding(16)
        }
    }
}
