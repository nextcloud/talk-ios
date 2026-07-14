//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

// Layout for the speaker view: the promoted participant (item 0) is shown fullscreen
// above a horizontally scrollable stripe with the other participants at the bottom.
// Based on the "speaker view" of the web client:
// https://github.com/nextcloud/spreed/blob/main/src/components/CallView/CallView.vue
@objcMembers
class CallSpeakerLayout: UICollectionViewLayout {

    public var isStripeHidden = false {
        didSet {
            invalidateLayout()
        }
    }

    private let spacing: CGFloat = 8
    private let stripeItemAspectRatio: CGFloat = 1.5

    private var itemAttributes: [UICollectionViewLayoutAttributes] = []
    private var contentSize: CGSize = .zero

    private var stripeItemMinSize: CGSize {
        return CGSize(width: (kCallParticipantCellMinHeight * stripeItemAspectRatio).rounded(.down), height: kCallParticipantCellMinHeight)
    }

    override var collectionViewContentSize: CGSize {
        return contentSize
    }

    override func prepare() {
        super.prepare()

        itemAttributes = []
        contentSize = .zero

        guard let collectionView else { return }

        let numberOfItems = collectionView.numberOfItems(inSection: 0)
        let bounds = collectionView.bounds
        let safeAreaInsets = collectionView.safeAreaInsets

        guard numberOfItems > 0 else {
            contentSize = bounds.size
            return
        }

        let showStripe = !isStripeHidden && numberOfItems > 1
        var stripeSize = stripeItemMinSize
        let stripeOriginX = safeAreaInsets.left

        if showStripe {
            let stripeItemsCount = numberOfItems - 1
            let availableWidth = bounds.width - safeAreaInsets.left - safeAreaInsets.right
            let requiredWidth = CGFloat(stripeItemsCount) * (stripeSize.width + spacing) - spacing

            if requiredWidth > availableWidth {
                // Not all cells fit on the screen at their preferred size
                let peekWidth: CGFloat = 16
                let fullyFittingCells = Int(((availableWidth + spacing) / (stripeSize.width + spacing)).rounded(.down))
                let cutCellVisibleWidth = availableWidth - CGFloat(fullyFittingCells) * (stripeSize.width + spacing)

                // When the cell at the screen edge is cut in a clearly visible way, the user can already
                // see that the stripe is scrollable and the cells keep their preferred size. Otherwise
                // make the cells a bit narrower, so a few pixels of the next cell are visible
                // (or all cells fit on the screen, when only a few pixels were missing)
                if cutCellVisibleWidth < peekWidth || cutCellVisibleWidth > stripeSize.width - peekWidth {
                    let cellsToFit = max(Int(((availableWidth - peekWidth) / (stripeSize.width + spacing)).rounded(.up)), 1)

                    if cellsToFit >= stripeItemsCount {
                        // All cells fit on the screen when making them a bit narrower
                        stripeSize.width = ((availableWidth - CGFloat(stripeItemsCount - 1) * spacing) / CGFloat(stripeItemsCount)).rounded(.down)
                    } else {
                        stripeSize.width = ((availableWidth - peekWidth) / CGFloat(cellsToFit) - spacing).rounded(.down)
                    }
                }
            }
        }

        var speakerHeight = bounds.height - safeAreaInsets.bottom
        if showStripe {
            speakerHeight -= stripeSize.height + spacing
        }

        // The promoted participant is pinned to the current horizontal content offset,
        // so it stays in place while the stripe below it is scrolled
        let speakerAttributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
        speakerAttributes.frame = CGRect(x: bounds.origin.x, y: 0, width: bounds.width, height: speakerHeight)
        speakerAttributes.zIndex = 1
        itemAttributes.append(speakerAttributes)

        // When the stripe is hidden, its items are placed below the visible area, so their cells are not created
        let stripeOriginY = showStripe ? bounds.height - safeAreaInsets.bottom - stripeSize.height : bounds.height + spacing

        for item in 1..<numberOfItems {
            let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: item, section: 0))
            let originX = stripeOriginX + CGFloat(item - 1) * (stripeSize.width + spacing)
            attributes.frame = CGRect(x: originX, y: stripeOriginY, width: stripeSize.width, height: stripeSize.height)
            itemAttributes.append(attributes)
        }

        var stripeContentWidth: CGFloat = 0
        if showStripe {
            stripeContentWidth = stripeOriginX + CGFloat(numberOfItems - 1) * (stripeSize.width + spacing) - spacing + safeAreaInsets.right
        }

        contentSize = CGSize(width: max(bounds.width, stripeContentWidth), height: bounds.height)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        return itemAttributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.item < itemAttributes.count else { return nil }

        return itemAttributes[indexPath.item]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        // The promoted participant needs to be repositioned on every scroll of the stripe
        return true
    }

    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
        // The content is never scrollable vertically, make sure we don't keep
        // a vertical offset when switching from the grid layout
        return CGPoint(x: proposedContentOffset.x, y: 0)
    }
}
