//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class SignalingSettings: NSObject {

    public var server: String?
    public var signalingMode: String?
    public var ticket: String?
    public var userId: String?
    public var sipDialinInfo: String?
    public var stunServers: [StunServer] = []
    public var turnServers: [TurnServer] = []
    public var federation: [String: Any]?

    init?(dictionary: [String: Any]?) {
        guard let dictionary else { return nil }

        super.init()

        self.server = dictionary["server"] as? String
        self.signalingMode = dictionary["signalingMode"] as? String
        self.ticket = dictionary["ticket"] as? String
        self.userId = dictionary["userId"] as? String
        self.sipDialinInfo = dictionary["sipDialinInfo"] as? String
        self.federation = dictionary["federation"] as? [String: Any]

        if let stunArray = dictionary["stunservers"] as? [[String: Any]] {
            for case let stunDict in stunArray {
                stunServers.append(StunServer(dictionary: stunDict))
            }
        }

        if let turnArray = dictionary["turnservers"] as? [[String: Any]] {
            for case let turnDict in turnArray {
                turnServers.append(TurnServer(dictionary: turnDict))
            }
        }
    }

    public func getFederationJoinDictionary() -> [String: String]? {
        guard let federation, !federation.isEmpty else { return nil }

        var result: [String: String] = [:]

        if let server = federation["server"] as? String {
            result["signaling"] = server
        }

        if let roomid = federation["roomId"] as? String {
            result["roomid"] = roomid
        }

        if let url = federation["nextcloudServer"] as? String {
            // No `index.php` required here, as this is an ocs route
            result["url"] = url + "/ocs/v2.php/apps/spreed/api/v3/signaling/backend"
        }

        if let helloAuthParams = federation["helloAuthParams"] as? [String: String], let token = helloAuthParams["token"] {
            result["token"] = token
        }

        return result
    }
}
