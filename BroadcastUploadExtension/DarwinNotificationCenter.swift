//
//  DarwinNotificationCenter.swift
//  Broadcast Extension
//
//  Created by Alex-Dan Bumbu on 23/03/2021.
//  Copyright © 2021 8x8, Inc. All rights reserved.
//
// From https://github.com/jitsi/jitsi-meet-sdk-samples (Apache 2.0 license)
// SPDX-FileCopyrightText: 2021 Alex-Dan Bumbu, 8x8, Inc. All rights reserved.
// SPDX-License-Identifier: Apache-2.0

import Foundation

@objcMembers public class DarwinNotificationCenter: NSObject {

    static let shared = DarwinNotificationCenter()
    static let broadcastStartedNotification = "TalkiOS_BroadcastStarted"
    static let broadcastStoppedNotification = "TalkiOS_BroadcastStopped"

    private let notificationCenter: CFNotificationCenter

    internal var handlers: [String: [AnyHashable: () -> Void]] = [:]

    override init() {
        notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
    }

    func postNotification(_ name: String) {
        CFNotificationCenterPostNotification(notificationCenter, CFNotificationName(rawValue: name as CFString), nil, nil, true)
    }

    func addHandler(notificationName: String, owner: AnyHashable, completionBlock: @escaping () -> Void) {
        // When there are already handlers, we just add our own here
        if handlers[notificationName] != nil {
            handlers[notificationName]?[owner] = completionBlock
            return
        }

        // No handler for this notification -> setup a new darwin observer for that notification
        handlers[notificationName] = [owner: completionBlock]

        // see: https://stackoverflow.com/a/33262376
        let callback: CFNotificationCallback = { _, observer, name, _, _ in
            if let observer, let name {
                // Extract pointer to `self` from void pointer:
                let mySelf = Unmanaged<DarwinNotificationCenter>.fromOpaque(observer).takeUnretainedValue()

                if let handlers = mySelf.handlers[name.rawValue as String] {
                    for handler in handlers {
                        handler.value()
                    }
                }
            }
        }

        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(self.notificationCenter, observer, callback, notificationName as CFString, nil, .coalesce)
    }

    func removeHandler(notificationName: String, owner: AnyHashable) {
        guard handlers[notificationName] != nil else { return }

        // Remove the handler for the specified owner
        handlers[notificationName]!.removeValue(forKey: owner)

        // There are still other handlers registered for this notification, keep the darwin center observer
        if !handlers[notificationName]!.isEmpty {
            return
        }

        // No handlers registered for that notification anymore, remove the observer from darwin center
        handlers.removeValue(forKey: notificationName)

        let observer = Unmanaged.passUnretained(self).toOpaque()
        let name = CFNotificationName(rawValue: notificationName as CFString)
        CFNotificationCenterRemoveObserver(notificationCenter, observer, name, nil)
    }
}
