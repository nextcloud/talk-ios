//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@objc protocol EmojiAvatarPickerViewControllerDelegate {
    func didSelectEmoji(emoji: NSString, color: NSString, image: UIImage)
}

@objcMembers class EmojiAvatarPickerViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet weak var emojiTextField: EmojiTextField!
    @IBOutlet weak var emojiContainerView: UIView!

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

        NCAppBranding.styleViewController(self)

        self.emojiTextField.delegate = self
        self.emojiTextField.text = self.defaultEmoji
        self.selectedEmoji = self.defaultEmoji

        self.emojiContainerView.layer.cornerRadius = self.emojiContainerView.frame.height / 2
        self.emojiContainerView.clipsToBounds = true
        self.emojiContainerView.backgroundColor = NCAppBranding.avatarPlaceholderColor()

        self.removeColorButton.layer.cornerRadius = self.removeColorButton.frame.height / 2
        self.removeColorButton.backgroundColor = NCAppBranding.avatarPlaceholderColor()

        self.colorWell.addTarget(self, action: #selector(self.colorWellChanged), for: .valueChanged)
        self.colorWell.supportsAlpha = false

        self.generateColorButtons()

        self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(self.cancelButtonPressed))
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.doneButtonPressed))

        if #unavailable(iOS 26.0) {
            self.navigationItem.leftBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
            self.navigationItem.rightBarButtonItem?.tintColor = NCAppBranding.themeTextColor()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        self.emojiTextField.becomeFirstResponder()
    }

    func cancelButtonPressed() {
        self.dismiss(animated: true, completion: nil)
    }

    func doneButtonPressed() {
        self.delegate?.didSelectEmoji(emoji: selectedEmoji as NSString, color: selectedColor as NSString, image: emojiContainerView.asImage())
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
        self.selectedColor = NCUtils.hexString(fromColor: color)
        self.emojiContainerView.backgroundColor = color
    }

    @IBAction func removeColorButtonPressed(_ sender: Any) {
        self.selectedColor = ""
        self.emojiContainerView.backgroundColor = NCAppBranding.avatarPlaceholderColor()

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
