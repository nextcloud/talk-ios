//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

class NCMessageTextView: SLKTextView {

    override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)

        self.keyboardType = .default

        self.backgroundColor = NCAppBranding.backgroundColor()

        self.placeholder = NSLocalizedString("Write message, @ to mention someone …", comment: "")
        self.placeholderColor = NCAppBranding.placeholderColor()
    }

    @available(iOS 18.0, *)
    override func insert(_ adaptiveImageGlyph: NSAdaptiveImageGlyph, replacementRange: UITextRange) {
        let userInfo: [String: Any] = [
            SLKTextViewPastedItemMediaType: SLKPastableMediaType.PNG.rawValue,
            SLKTextViewPastedItemData: adaptiveImageGlyph.imageContent
        ]

        NotificationCenter.default.post(name: .SLKTextViewDidPasteItem, object: nil, userInfo: userInfo)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // Hide iOS-native "Format" option, which is shown, because we enabled allowsEditingTextAttributes for Memoji/Genmoji support
        if action == NSSelectorFromString("_showTextFormattingOptions:") ||
            action == NSSelectorFromString("toggleBoldface:") ||
            action == NSSelectorFromString("toggleItalics:") ||
            action == NSSelectorFromString("toggleUnderline:") {

            return false
        }

        return super.canPerformAction(action, withSender: sender)
    }
}
