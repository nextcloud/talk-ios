//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitDarwinCenterTest: XCTestCase {

    override func setUpWithError() throws {
        // Reset any remaining handlers for each test
        for (notificationName, handlerDict) in DarwinNotificationCenter.shared.handlers {
            for (owner, _) in handlerDict {
                DarwinNotificationCenter.shared.removeHandler(notificationName: notificationName, owner: owner)
            }
        }

        XCTAssertTrue(DarwinNotificationCenter.shared.handlers.isEmpty)
    }

    func testDarwinCenterHandlerSingle() throws {
        let center = DarwinNotificationCenter.shared

        let expStarted = expectation(description: "\(#function)\(#line)")
        let expStopped = expectation(description: "\(#function)\(#line)")

        center.addHandler(notificationName: DarwinNotificationCenter.broadcastStartedNotification, owner: self) {
            expStarted.fulfill()
        }

        center.addHandler(notificationName: DarwinNotificationCenter.broadcastStoppedNotification, owner: self) {
            expStopped.fulfill()
        }

        // Check if the handlers are correctly registered
        XCTAssertEqual(center.handlers[DarwinNotificationCenter.broadcastStartedNotification]?.count, 1)
        XCTAssertEqual(center.handlers[DarwinNotificationCenter.broadcastStoppedNotification]?.count, 1)

        // Check if the handlers are correctly called after posting a notification
        center.postNotification(DarwinNotificationCenter.broadcastStartedNotification)
        center.postNotification(DarwinNotificationCenter.broadcastStoppedNotification)
        wait(for: [expStarted, expStopped], timeout: TestConstants.timeoutShort)

        // Check if the handlers are correctly cleaned up
        center.removeHandler(notificationName: DarwinNotificationCenter.broadcastStartedNotification, owner: self)
        center.removeHandler(notificationName: DarwinNotificationCenter.broadcastStoppedNotification, owner: self)

        XCTAssertNil(center.handlers[DarwinNotificationCenter.broadcastStartedNotification])
        XCTAssertNil(center.handlers[DarwinNotificationCenter.broadcastStoppedNotification])
    }

    func testDarwinCenterHandlerMultiple() throws {
        let center = DarwinNotificationCenter.shared

        let owner1 = NSObject()

        // We need to wait twice for the expectation
        // 1. Before the handler is removed to ensure it is correctly called
        // 2. After a notification was posted a second time to ensure the first handler wasn't called multiple times
        let expSingleStarted = expectation(description: "\(#function)\(#line)")
        let expSingleStopped = expectation(description: "\(#function)\(#line)")
        let expSingleStartedEnd = expectation(description: "\(#function)\(#line)")
        let expSingleStoppedEnd = expectation(description: "\(#function)\(#line)")

        center.addHandler(notificationName: DarwinNotificationCenter.broadcastStartedNotification, owner: owner1) {
            expSingleStarted.fulfill()
            expSingleStartedEnd.fulfill()
        }

        center.addHandler(notificationName: DarwinNotificationCenter.broadcastStoppedNotification, owner: owner1) {
            expSingleStopped.fulfill()
            expSingleStoppedEnd.fulfill()
        }

        let owner2 = NSObject()
        let expStartedSecond = expectation(description: "\(#function)\(#line)")
        let expStoppedSecond = expectation(description: "\(#function)\(#line)")

        expStartedSecond.expectedFulfillmentCount = 2
        expStoppedSecond.expectedFulfillmentCount = 2

        center.addHandler(notificationName: DarwinNotificationCenter.broadcastStartedNotification, owner: owner2) {
            expStartedSecond.fulfill()
        }

        center.addHandler(notificationName: DarwinNotificationCenter.broadcastStoppedNotification, owner: owner2) {
            expStoppedSecond.fulfill()
        }

        // Call the handlers a first time
        center.postNotification(DarwinNotificationCenter.broadcastStartedNotification)
        center.postNotification(DarwinNotificationCenter.broadcastStoppedNotification)

        wait(for: [expSingleStarted, expSingleStopped], timeout: TestConstants.timeoutShort)

        // Remove the handlers of owner1
        center.removeHandler(notificationName: DarwinNotificationCenter.broadcastStartedNotification, owner: owner1)
        center.removeHandler(notificationName: DarwinNotificationCenter.broadcastStoppedNotification, owner: owner1)

        // Call the handlers a second time
        center.postNotification(DarwinNotificationCenter.broadcastStartedNotification)
        center.postNotification(DarwinNotificationCenter.broadcastStoppedNotification)

        // Also check the expectations from the first call to make sure, they were only called once and not again
        // We can't wait for an expectation twice, that's why we use a second expectation
        wait(for: [expStartedSecond, expStoppedSecond, expSingleStartedEnd, expSingleStoppedEnd], timeout: TestConstants.timeoutShort)
    }

    func testDarwinCenterUnbalancedRemove() throws {
        let center = DarwinNotificationCenter.shared

        let expStarted = expectation(description: "\(#function)\(#line)")

        center.addHandler(notificationName: DarwinNotificationCenter.broadcastStartedNotification, owner: self) {
            expStarted.fulfill()
        }

        center.postNotification(DarwinNotificationCenter.broadcastStartedNotification)
        wait(for: [expStarted], timeout: TestConstants.timeoutShort)

        // Remove ourselves twice
        center.removeHandler(notificationName: DarwinNotificationCenter.broadcastStartedNotification, owner: self)
        center.removeHandler(notificationName: DarwinNotificationCenter.broadcastStartedNotification, owner: self)

        XCTAssertNil(center.handlers[DarwinNotificationCenter.broadcastStartedNotification])
    }
}
