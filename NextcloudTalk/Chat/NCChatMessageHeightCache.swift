//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

public class NCChatMessageHeightCache {

    private let internalCache = NSCache<NSString, NSNumber>()

    private var cachedWidth: CGFloat = 0

    private func getCacheKey(forMessage message: NCChatMessage) -> NSString {
        let key = "\(String(message.messageId))-\(message.isGroupMessage)"

        return key as NSString
    }

    public func getHeight(forMessage message: NCChatMessage, forWidth width: CGFloat) -> CGFloat? {
        guard self.cachedWidth == width, message.messageId > 0, !message.isSystemMessage else { return nil }

        return self.internalCache.object(forKey: getCacheKey(forMessage: message)) as? CGFloat
    }

    public func setHeight(forMessage message: NCChatMessage, forWidth width: CGFloat, withHeight height: CGFloat) {
        if self.cachedWidth != width {
            self.internalCache.removeAllObjects()
            self.cachedWidth = width
        }

        self.internalCache.setObject(height as NSNumber, forKey: getCacheKey(forMessage: message))
    }

    public func removeHeight(forMessage message: NCChatMessage) {
        self.internalCache.removeObject(forKey: getCacheKey(forMessage: message))
    }

}
