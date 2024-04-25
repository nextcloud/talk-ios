//
// Copyright (c) 2024 Marcel Müller <marcel.mueller@nextcloud.com>
//
// Author Marcel Müller <marcel.mueller@nextcloud.com>
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

import UIKit

@objcMembers class AllocationTracker: NSObject {

    public static let shared = AllocationTracker()

    private var allocationDict: [String: Int] = [:]

    public func addAllocation(_ name: String) {
        allocationDict[name, default: 0] += 1
    }

    public func removeAllocation(_ name: String) {
        if let currentAllocations = allocationDict[name] {
            if currentAllocations == 1 {
                allocationDict.removeValue(forKey: name)
            } else {
                allocationDict[name] = currentAllocations - 1
            }
        } else {
            print("WARNING: Removing non-existing allocation")
        }
    }

    override var description: String {
        if let jsonData = try? JSONSerialization.data(withJSONObject: allocationDict, options: .sortedKeys),
           let jsonString = String(data: jsonData, encoding: .utf8) {

            return jsonString
        }

        return "Unknown"
    }
}
