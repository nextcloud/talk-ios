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

@objcMembers public class OcsResponse: NSObject {

    let data: Any?
    
    lazy var responseDict: [String: AnyObject]? = {
        return data as? [String: AnyObject]
    }()

    lazy var ocsDict: [String: AnyObject]? = {
        return responseDict?["ocs"] as? [String: AnyObject]
    }()

    lazy var dataDict: [String: AnyObject]? = {
        return ocsDict?["data"] as? [String: AnyObject]
    }()

    lazy var dataArrayDict: [[String: AnyObject]]? = {
        return ocsDict?["data"] as? [[String: AnyObject]]
    }()

    init(withData data: Any?) {
        self.data = data
    }
}
