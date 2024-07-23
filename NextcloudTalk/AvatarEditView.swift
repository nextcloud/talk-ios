//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objc protocol AvatarEditViewDelegate {
    @objc func avatarEditViewPresentCamera(_ controller: AvatarEditView?)
    @objc func avatarEditViewPresentPhotoLibrary(_ controller: AvatarEditView?)
    @objc optional func avatarEditViewPresentEmojiAvatarPicker(_ controller: AvatarEditView?)
    @objc func avatarEditViewRemoveAvatar(_ controller: AvatarEditView?)
}

@objcMembers class AvatarEditView: UIView, UIImagePickerControllerDelegate, UINavigationControllerDelegate, TOCropViewControllerDelegate {

    public weak var delegate: AvatarEditViewDelegate?

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var avatarImageView: AvatarImageView!
    @IBOutlet weak var nameLabel: UILabel!
    @IBOutlet weak var editView: UIView!
    @IBOutlet weak var scopeButton: UIButton!
    @IBOutlet weak var cameraButton: UIButton!
    @IBOutlet weak var photoLibraryButton: UIButton!
    @IBOutlet weak var emojiButton: UIButton!
    @IBOutlet weak var trashButton: UIButton!

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    func commonInit() {
        Bundle.main.loadNibNamed("AvatarEditView", owner: self, options: nil)

        contentView.frame = self.bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        self.avatarImageView.layer.masksToBounds = true

        self.addSubview(contentView)
    }

    override func layoutSubviews() {
        self.avatarImageView.layer.cornerRadius = self.avatarImageView.frame.size.height / 2
    }

    func changeButtonState(to state: Bool) {
        self.scopeButton.isEnabled = state
        self.cameraButton.isEnabled = state
        self.photoLibraryButton.isEnabled = state
        self.emojiButton.isEnabled = state
        self.trashButton.isEnabled = state
    }

    @IBAction func cameraButtonTouchUpInside(_ sender: Any) {
        self.delegate?.avatarEditViewPresentCamera(self)
    }

    @IBAction func photoLibraryTouchUpInside(_ sender: Any) {
        self.delegate?.avatarEditViewPresentPhotoLibrary(self)
    }

    @IBAction func trashTouchUpInside(_ sender: Any) {
        self.delegate?.avatarEditViewRemoveAvatar(self)
    }

    @IBAction func emojiTouchUpInside(_ sender: Any) {
        self.delegate?.avatarEditViewPresentEmojiAvatarPicker?(self)
    }
}
