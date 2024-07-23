//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

class BoundsChangedFlowLayout: UICollectionViewFlowLayout {

    override func invalidationContext(forBoundsChange newBounds: CGRect) -> UICollectionViewLayoutInvalidationContext {
        if let context = super.invalidationContext(forBoundsChange: newBounds) as? UICollectionViewFlowLayoutInvalidationContext {
            if let collectionView = collectionView {
                context.invalidateFlowLayoutDelegateMetrics = collectionView.bounds.size != newBounds.size
            }

            return context
        }

        return  UICollectionViewLayoutInvalidationContext()
    }
}
