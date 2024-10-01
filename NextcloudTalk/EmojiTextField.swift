//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import SwiftUI
import Dynamic

struct SingleEmojiTextFieldWrapper: UIViewRepresentable {
    @State var placeholder: String
    @Binding var text: String

    func makeUIView(context: Context) -> EmojiTextField {
        let emojiTextField = EmojiTextField()
        emojiTextField.delegate = context.coordinator
        return emojiTextField
    }

    func updateUIView(_ uiView: EmojiTextField, context: Context) {
        uiView.text = text
        uiView.placeholder = placeholder
    }

    func makeCoordinator() -> SingleEmojiTextFieldWrapper.Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SingleEmojiTextFieldWrapper

        init(parent: SingleEmojiTextFieldWrapper) {
            self.parent = parent
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if textField is EmojiTextField {
                if string.isSingleEmoji == false {
                    self.parent.text = ""
                } else {
                    self.parent.text = string
                }

                textField.endEditing(true)

                return false
            }

            return true
        }
    }
}

@objc class EmojiTextField: UITextField {

    override init(frame: CGRect) {
        super.init(frame: frame)

        tintColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        tintColor = .clear
    }

    // required for iOS 13
    override var textInputContextIdentifier: String? { "" } // return non-nil to show the Emoji keyboard ¯\_(ツ)_/¯

    override var textInputMode: UITextInputMode? {
        for mode in UITextInputMode.activeInputModes where mode.primaryLanguage == "emoji" {
            return mode
        }
        return nil
    }

    @discardableResult override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()

        if result && NCUtils.isiOSAppOnMac() {
            // Open the emoji picker when running on Mac OS

            let app = Dynamic.NSApplication.sharedApplication()
            app.orderFrontCharacterPalette(nil)
        }

        return result
    }
}
