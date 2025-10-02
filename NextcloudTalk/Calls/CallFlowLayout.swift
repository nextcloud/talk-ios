//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Based on https://stackoverflow.com/a/41409642

import UIKit

@objcMembers
class CallFlowLayout: UICollectionViewFlowLayout {

    private let targetAspectRatioPortrait = 1.0
    private let targetAspectRatioLandscape = 1.5

    private var numberOfColumns = 1
    private var numberOfRows = 1
    private var targetAspectRatio: Double

    override init() {
        self.targetAspectRatio = self.targetAspectRatioLandscape

        super.init()

        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        self.targetAspectRatio = self.targetAspectRatioLandscape

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

    func columnsMax() -> Int {
        guard let collectionView = collectionView else { return 1 }

        let contentSize = collectionView.bounds.size
        let cellMinWidth = kCallParticipantCellMinHeight * targetAspectRatio + minimumInteritemSpacing

        if (contentSize.width / cellMinWidth).rounded(.down) < 1 {
            return 1
        }

        return Int((contentSize.width / cellMinWidth).rounded(.down))
    }

    func rowsMax() -> Int {
        guard let collectionView = collectionView else { return 1 }

        let contentSize = collectionView.bounds.size
        let cellMinHeight = kCallParticipantCellMinHeight + minimumLineSpacing

        if (contentSize.height / cellMinHeight).rounded(.down) < 1 {
            return 1
        }

        return Int((contentSize.height / cellMinHeight).rounded(.down))
    }

    // Based on the makeGrid method of web:
    // https://github.com/nextcloud/spreed/blob/5ba554c3f751ba8b8035c7fc8404ca6194d3c16a/src/components/CallView/Grid/Grid.vue#L664
    func makeGrid() {
        guard let collectionView = collectionView else { return }

        let numberOfCells = collectionView.numberOfItems(inSection: 0)

        if numberOfCells == 0 {
            self.numberOfColumns = 0
            self.numberOfRows = 0

            return
        }

        if self.isPortrait() {
            self.targetAspectRatio = self.targetAspectRatioPortrait
        } else {
            self.targetAspectRatio = self.targetAspectRatioLandscape
        }

        // Start with the maximum number of allowed columns/rows
        self.numberOfColumns = self.columnsMax()
        self.numberOfRows = self.rowsMax()

        // Try to adjust the number of columns/rows based on the number of cells
        self.shrinkGrid()
    }

    func shrinkGrid() {
        if self.numberOfRows == 1, self.numberOfColumns == 1 {
            return
        }

        guard let collectionView = collectionView else { return }
        let contentSize = collectionView.bounds.size

        var currentColumns = self.numberOfColumns
        var currentRows = self.numberOfRows
        var currentSlots = currentColumns * currentRows
        let numberOfCells = collectionView.numberOfItems(inSection: 0)

        while numberOfCells < currentSlots {
            let previousColumns = currentColumns
            let previousRows = currentRows

            let videoWidth = contentSize.width / CGFloat(currentColumns)
            let videoHeight = contentSize.height / CGFloat(currentRows)

            let videoWidthWithOneColumnLess = contentSize.width / CGFloat(currentColumns - 1)
            let videoHeightWithOneRowLess = contentSize.height / CGFloat(currentRows - 1)

            let aspectRatioWithOneColumnLess = videoWidthWithOneColumnLess / videoHeight
            let aspectRatioWithOneRowLess = videoWidth / videoHeightWithOneRowLess

            let deltaAspectRatioWithOneColumnLess = abs(aspectRatioWithOneColumnLess - targetAspectRatio)
            let deltaAspectRatioWithOneRowLess = abs(aspectRatioWithOneRowLess - targetAspectRatio)

            // Based on the aspect ratio we want to achieve, try to either reduce the number of columns or rows
            if deltaAspectRatioWithOneColumnLess <= deltaAspectRatioWithOneRowLess {
                if currentColumns >= 2 {
                    currentColumns -= 1
                }

                currentSlots = currentColumns * currentRows

                if numberOfCells > currentSlots {
                    currentColumns += 1

                    break
                }
            } else {
                if currentRows >= 2 {
                    currentRows -= 1
                }

                currentSlots = currentColumns * currentRows

                if numberOfCells > currentSlots {
                    currentRows += 1

                    break
                }
            }

            if previousColumns == currentColumns, previousRows == currentRows {
                break
            }
        }

        self.numberOfColumns = currentColumns
        self.numberOfRows = currentRows
    }

    override func prepare() {
        super.prepare()

        guard let collectionView = collectionView else { return }

        let contentSize = collectionView.bounds.size

        self.makeGrid()

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
