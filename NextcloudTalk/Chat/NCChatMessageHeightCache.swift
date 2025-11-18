//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

public class NCChatMessageHeightCache {

    private let internalCache = NSCache<NSString, NSNumber>()

    private var cachedWidth: CGFloat = 0

    public func getHeight(forMessage message: NCChatMessage, forWidth width: CGFloat) -> CGFloat? {
        guard self.cachedWidth == width else { return nil }

        return self.internalCache.object(forKey: String(message.messageId) as NSString) as? CGFloat
    }

    public func setHeight(forMessage message: NCChatMessage, forWidth width: CGFloat, withHeight height: CGFloat) {
        if self.cachedWidth != width {
            self.internalCache.removeAllObjects()
            self.cachedWidth = width
        }

        self.internalCache.setObject(height as NSNumber, forKey: String(message.messageId) as NSString)
    }

    public func removeHeight(forMessage message: NCChatMessage) {
        self.internalCache.removeObject(forKey: String(message.messageId) as NSString)
    }

}
