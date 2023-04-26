//
// Copyright (c) 2023 Marcel Müller <marcel.mueller@nextcloud.com>
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

@objc protocol AvatarEditViewDelegate {
    @objc func avatarEditViewPresentCamera(_ controller: AvatarEditView?)
    @objc func avatarEditViewPresentPhotoLibrary(_ controller: AvatarEditView?)
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

    @IBAction func cameraButtonTouchUpInside(_ sender: Any) {
        self.delegate?.avatarEditViewPresentCamera(self)
    }

    @IBAction func photoLibraryTouchUpInside(_ sender: Any) {
        self.delegate?.avatarEditViewPresentPhotoLibrary(self)
    }

    @IBAction func trashTouchUpInside(_ sender: Any) {
        self.delegate?.avatarEditViewRemoveAvatar(self)
    }
}
