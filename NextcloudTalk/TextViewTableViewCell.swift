//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@objc protocol TextViewTableViewCellDelegate: AnyObject {
    @objc optional func textViewCellDidExceedCharacterLimit(_ cell: TextViewTableViewCell)
    @objc optional func textViewCellTextViewDidChange(_ cell: TextViewTableViewCell)
    @objc optional func textViewCellDidEndEditing(_ cell: TextViewTableViewCell)
}

@objcMembers class TextViewTableViewCell: UITableViewCell, UITextViewDelegate {

    var characterLimit: Int = -1
    weak var delegate: TextViewTableViewCellDelegate?

    public static var identifier = "textViewCellIdentifier"

    let textView: UITextView = {
        let textView = UITextView()

        textView.translatesAutoresizingMaskIntoConstraints = false

        textView.font = UIFont.preferredFont(forTextStyle: .body)

        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.dataDetectorTypes = .all

        return textView
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        contentView.addSubview(textView)

        textView.delegate = self

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            textView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        characterLimit = -1

        textView.text = ""
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.isScrollEnabled = false
        textView.isEditable = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.dataDetectorTypes = .all

        selectionStyle = .default
    }

    // MARK: - UITextView delegate

    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Prevent crashing undo bug
        // https://stackoverflow.com/questions/433337/set-the-maximum-character-length-of-a-uitextfield
        let currentCharacterCount = textView.text?.count ?? 0
        if range.length + range.location > currentCharacterCount {
            return false
        }

        // Check character limit
        let newLength = currentCharacterCount + text.count - range.length
        let limitExceeded = self.characterLimit > 0 && newLength > self.characterLimit

        if limitExceeded {
            delegate?.textViewCellDidExceedCharacterLimit?(self)
            return false
        }

        return true
    }

    public func textViewDidChange(_ textView: UITextView) {
        delegate?.textViewCellTextViewDidChange?(self)
    }

    public func textViewDidEndEditing(_ textView: UITextView) {
        delegate?.textViewCellDidEndEditing?(self)
    }
}
