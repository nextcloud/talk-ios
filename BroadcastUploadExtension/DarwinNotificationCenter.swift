//
//  DarwinNotificationCenter.swift
//  Broadcast Extension
//
//  Created by Alex-Dan Bumbu on 23/03/2021.
//  Copyright © 2021 8x8, Inc. All rights reserved.
//
// From https://github.com/jitsi/jitsi-meet-sdk-samples (Apache 2.0 license)
// SPDX-License-Identifier: Apache-2.0

import Foundation

@objcMembers public class DarwinNotificationCenter: NSObject {

    static let shared = DarwinNotificationCenter()
    static let broadcastStartedNotification = "TalkiOS_BroadcastStarted"
    static let broadcastStoppedNotification = "TalkiOS_BroadcastStopped"

    private let notificationCenter: CFNotificationCenter
    private var handlers: [String: [() -> Void]] = [:]

    override init() {
        notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
    }

    func postNotification(_ name: String) {
        CFNotificationCenterPostNotification(notificationCenter, CFNotificationName(rawValue: name as CFString), nil, nil, true)
    }

    func addObserver(notificationName: String, completionBlock: @escaping () -> Void) {
        if handlers[notificationName] == nil {
            handlers[notificationName] = []
        }

        handlers[notificationName]?.append(completionBlock)
        let observer = Unmanaged.passUnretained(self).toOpaque()

        // see: https://stackoverflow.com/a/33262376
        let callback: CFNotificationCallback = { _, observer, name, _, _ in
            if let observer, let name {
                // Extract pointer to `self` from void pointer:
                let mySelf = Unmanaged<DarwinNotificationCenter>.fromOpaque(observer).takeUnretainedValue()

                if let handlers = mySelf.handlers[name.rawValue as String] {
                    for handler in handlers {
                        handler()
                    }
                }
            }
        }

        CFNotificationCenterAddObserver(self.notificationCenter, observer, callback, notificationName as CFString, nil, .coalesce)
    }

    func removeObserver(_ name: String) {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        let name = CFNotificationName(rawValue: name as CFString)
        CFNotificationCenterRemoveObserver(notificationCenter, observer, name, nil)
    }
}
