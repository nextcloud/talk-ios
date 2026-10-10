//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

protocol WaterfallLayoutDelegate: AnyObject {
    /// The aspect ratio (width / height) of the item at `indexPath`. Must not change once the item has
    /// been placed, as the layout relies on that to never move already placed items.
    func waterfallLayout(_ layout: WaterfallLayout, aspectRatioForItemAt indexPath: IndexPath) -> CGFloat

    /// The height of the full-width header above `section`, or 0 for none.
    func waterfallLayout(_ layout: WaterfallLayout, heightForHeaderInSection section: Int) -> CGFloat
}

extension WaterfallLayoutDelegate {
    func waterfallLayout(_ layout: WaterfallLayout, heightForHeaderInSection section: Int) -> CGFloat {
        return 0
    }
}

/// A masonry ("waterfall") layout: items share a column width but keep their own aspect ratio, each
/// placed into the currently shortest column. Unlike a flow layout with fixed item sizes, this shows
/// images without letterboxing or cropping them. Each section starts new columns below the previous one.
class WaterfallLayout: UICollectionViewLayout {

    weak var delegate: WaterfallLayoutDelegate?

    var interItemSpacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    var sectionSpacing: CGFloat = 16
    var sectionInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

    /// The column count is derived from the available width to stay close to this, which keeps items
    /// a sensible size on a phone, an iPad sheet and a full-screen iPad window alike.
    var preferredColumnWidth: CGFloat = 165

    /// The preferred width alone would give a single full-width column on the narrowest phones
    var minimumColumnCount = 2

    /// Clamped, so that one very tall or very wide item cannot unbalance a whole column
    private static let minAspectRatio: CGFloat = 0.55
    private static let maxAspectRatio: CGFloat = 2.2

    private static func clampedAspectRatio(_ aspectRatio: CGFloat) -> CGFloat {
        return min(max(aspectRatio, Self.minAspectRatio), Self.maxAspectRatio)
    }

    private var itemAttributesCache: [[UICollectionViewLayoutAttributes]] = []
    private var headerAttributesCache: [Int: UICollectionViewLayoutAttributes] = [:]
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

        self.itemAttributesCache.removeAll(keepingCapacity: true)
        self.headerAttributesCache.removeAll(keepingCapacity: true)
        self.contentHeight = 0

        guard let collectionView = self.collectionView else { return }

        let sectionCount = collectionView.numberOfSections
        let insets = self.horizontalInsets
        let availableWidth = self.contentWidth - insets.left - insets.right

        guard sectionCount > 0, availableWidth > 0 else { return }

        // Recomputed in full on every invalidation: placement is deterministic, so existing items
        // keep identical frames and no cached state can go stale (a new search can return the same
        // number of items with entirely different sizes).
        let columnCount = max(self.minimumColumnCount, Int((availableWidth + self.interItemSpacing) / (self.preferredColumnWidth + self.interItemSpacing)))
        let itemWidth = ((availableWidth - self.interItemSpacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)).rounded(.down)

        var sectionTop = self.sectionInset.top
        var contentBottom: CGFloat?

        for section in 0..<sectionCount {
            let itemCount = collectionView.numberOfItems(inSection: section)
            let headerHeight = self.delegate?.waterfallLayout(self, heightForHeaderInSection: section) ?? 0
            var sectionItemAttributes: [UICollectionViewLayoutAttributes] = []

            if headerHeight > 0 {
                let attributes = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                                                  with: IndexPath(item: 0, section: section))
                attributes.frame = CGRect(x: insets.left, y: sectionTop, width: availableWidth, height: headerHeight)
                self.headerAttributesCache[section] = attributes

                sectionTop += headerHeight
            }

            var columnBottoms = [CGFloat](repeating: sectionTop, count: columnCount)

            for item in 0..<itemCount {
                let indexPath = IndexPath(item: item, section: section)

                // `min(by:)` returns the first of equally short columns, so the first row fills left to right
                let column = columnBottoms.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0

                let aspectRatio = self.delegate?.waterfallLayout(self, aspectRatioForItemAt: indexPath) ?? 1
                let itemHeight = (itemWidth / Self.clampedAspectRatio(aspectRatio)).rounded()

                let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
                attributes.frame = CGRect(x: insets.left + (itemWidth + self.interItemSpacing) * CGFloat(column),
                                          y: columnBottoms[column],
                                          width: itemWidth,
                                          height: itemHeight)

                sectionItemAttributes.append(attributes)

                columnBottoms[column] = attributes.frame.maxY + self.lineSpacing
            }

            self.itemAttributesCache.append(sectionItemAttributes)

            guard itemCount > 0 || headerHeight > 0 else { continue }

            // The trailing line spacing of the tallest column is not part of the content
            let sectionBottom = itemCount > 0 ? (columnBottoms.max() ?? sectionTop) - self.lineSpacing : sectionTop

            contentBottom = sectionBottom
            sectionTop = sectionBottom + self.sectionSpacing
        }

        if let contentBottom {
            self.contentHeight = contentBottom + self.sectionInset.bottom
        }
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        let items = self.itemAttributesCache.joined().filter { $0.frame.intersects(rect) }
        let headers = self.headerAttributesCache.values.filter { $0.frame.intersects(rect) }

        return items + headers
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.section < self.itemAttributesCache.count,
              indexPath.item < self.itemAttributesCache[indexPath.section].count
        else { return nil }

        return self.itemAttributesCache[indexPath.section][indexPath.item]
    }

    override func layoutAttributesForSupplementaryView(ofKind elementKind: String, at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard elementKind == UICollectionView.elementKindSectionHeader else { return nil }

        return self.headerAttributesCache[indexPath.section]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView = self.collectionView else { return false }

        // Only the width matters (column count and item width); scrolling must not invalidate
        return newBounds.width != collectionView.bounds.width
    }
}
