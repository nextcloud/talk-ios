//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

extension BaseChatTableViewCell {

    private static let selectionIndicatorSize = 24.0
    private static let selectionIndicatorMargin = 8.0

    /// The frames, in the coordinate space of the cell, that handle touches themselves: the bubble and the avatar.
    /// A touch anywhere else in the row is outside of the message.
    func interactiveFrames() -> [CGRect] {
        var frames = [self.convert(self.bubbleStackView.bounds, from: self.bubbleStackView)]

        if !self.avatarButton.isHidden {
            frames.append(self.convert(self.avatarButton.bounds, from: self.avatarButton))
        }

        return frames
    }

    /// While the mode is active a transparent view covers the row, so a touch on the bubble does not reach
    /// its content (file, link, voice message) but is a touch on the row.
    func setSelectionMode(_ active: Bool, selected: Bool) {
        self.isSelectionModeActive = active
        self.replyGestureRecognizer?.isEnabled = !active

        guard active else {
            self.selectionOverlay?.removeFromSuperview()
            self.selectionOverlay = nil
            self.selectionIndicator = nil
            return
        }

        let overlay: UIView
        let indicator: UIImageView

        if let existingOverlay = self.selectionOverlay, let existingIndicator = self.selectionIndicator {
            overlay = existingOverlay
            indicator = existingIndicator
        } else {
            overlay = UIView(frame: self.contentView.bounds)
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.isAccessibilityElement = true

            indicator = UIImageView()
            indicator.contentMode = .scaleAspectFit
            overlay.addSubview(indicator)

            self.contentView.addSubview(overlay)
            self.selectionOverlay = overlay
            self.selectionIndicator = indicator
        }

        overlay.backgroundColor = selected ? NCAppBranding.elementColor().withAlphaComponent(0.15) : .clear
        overlay.accessibilityLabel = self.message?.parsedMessage().string
        overlay.accessibilityTraits = selected ? [.button, .selected] : [.button]

        indicator.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle")
        indicator.tintColor = selected ? NCAppBranding.elementColor() : .secondaryLabel

        self.setNeedsLayout()
    }

    /// The indicator sits in the free space next to the bubble: left for own messages, right for the others,
    /// where the avatar is on the left.
    func layoutSelectionIndicator() {
        guard let indicator = self.selectionIndicator else { return }

        let size = Self.selectionIndicatorSize
        var isOwnMessage = false

        if let message = self.message, let account = self.account {
            isOwnMessage = message.isMessage(from: account.userId)
        }

        let x = isOwnMessage ? self.safeAreaInsets.left + Self.selectionIndicatorMargin
                             : self.contentView.bounds.width - self.safeAreaInsets.right - Self.selectionIndicatorMargin - size

        indicator.frame = CGRect(x: x, y: (self.contentView.bounds.height - size) / 2, width: size, height: size)
    }
}
