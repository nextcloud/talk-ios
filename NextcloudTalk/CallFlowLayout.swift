//
// Copyright (c) 2022 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Marcel Müller <marcel-mueller@gmx.de>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

// Based on https://stackoverflow.com/a/41409642

import UIKit

@objcMembers
class CallFlowLayout: UICollectionViewFlowLayout {

    override init() {
        super.init()

        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        commonInit()
    }

    func commonInit() {
        self.minimumInteritemSpacing = 8
        self.minimumLineSpacing = 8
        self.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    func isPortrait() -> Bool {
        guard let collectionView = collectionView else { return false }

        return collectionView.bounds.size.width < collectionView.bounds.size.height
    }

    func numberOfColumns(for numberOfCells: Int) -> Int {
        if isPortrait() {
            if numberOfCells <= 2 {
                return 1
            } else if numberOfCells <= 6 {
                return 2
            }

            return 3
        }

        if numberOfCells == 1 {
            return 1
        } else if numberOfCells <= 2 || numberOfCells == 4 {
            return 2
        } else if numberOfCells == 3 || numberOfCells == 5 {
            return 3
        }

        return 4
    }

    override func prepare() {
        super.prepare()

        guard let collectionView = collectionView else { return }

        let contentSize = collectionView.bounds.size
        let numberOfCells = collectionView.numberOfItems(inSection: 0)
        let numberOfColumns = numberOfColumns(for: numberOfCells)
        let numberOfRows = (CGFloat(numberOfCells) / CGFloat(numberOfColumns)).rounded(.up)

        // Calculate cell width
        let sectionInsetWidth = sectionInset.left + sectionInset.right
        let safeAreaInsetWidth = collectionView.safeAreaInsets.left + collectionView.safeAreaInsets.right
        let marginsAndInsetsWidth = sectionInsetWidth + safeAreaInsetWidth + minimumInteritemSpacing * CGFloat(numberOfColumns - 1)
        let itemWidth = ((contentSize.width - marginsAndInsetsWidth) / CGFloat(numberOfColumns)).rounded(.down)

        // Calculate cell height
        let sectionInsetHeight = sectionInset.top + sectionInset.bottom
        let safeAreaInsetHeight = collectionView.safeAreaInsets.top + collectionView.safeAreaInsets.bottom
        let marginsAndInsetsHeight = sectionInsetHeight + safeAreaInsetHeight + minimumLineSpacing * CGFloat(numberOfRows - 1)
        var itemHeight = ((contentSize.height - marginsAndInsetsHeight) / CGFloat(numberOfRows)).rounded(.down)

        // Enfore minimum cell height
        if itemHeight < kCallParticipantCellMinHeight {
            itemHeight = kCallParticipantCellMinHeight
        }

        itemSize = CGSize(width: itemWidth, height: itemHeight)
    }

    override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
        let context = super.invalidationContext(forBoundsChange: newBounds)

        if let context = context as? UICollectionViewFlowLayoutInvalidationContext {
            context.invalidateFlowLayoutDelegateMetrics = newBounds.size != collectionView?.bounds.size
        }

        return context
    }

}
