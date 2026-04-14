//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

// Needs to be Int to be accessible by Objc
@objc
public enum NCAPIType: Int {
    case conversation
    case call
    case chat
    case reactions
    case polls
    case breakoutRooms
    case federation
    case ban
    case bots
    case signaling
    case recording
    case settings
    case avatar
}
