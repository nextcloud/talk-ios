//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

extension UIFont {

    static func monospacedPreferredFont(forTextStyle style: TextStyle) -> UIFont {
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style)
        let font = UIFont.monospacedSystemFont(ofSize: fontDescriptor.pointSize, weight: .regular)

        return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }

    // See: https://stackoverflow.com/a/62687023
    static func preferredFont(for style: TextStyle, weight: Weight, italic: Bool) -> UIFont {
        // Get the style's default pointSize
        let traits = UITraitCollection(preferredContentSizeCategory: .large)
        let desc = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style, compatibleWith: traits)

        // Get the font at the default size and preferred weight
        var font = UIFont.systemFont(ofSize: desc.pointSize, weight: weight)
        if italic == true {
            font = font.with([.traitItalic])
        }

        // Setup the font to be auto-scalable
        let metrics = UIFontMetrics(forTextStyle: style)
        return metrics.scaledFont(for: font)
    }

    @objc
    static func preferredFont(for style: TextStyle, weight: Weight) -> UIFont {
        return preferredFont(for: style, weight: weight, italic: false)
    }

    private func with(_ traits: UIFontDescriptor.SymbolicTraits...) -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(UIFontDescriptor.SymbolicTraits(traits).union(fontDescriptor.symbolicTraits)) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
