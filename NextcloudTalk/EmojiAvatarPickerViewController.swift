//
// Copyright (c) 2023 Ivan Sein <ivan@nextcloud.com>
//
// Author Ivan Sein <ivan@nextcloud.com>
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

import UIKit

@objc protocol EmojiAvatarPickerViewControllerDelegate {
    func didSelectEmoji(emoji: NSString, color: NSString)
}

@objcMembers class EmojiAvatarPickerViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet weak var emojiTextField: EmojiTextField!
    @IBOutlet weak var emojiBackgroundView: UIView!

    @IBOutlet weak var colorsStackView: UIStackView!
    @IBOutlet weak var removeColorButton: UIButton!
    @IBOutlet weak var colorWell: UIColorWell!

    public weak var delegate: EmojiAvatarPickerViewControllerDelegate?

    let defaultEmoji: String = "🙂"
    var defaultColors: [UIColor] = []
    var selectedEmoji: String = ""
    var selectedColor: String = ""

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: NCAppBranding.themeTextColor()]
        self.navigationController?.navigationBar.tintColor = NCAppBranding.themeTextColor()
        self.navigationController?.navigationBar.barTintColor = NCAppBranding.themeColor()
        self.navigationController?.navigationBar.isTranslucent = false

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.titleTextAttributes = [.foregroundColor: NCAppBranding.themeTextColor()]
        appearance.backgroundColor = NCAppBranding.themeColor()
        self.navigationItem.standardAppearance = appearance
        self.navigationItem.compactAppearance = appearance
        self.navigationItem.scrollEdgeAppearance = appearance

        self.emojiTextField.delegate = self
        self.emojiTextField.text = self.defaultEmoji
        self.selectedEmoji = self.defaultEmoji

        self.emojiBackgroundView.layer.cornerRadius = self.emojiBackgroundView.frame.height / 2
        self.emojiBackgroundView.clipsToBounds = true
        self.emojiBackgroundView.backgroundColor = NCAppBranding.avatarPlaceholderColor()

        self.removeColorButton.layer.cornerRadius = self.removeColorButton.frame.height / 2
        self.removeColorButton.backgroundColor = NCAppBranding.avatarPlaceholderColor()

        self.colorWell.addTarget(self, action: #selector(self.colorWellChanged), for: .valueChanged)
        self.colorWell.supportsAlpha = false

        self.generateColorButtons()

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancelButtonPressed))
        self.navigationItem.leftBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.doneButtonPressed))
        self.navigationItem.rightBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
    }

    override func viewDidAppear(_ animated: Bool) {
        self.emojiTextField.becomeFirstResponder()
    }

    func cancelButtonPressed() {
        self.dismiss(animated: true, completion: nil)
    }

    func doneButtonPressed() {
        self.delegate?.didSelectEmoji(emoji: selectedEmoji as NSString, color: selectedColor as NSString)
        self.dismiss(animated: true, completion: nil)
    }

    func colorWellChanged() {
        self.setSelectedColor(color: self.colorWell.selectedColor ?? .black)
    }

    // MARK: - Color buttons

    func generateColorButtons() {
        self.defaultColors = ColorGenerator.genColors(2)
        for (index, color) in self.defaultColors.enumerated() {
            let colorButton = UIButton(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
            colorButton.layer.cornerRadius = colorButton.frame.height / 2
            colorButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
            colorButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
            colorButton.backgroundColor = color
            colorButton.tag = index
            colorButton.addTarget(self, action: #selector(colorButtonPressed(_ :)), for: .touchUpInside)
            self.colorsStackView.addArrangedSubview(colorButton)
        }
    }

    func colorButtonPressed(_ sender: UIButton) {
        let color = self.defaultColors[sender.tag]
        self.setSelectedColor(color: color)

        self.colorWell.selectedColor = nil
    }

    func setSelectedColor(color: UIColor) {
        self.selectedColor = NCUtils.hexString(from: color)
        self.emojiBackgroundView.backgroundColor = color
    }

    @IBAction func removeColorButtonPressed(_ sender: Any) {
        self.selectedColor = ""
        self.emojiBackgroundView.backgroundColor = NCAppBranding.avatarPlaceholderColor()

        self.colorWell.selectedColor = nil
    }

    // MARK: - UITextField delegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.emojiTextField.resignFirstResponder()
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        self.navigationItem.rightBarButtonItem?.isEnabled = !self.selectedEmoji.isEmpty
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if textField is EmojiTextField {
            if string.isSingleEmoji == false {
                self.selectedEmoji = ""
                self.emojiTextField.text = ""
            } else {
                self.selectedEmoji = string
                self.emojiTextField.text = string
            }

            self.navigationItem.rightBarButtonItem?.isEnabled = !self.selectedEmoji.isEmpty

            return false
        }

        return true
    }
}
