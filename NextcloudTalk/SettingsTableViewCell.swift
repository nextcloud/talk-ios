//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

class SettingsTableViewCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        textLabel?.numberOfLines = 0
        detailTextLabel?.numberOfLines = 0
        detailTextLabel?.textColor = .secondaryLabel
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        textLabel?.text = nil
        detailTextLabel?.text = nil
        imageView?.image = nil
        accessoryView = nil
        accessoryType = .none
        selectionStyle = .default
    }

    func setSettingsImage(image: UIImage?, renderingMode: UIImage.RenderingMode = .alwaysTemplate) {
        // Render all images to a size of 20x20 so all cells have the same width for the imageView
        self.imageView?.image = NCUtils.renderAspectImage(image: image, ofSize: .init(width: 20, height: 20), centerImage: true)?.withRenderingMode(renderingMode)
        self.imageView?.tintColor = .secondaryLabel
        self.imageView?.contentMode = .scaleAspectFit
    }
}
