//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

@objcMembers class AllocationTracker: NSObject {

    public static let shared = AllocationTracker()

    private var allocationDict: [String: Int] = [:]

    public func addAllocation(_ name: String = #fileID) {
        if !NCUtils.isTestEnvironment {
            return
        }

        allocationDict[name, default: 0] += 1
    }

    public func removeAllocation(_ name: String = #fileID) {
        if !NCUtils.isTestEnvironment {
            return
        }

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
        if !NCUtils.isTestEnvironment {
            return "Not running in testing environment."
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: allocationDict, options: .sortedKeys),
           let jsonString = String(data: jsonData, encoding: .utf8) {

            return jsonString
        }

        return "Unknown"
    }
}
