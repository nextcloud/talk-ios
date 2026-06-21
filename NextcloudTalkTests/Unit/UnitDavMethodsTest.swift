//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
@testable import NextcloudTalk

@Suite(.serialized)
final class UnitDavMethodsTest: TestBaseRealm {

    @Test func `alternative names`() throws {
        #expect(NCAPIController.sharedInstance().alternativeName(forFileName: "test.pdf", isOriginal: true) == "test (1).pdf")
        #expect(NCAPIController.sharedInstance().alternativeName(forFileName: "test (1).pdf", isOriginal: true) == "test (1) (1).pdf")
        #expect(NCAPIController.sharedInstance().alternativeName(forFileName: "test (1).pdf", isOriginal: false) == "test (2).pdf")
        #expect(NCAPIController.sharedInstance().alternativeName(forFileName: "test (24).pdf", isOriginal: false) == "test (25).pdf")
        #expect(NCAPIController.sharedInstance().alternativeName(forFileName: "test (24) (1).pdf", isOriginal: false) == "test (24) (2).pdf")
        #expect(NCAPIController.sharedInstance().alternativeName(forFileName: "test (24) (1)", isOriginal: false) == "test (24) (2)")
    }
}
