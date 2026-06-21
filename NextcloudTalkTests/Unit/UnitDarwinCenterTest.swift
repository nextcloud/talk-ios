//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import Testing
@testable import NextcloudTalk

@Suite(.serialized) @MainActor
final class UnitDarwinCenterTest {

    private let startedNotification = DarwinNotificationCenter.broadcastStartedNotification
    private let stoppedNotification = DarwinNotificationCenter.broadcastStoppedNotification

    /// A small reference-type counter that the run-loop-delivered handlers can increment.
    private final class CallCounter {
        private(set) var callCount = 0
        func increment() { callCount += 1 }
    }

    init() {
        // Reset any remaining handlers for each test
        let center = DarwinNotificationCenter.shared
        for (notificationName, handlerDict) in center.handlers {
            for (owner, _) in handlerDict {
                center.removeHandler(notificationName: notificationName, owner: owner)
            }
        }

        #expect(center.handlers.isEmpty)
    }

    /// Darwin notifications are delivered on the run loop, so we need to give it time to run.
    /// Pumps the run loop until `condition` is satisfied or the timeout elapses.
    private func wait(timeout: TimeInterval = TestConstants.timeoutShort, until condition: () -> Bool) async {
        let start = Date()
        while !condition(), Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
        }
    }

    @Test func `single owner handler lifecycle`() async {
        let center = DarwinNotificationCenter.shared
        let owner = NSObject()

        let startedCounter = CallCounter()
        let stoppedCounter = CallCounter()

        await confirmation("Started handler is called") { startedConfirm in
            await confirmation("Stopped handler is called") { stoppedConfirm in
                center.addHandler(notificationName: startedNotification, owner: owner) {
                    startedCounter.increment()
                    startedConfirm()
                }

                center.addHandler(notificationName: stoppedNotification, owner: owner) {
                    stoppedCounter.increment()
                    stoppedConfirm()
                }

                // Check if the handlers are correctly registered
                #expect(center.handlers[startedNotification]?.count == 1)
                #expect(center.handlers[stoppedNotification]?.count == 1)

                // Check if the handlers are correctly called after posting a notification
                center.postNotification(startedNotification)
                center.postNotification(stoppedNotification)

                await wait { startedCounter.callCount >= 1 && stoppedCounter.callCount >= 1 }
            }
        }

        // Check if the handlers are correctly cleaned up
        center.removeHandler(notificationName: startedNotification, owner: owner)
        center.removeHandler(notificationName: stoppedNotification, owner: owner)

        #expect(center.handlers[startedNotification] == nil)
        #expect(center.handlers[stoppedNotification] == nil)
    }

    @Test func `multiple owner handlers`() async {
        let center = DarwinNotificationCenter.shared

        let owner1 = NSObject()
        let owner2 = NSObject()

        let owner1Started = CallCounter()
        let owner1Stopped = CallCounter()
        let owner2Started = CallCounter()
        let owner2Stopped = CallCounter()

        center.addHandler(notificationName: startedNotification, owner: owner1) { owner1Started.increment() }
        center.addHandler(notificationName: stoppedNotification, owner: owner1) { owner1Stopped.increment() }
        center.addHandler(notificationName: startedNotification, owner: owner2) { owner2Started.increment() }
        center.addHandler(notificationName: stoppedNotification, owner: owner2) { owner2Stopped.increment() }

        // Call the handlers a first time, both owners should receive the notifications
        center.postNotification(startedNotification)
        center.postNotification(stoppedNotification)

        await wait {
            owner1Started.callCount >= 1 && owner1Stopped.callCount >= 1 && owner2Started.callCount >= 1 && owner2Stopped.callCount >= 1
        }

        // Remove the handlers of owner1
        center.removeHandler(notificationName: startedNotification, owner: owner1)
        center.removeHandler(notificationName: stoppedNotification, owner: owner1)

        // Call the handlers a second time, only owner2 should receive the notifications
        center.postNotification(startedNotification)
        center.postNotification(stoppedNotification)

        await wait { owner2Started.callCount >= 2 && owner2Stopped.callCount >= 2 }

        // Make sure the handlers of owner1 were only called once and not again after they were removed
        #expect(owner1Started.callCount == 1)
        #expect(owner1Stopped.callCount == 1)
        #expect(owner2Started.callCount == 2)
        #expect(owner2Stopped.callCount == 2)
    }

    @Test func `unbalanced handler removal`() async {
        let center = DarwinNotificationCenter.shared
        let owner = NSObject()

        let startedCounter = CallCounter()

        center.addHandler(notificationName: startedNotification, owner: owner) { startedCounter.increment() }

        center.postNotification(startedNotification)
        await wait { startedCounter.callCount >= 1 }

        // Remove ourselves twice
        center.removeHandler(notificationName: startedNotification, owner: owner)
        center.removeHandler(notificationName: startedNotification, owner: owner)

        #expect(center.handlers[startedNotification] == nil)
    }
}
