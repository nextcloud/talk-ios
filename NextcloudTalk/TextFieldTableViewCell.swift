//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

class TextFieldTableViewCell: UITableViewCell {

    static let identifier = "textFieldCellIdentifier"

    let textField: UITextField = {
        let textField = UITextField()

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.adjustsFontForContentSizeCategory = true

        textField.font = UIFont.preferredFont(forTextStyle: .body)

        textField.clearButtonMode = .whileEditing
        textField.returnKeyType = .done
        textField.keyboardType = .default
        textField.autocorrectionType = .default
        textField.autocapitalizationType = .sentences

        return textField
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none

        contentView.addSubview(textField)

        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            textField.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            textField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        selectionStyle = .none

        textField.text = ""
        textField.placeholder = nil

        textField.clearButtonMode = .whileEditing
        textField.returnKeyType = .done
        textField.keyboardType = .default
        textField.autocorrectionType = .default
        textField.autocapitalizationType = .sentences
    }
}
