//
// Copyright (c) 2024 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Marcel Müller <marcel-mueller@gmx.de>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation

@objcMembers public class BannedActor: NSObject {

    public var banId: Int = 0
    public var actorType: String?
    public var actorId: String?
    public var bannedType: String?
    public var bannedId: String?
    public var bannedTime: Int?
    public var internalNote: String?

    init(dictionary: [String: Any]) {
        super.init()

        self.banId = dictionary["id"] as? Int ?? 0
        self.actorType = dictionary["actorType"] as? String
        self.actorId = dictionary["actorId"] as? String
        self.bannedType = dictionary["bannedType"] as? String
        self.bannedId = dictionary["bannedId"] as? String
        self.bannedTime = dictionary["bannedTime"] as? Int
        self.internalNote = dictionary["internalNote"] as? String
    }
}
