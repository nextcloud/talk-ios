//
// Copyright (c) 2024 Marcel Müller <marcel.mueller@nextcloud.com>
//
// Author Ivan Sein <ivan@nextcloud.com>
// Author Marcel Müller <marcel.mueller@nextcloud.com>
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
