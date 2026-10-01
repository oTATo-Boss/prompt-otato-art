import AppKit
import SwiftUI

/// Match the existing adaptive GridItem's widths, spacing and centered columns.
struct PromptGridMetrics: Equatable {
    let columns: Int
    let itemSize: CGSize
    let sideInset: CGFloat
    let height: CGFloat

    init(width: CGFloat, minimumWidth: CGFloat, count: Int) {
        let width = max(1, width)
        columns = max(1, Int((width + 16) / (minimumWidth + 16)))
        let itemWidth = min(minimumWidth + 45, (width - CGFloat(columns - 1) * 16) / CGFloat(columns))
        itemSize = CGSize(width: itemWidth, height: itemWidth * 9 / 16 + 69)
        sideInset = max(0, (width - CGFloat(columns) * itemWidth - CGFloat(columns - 1) * 16) / 2)
        let rows = (count + columns - 1) / columns
        height = CGFloat(rows) * itemSize.height + CGFloat(max(0, rows - 1)) * 16
    }
}

/// The collection owns its viewport so only visible cards need hosting views.
/// Scrolling moves AppKit layers without laying out the whole SwiftUI grid.
struct NativePromptGrid: NSViewRepresentable {
    @Environment(\.appAccentStyle) private var accent
    let prompts: [Prompt]
    let minimumWidth: CGFloat
    var topInset: CGFloat = 0
    let selection: UUID?
    let card: (Prompt) -> AnyView

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.wantsLayer = true
        scroll.automaticallyAdjustsContentInsets = false
        let collection = PromptCollectionView()
        collection.frame = scroll.contentView.bounds
        collection.autoresizingMask = [.width]
        collection.backgroundColors = [.clear]
        collection.wantsLayer = true
        collection.isSelectable = false
        // Assigning a modern layout replaces AppKit's legacy collection core;
        // register the reusable item class after that core has been created.
        collection.collectionViewLayout = PromptGridLayout()
        collection.register(PromptCardItem.self, forItemWithIdentifier: Coordinator.itemIdentifier)
        collection.dataSource = context.coordinator
        collection.delegate = context.coordinator
        scroll.documentView = collection
        context.coordinator.update(collection, parent: self)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let collection = scroll.documentView as? PromptCollectionView else { return }
        if scroll.contentInsets.top != topInset {
            let wasAtTop = scroll.contentView.bounds.minY <= -scroll.contentInsets.top + 0.5
            scroll.contentInsets.top = topInset
            scroll.scrollerInsets.top = topInset
            if wasAtTop {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: -topInset))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        context.coordinator.update(collection, parent: self)
    }

    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        static let itemIdentifier = NSUserInterfaceItemIdentifier("PromptCard")
        private var parent: NativePromptGrid
        private var ids: [UUID] = []
        private var selection: UUID?
        private var accent: AppAccentStyle?

        init(_ parent: NativePromptGrid) { self.parent = parent }

        func update(_ collection: NSCollectionView, parent: NativePromptGrid) {
            let oldSelection = selection
            let changedAccent = accent?.palette != parent.accent.palette || accent?.colorScheme != parent.accent.colorScheme
            self.parent = parent
            selection = parent.selection
            accent = parent.accent
            if let layout = collection.collectionViewLayout as? PromptGridLayout,
               layout.minimumWidth != parent.minimumWidth {
                layout.minimumWidth = parent.minimumWidth
                layout.invalidateLayout()
            }
            let nextIDs = parent.prompts.map(\.id)
            if ids != nextIDs {
                ids = nextIDs
                collection.reloadData()
            } else if oldSelection != selection || changedAccent {
                for item in collection.visibleItems() {
                    guard let item = item as? PromptCardItem,
                          let index = collection.indexPath(for: item)?.item,
                          parent.prompts.indices.contains(index) else { continue }
                    let prompt = parent.prompts[index]
                    if changedAccent || prompt.id == oldSelection || prompt.id == selection {
                        configure(item, prompt: prompt)
                    }
                }
            }
        }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.prompts.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: Self.itemIdentifier, for: indexPath) as! PromptCardItem
            configure(item, prompt: parent.prompts[indexPath.item])
            return item
        }

        func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem,
                            forRepresentedObjectAt indexPath: IndexPath) {
            guard let item = item as? PromptCardItem, parent.prompts.indices.contains(indexPath.item) else { return }
            // A cached offscreen card may have missed a theme or selection change.
            configure(item, prompt: parent.prompts[indexPath.item])
        }

        private func configure(_ item: PromptCardItem, prompt: Prompt) {
            let presentation = PromptCardPresentation(id: prompt.id, selected: parent.selection == prompt.id,
                                                      palette: parent.accent.palette, scheme: parent.accent.colorScheme)
            guard item.presentation != presentation else { return }
            item.presentation = presentation
            item.host.rootView = AnyView(parent.card(prompt)
                .environment(\.appAccentStyle, parent.accent)
                .environment(\.colorScheme, parent.accent.colorScheme)
                .id(prompt.id))
        }
    }
}

