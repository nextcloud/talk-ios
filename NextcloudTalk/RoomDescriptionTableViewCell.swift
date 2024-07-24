//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objc public protocol RoomDescriptionTableViewCellDelegate: AnyObject {
    @objc optional func roomDescriptionCellTextViewDidChange(_ cell: RoomDescriptionTableViewCell)
    @objc optional func roomDescriptionCellDidExceedLimit(_ cell: RoomDescriptionTableViewCell)
    @objc optional func roomDescriptionCellDidEndEditing(_ cell: RoomDescriptionTableViewCell)
}

@objcMembers public class RoomDescriptionTableViewCell: UITableViewCell, UITextViewDelegate {

    public weak var delegate: RoomDescriptionTableViewCellDelegate?

    @IBOutlet weak var textView: UITextView!

    public static var identifier = "RoomDescriptionCellIdentifier"
    public static var nibName = "RoomDescriptionTableViewCell"

    public var characterLimit: Int = -1

    public override func awakeFromNib() {
        super.awakeFromNib()

        self.textView.dataDetectorTypes = .all
        self.textView.textContainer.lineFragmentPadding = 0
        self.textView.textContainerInset = .zero
        self.textView.isScrollEnabled = false
        self.textView.isEditable = false
        self.textView.delegate = self
    }

    // MARK: - UITextView delegate

    public func textViewDidChange(_ textView: UITextView) {
        self.delegate?.roomDescriptionCellTextViewDidChange?(self)
    }

    public func textViewDidEndEditing(_ textView: UITextView) {
        self.delegate?.roomDescriptionCellDidEndEditing?(self)
    }

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
            self.delegate?.roomDescriptionCellDidExceedLimit?(self)
        }

        return !limitExceeded
    }
}
