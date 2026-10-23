//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Network

// The status stays unknown, and therefore not reachable, until the first path update arrives after startMonitoring()
class NCNetworkReachability {

    enum Status {
        case unknown
        case notReachable
        case reachableViaCellular
        case reachableViaOther
    }

    static let shared = NCNetworkReachability()

    // Called on the main queue, only when the status actually changes
    var statusChangeHandler: ((Status) -> Void)?

    private(set) var status: Status = .unknown

    var isReachable: Bool {
        return status == .reachableViaCellular || status == .reachableViaOther
    }

    private let monitor = NWPathMonitor()
    private var isMonitoring = false

    func startMonitoring() {
        // A NWPathMonitor can only be started once
        guard !isMonitoring else { return }
        isMonitoring = true

        monitor.pathUpdateHandler = { [weak self] path in
            let status = Self.status(for: path)

            DispatchQueue.main.async {
                guard let self, status != self.status else { return }

                self.status = status
                self.statusChangeHandler?(status)
            }
        }

        monitor.start(queue: DispatchQueue(label: "com.nextcloud.talk.reachability"))
    }

    private static func status(for path: NWPath) -> Status {
        guard path.status == .satisfied else { return .notReachable }

        return path.usesInterfaceType(.cellular) ? .reachableViaCellular : .reachableViaOther
    }
}