/// Fixed arithmetic for the established adaptive grid. Bounds scrolling only
/// asks for intersecting rows; it does not invalidate sizes or SwiftUI hosts.
final class PromptGridLayout: NSCollectionViewLayout {
    var minimumWidth: CGFloat = 230
    private var metrics = PromptGridMetrics(width: 1, minimumWidth: 230, count: 0)
    private var width: CGFloat = 0
    private var count = 0

    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        width = collectionView.bounds.width
        count = collectionView.numberOfItems(inSection: 0)
        metrics = PromptGridMetrics(width: width - 40, minimumWidth: minimumWidth, count: count)
    }

    override var collectionViewContentSize: NSSize {
        NSSize(width: width, height: metrics.height + 35)
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        newBounds.width != width
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        guard count > 0 else { return [] }
        let stride = metrics.itemSize.height + 16
        let first = max(0, Int(floor((rect.minY - 15) / stride))) * metrics.columns
        let last = min(count, (max(0, Int(floor((rect.maxY - 15) / stride))) + 1) * metrics.columns)
        guard first < last else { return [] }
        return (first..<last).compactMap { layoutAttributesForItem(at: IndexPath(item: $0, section: 0)) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        guard indexPath.section == 0, indexPath.item < count else { return nil }
        let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
        attributes.frame = NSRect(
            x: 20 + metrics.sideInset + CGFloat(indexPath.item % metrics.columns) * (metrics.itemSize.width + 16),
            y: 15 + CGFloat(indexPath.item / metrics.columns) * (metrics.itemSize.height + 16),
            width: metrics.itemSize.width, height: metrics.itemSize.height)
        return attributes
    }
}

final class PromptCollectionView: NSCollectionView {
    // The surrounding library owns arrow, Return and Space navigation.
    override var acceptsFirstResponder: Bool { false }
}

private struct PromptCardPresentation: Equatable {
    let id: UUID
    let selected: Bool
    let palette: AppAccentPalette
    let scheme: ColorScheme
}

private final class PromptCardItem: NSCollectionViewItem {
    let host = NSHostingView(rootView: AnyView(EmptyView()))
    var presentation: PromptCardPresentation?

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nil, bundle: nil)
        installHost()
    }

    private func installHost() {
        let container = NSView()
        container.wantsLayer = true
        // Each card has a known size. Asking every host for min/intrinsic size
        // would re-enter SwiftUI layout while the collection is positioning it.
        host.sizingOptions = []
        host.safeAreaRegions = []
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        view = container
    }

    required init?(coder: NSCoder) { fatalError("Cards are created programmatically") }

    override func viewDidLayout() {
        super.viewDidLayout()
        if host.frame != view.bounds { host.frame = view.bounds }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        presentation = nil
        host.rootView = AnyView(EmptyView())
    }
}
