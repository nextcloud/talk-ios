//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

protocol GiphyWaterfallLayoutDelegate: AnyObject {
    /// The aspect ratio (width / height) of the item at `index`. Must not change once the item has
    /// been placed, as the layout relies on that to never move already placed items.
    func waterfallLayout(_ layout: GiphyWaterfallLayout, aspectRatioForItemAt index: Int) -> CGFloat
}

/// A masonry ("waterfall") layout: items share a column width but keep their own aspect ratio, each
/// placed into the currently shortest column. Unlike a flow layout with fixed item sizes, this shows
/// GIFs without letterboxing or cropping them.
class GiphyWaterfallLayout: UICollectionViewLayout {

    weak var delegate: GiphyWaterfallLayoutDelegate?

    var interItemSpacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    var sectionInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

    /// The column count is derived from the available width to stay close to this, which keeps GIFs
    /// a sensible size on a phone, an iPad sheet and a full-screen iPad window alike.
    var preferredColumnWidth: CGFloat = 165

    /// The preferred width alone would give a single full-width column on the narrowest phones
    var minimumColumnCount = 2

    /// Clamped, so that one very tall or very wide GIF cannot unbalance a whole column
    private static let minAspectRatio: CGFloat = 0.55
    private static let maxAspectRatio: CGFloat = 2.2

    private var attributesCache: [UICollectionViewLayoutAttributes] = []
    private var contentHeight: CGFloat = 0

    private var contentWidth: CGFloat {
        return self.collectionView?.bounds.width ?? 0
    }

    /// The section inset, widened by the horizontal safe area (e.g. the notch in landscape).
    ///
    /// Insetting the items rather than narrowing the content avoids making the content width depend
    /// on the adjusted content inset, which in turn depends on the content size computed from it.
    private var horizontalInsets: (left: CGFloat, right: CGFloat) {
        let safeAreaInsets = self.collectionView?.safeAreaInsets ?? .zero

        return (self.sectionInset.left + safeAreaInsets.left, self.sectionInset.right + safeAreaInsets.right)
    }

    override var collectionViewContentSize: CGSize {
        return CGSize(width: self.contentWidth, height: self.contentHeight)
    }

    override func prepare() {
        super.prepare()

        self.attributesCache.removeAll(keepingCapacity: true)
        self.contentHeight = 0

        guard let collectionView = self.collectionView else { return }

        let itemCount = collectionView.numberOfItems(inSection: 0)
        let insets = self.horizontalInsets
        let availableWidth = self.contentWidth - insets.left - insets.right

        guard itemCount > 0, availableWidth > 0 else { return }

        // Recomputed in full on every invalidation: placement is deterministic, so existing items
        // keep identical frames and no cached state can go stale (a new search can return the same
        // number of items with entirely different sizes).
        let columnCount = max(self.minimumColumnCount, Int((availableWidth + self.interItemSpacing) / (self.preferredColumnWidth + self.interItemSpacing)))
        let itemWidth = ((availableWidth - self.interItemSpacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)).rounded(.down)

        var columnBottoms = [CGFloat](repeating: self.sectionInset.top, count: columnCount)

        for item in 0..<itemCount {
            // `min(by:)` returns the first of equally short columns, so the first row fills left to right
            let column = columnBottoms.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0

            let aspectRatio = self.delegate?.waterfallLayout(self, aspectRatioForItemAt: item) ?? 1
            let clampedAspectRatio = min(max(aspectRatio, Self.minAspectRatio), Self.maxAspectRatio)
            let itemHeight = (itemWidth / clampedAspectRatio).rounded()

            let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: item, section: 0))
            attributes.frame = CGRect(x: insets.left + (itemWidth + self.interItemSpacing) * CGFloat(column),
                                      y: columnBottoms[column],
                                      width: itemWidth,
                                      height: itemHeight)

            self.attributesCache.append(attributes)

            columnBottoms[column] = attributes.frame.maxY + self.lineSpacing
        }

        // The trailing line spacing of the tallest column is not part of the content
        let contentBottom = (columnBottoms.max() ?? self.sectionInset.top) - self.lineSpacing

        self.contentHeight = contentBottom + self.sectionInset.bottom
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        return self.attributesCache.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.section == 0, indexPath.item < self.attributesCache.count else { return nil }

        return self.attributesCache[indexPath.item]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView = self.collectionView else { return false }

        // Only the width matters (column count and item width); scrolling must not invalidate
        return newBounds.width != collectionView.bounds.width
    }
}
