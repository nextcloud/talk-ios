//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

let kShareConfirmationCellIdentifier = "ShareConfirmationCellIdentifier"
let kShareConfirmationTableCellNibName = "ShareConfirmationCollectionViewCell"

class ShareConfirmationCollectionViewCell: UICollectionViewCell {

    @IBOutlet var previewView: UIImageView!
    @IBOutlet var placeholderImageView: UIImageView!
    @IBOutlet var placeholderTextView: UITextView!

    override func prepareForReuse() {
        super.prepareForReuse()

        self.previewView.image = nil
        self.placeholderImageView.image = nil
        self.placeholderTextView.text = ""

        self.placeholderImageView.isHidden = false
        self.placeholderTextView.isHidden = false
    }

    func setPreviewImage(_ image: UIImage) {
        self.previewView.image = image

        self.placeholderImageView.isHidden = true
        self.placeholderTextView.isHidden = true
    }

    func setPlaceHolderImage(_ image: UIImage) {
        self.placeholderImageView.image = image
    }

    func setPlaceHolderText(_ text: String) {
        self.placeholderTextView.text = text
    }
}
