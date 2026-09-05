//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

/// The cell has to come from a nib, not from the reuse pool: a cell which was displayed only renders the
/// part which was on screen, and handing over the live cell of a row means UIKit reparents it
class ContextMenuPreviewController: UIViewController {

    // Keeps the cell out of the corners of the preview, which UIKit rounds stronger than our cells
    private static let padding = 12.0

    init(for cellView: UIView, maxHeight: CGFloat = .greatestFiniteMagnitude) {
        super.init(nibName: nil, bundle: nil)

        let padding = ContextMenuPreviewController.padding
        let cellWidth = cellView.frame.width

        // A preview wider than the cell is cut off instead of scaled, so the cell makes room for the padding
        let scale = (cellWidth - padding * 2) / cellWidth

        cellView.transform = .init(scaleX: scale, y: scale)
        cellView.frame.origin = .init(x: padding, y: padding)

        let previewSize = CGSize(width: cellWidth, height: min(cellView.frame.height + padding * 2, maxHeight))
        let previewView = UIView(frame: .init(origin: .zero, size: previewSize))
        previewView.clipsToBounds = true

        // Our cells can be translucent, the menu background behind them would shine through
        previewView.backgroundColor = .systemBackground
        previewView.addSubview(cellView)

        self.view = previewView
        self.preferredContentSize = previewSize
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
