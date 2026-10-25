//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

// Handoff: a conversation open on one device can be continued on another device of the same Apple Account,
// in the app or, where the app isn't installed (e.g. a Mac), in the browser.
enum ConversationHandoff {

    // Needs to be listed in NSUserActivityTypes of the Info.plist
    static var activityType: String {
        return "\(Bundle.main.bundleIdentifier ?? "com.nextcloud.Talk").conversation"
    }

    private static let serverKey = "server"
    private static let userKey = "user"
    private static let tokenKey = "token"

    static func userActivity(for room: NCRoom, account: TalkAccount) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activityType)

        // The title can be shown on the other device, so don't show the name of a sensitive conversation there
        activity.title = room.isSensitive ? NSLocalizedString("Conversation", comment: "") : room.displayName
        activity.userInfo = [serverKey: account.server, userKey: account.userId, tokenKey: room.token ?? ""]
        activity.requiredUserInfoKeys = [serverKey, userKey, tokenKey]
        activity.webpageURL = self.webURL(server: account.server, token: room.token)
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        activity.isEligibleForPrediction = false

        return activity
    }

    // The same link the web interface uses for a conversation
    static func webURL(server: String, token: String?) -> URL? {
        guard let token, !token.isEmpty,
              let encodedToken = token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }

        let trimmedServer = server.hasSuffix("/") ? String(server.dropLast()) : server
        return URL(string: "\(trimmedServer)/index.php/call/\(encodedToken)")
    }

    /// The nextcloudtalk:// link to open the conversation of a continued activity
    static func conversationURL(for userActivity: NSUserActivity) -> NSURLComponents? {
        guard userActivity.activityType == activityType,
              let server = userActivity.userInfo?[serverKey] as? String,
              let user = userActivity.userInfo?[userKey] as? String,
              let token = userActivity.userInfo?[tokenKey] as? String, !token.isEmpty
        else { return nil }

        let urlComponents = NSURLComponents()
        urlComponents.scheme = "nextcloudtalk"
        urlComponents.host = "open-conversation"
        urlComponents.queryItems = [
            URLQueryItem(name: "server", value: server),
            URLQueryItem(name: "user", value: user),
            URLQueryItem(name: "withRoomToken", value: token)
        ]

        return urlComponents
    }
}
