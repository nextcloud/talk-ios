//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitTalkActor: XCTestCase {

    func testFirstNameParsing() throws {
        let cases: [(input: String, expected: String)] = [
            // Simple cases
            ("Jane", "Jane"),
            ("Jane Smith", "Jane"),
            ("Jane Middle Smith", "Jane"),
            ("  Jane   Smith  ", "Jane"),

            // Inverted enterprise-directory convention "Lastname, Firstname"
            ("Conrad, Hermes", "Hermes"),
            ("Doe, John Michael", "John"),

            // Comma-separated suffixes / credentials
            ("Jane Smith, MD", "Jane"),
            ("Martin Luther King, Jr.", "Martin"),
            ("Jane Smith, PhD, MBA", "Jane"),
            ("Doe, John, PhD", "John"),

            // Bracketed annotations
            ("Doe, John (Contracting)", "John"),
            ("[Bot] Weather", "Weather"),
            ("Jane (she/her) Smith", "Jane"),

            // Salutations
            ("Dr. Jane Smith", "Jane"),
            ("Prof. Dr. Jane Smith", "Jane"),
            ("Herr Hans Müller", "Hans"),

            // Leading initials: goes by the middle name, but pure initials keep the first
            ("R. Jason Smith", "Jason"),
            ("R. J. Smith", "R."),

            // CJK names are a single component, not initials
            ("山田 太郎", "山田"),

            // Empty / whitespace input
            ("", ""),
            ("   ", "")
        ]

        for testCase in cases {
            XCTAssertEqual(TalkActor.firstName(fromDisplayName: testCase.input), testCase.expected, "firstName of \"\(testCase.input)\"")
        }
    }

    func testFirstNameFallbacks() throws {
        // Non-empty display name is parsed
        XCTAssertEqual(TalkActor(actorDisplayName: "Jane Smith").firstName, "Jane")

        // Empty display name keeps the guest fallback (not parsed into a first name)
        XCTAssertEqual(TalkActor(actorType: "guests", actorDisplayName: "").firstName, "Guest")

        // Empty display name of a deleted user keeps the deleted fallback
        XCTAssertEqual(TalkActor(actorId: "deleted_users", actorType: "deleted_users", actorDisplayName: "").firstName, "Deleted user")
    }
}
