//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

// Watches the thermal state and Low Power Mode during a call. Encoding and decoding video is
// what heats up the device the most, so while it is hot or should save power, less video is used.
class CallPerformanceMonitor {

    enum Reason {
        case none
        case thermalState
        case lowPowerMode
    }

    private(set) var maxVideoQuality: SimulcastVideoQuality = .high
    private(set) var reason: Reason = .none

    // Called on the main thread, whenever the maximum video quality changed
    var onChange: ((_ maxVideoQuality: SimulcastVideoQuality, _ reason: Reason) -> Void)?

    private let processInfo: ProcessInfo

    init(processInfo: ProcessInfo = .processInfo) {
        self.processInfo = processInfo

        self.update(notify: false)

        NotificationCenter.default.addObserver(self, selector: #selector(stateDidChange), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stateDidChange), name: .NSProcessInfoPowerStateDidChange, object: nil)
    }

    static func maxVideoQuality(thermalState: ProcessInfo.ThermalState, isLowPowerModeEnabled: Bool) -> (quality: SimulcastVideoQuality, reason: Reason) {
        switch thermalState {
        case .critical:
            return (.low, .thermalState)
        case .serious:
            return (.medium, .thermalState)
        default:
            return isLowPowerModeEnabled ? (.medium, .lowPowerMode) : (.high, .none)
        }
    }

    @objc private func stateDidChange() {
        // The notifications are posted on an arbitrary thread
        DispatchQueue.main.async {
            self.update(notify: true)
        }
    }

    private func update(notify: Bool) {
        let (quality, reason) = Self.maxVideoQuality(thermalState: processInfo.thermalState, isLowPowerModeEnabled: processInfo.isLowPowerModeEnabled)

        guard quality != self.maxVideoQuality || reason != self.reason else { return }

        NCLog.log("Call video quality limited to \(quality) (thermal state: \(processInfo.thermalState.rawValue), low power mode: \(processInfo.isLowPowerModeEnabled))")

        self.maxVideoQuality = quality
        self.reason = reason

        if notify {
            self.onChange?(quality, reason)
        }
    }
}
