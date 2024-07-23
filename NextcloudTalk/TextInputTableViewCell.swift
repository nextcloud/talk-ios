//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

let kTextInputCellIdentifier = "TextInputCellIdentifier"
let kTextInputTableViewCellNibName = "TextInputTableViewCell"

class TextInputTableViewCell: UITableViewCell {

    @IBOutlet weak var textField: UITextField!

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        self.textField.clearButtonMode = .whileEditing
        self.textField.returnKeyType = .done
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        self.textField.text = ""
        self.textField.placeholder = nil
        self.textField.keyboardType = .default
        self.textField.autocorrectionType = .no
        self.textField.autocapitalizationType = .none
    }
}
