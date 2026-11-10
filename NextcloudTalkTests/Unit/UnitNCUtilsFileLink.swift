//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import XCTest
@testable import NextcloudTalk

final class UnitNCUtilsFileLink: XCTestCase {

    func testInstanceFileIdFromLink() throws {
        let server = "https://cloud.example.com"

        let cases: [(link: String, expected: String?)] = [
            // Internal links
            ("https://cloud.example.com/f/42", "42"),
            ("https://cloud.example.com/index.php/f/42", "42"),
            ("https://cloud.example.com/f/42/", "42"),
            ("https://cloud.example.com/f/42?foo=bar", "42"),
            ("https://cloud.example.com/f/42#details", "42"),
            ("https://CLOUD.example.com/f/42", "42"),

            // Files app links
            ("https://cloud.example.com/apps/files/files/42?dir=/Documents&openfile=true", "42"),
            ("https://cloud.example.com/index.php/apps/files/files/42?dir=/", "42"),
            ("https://cloud.example.com/apps/files/?dir=/Documents&fileid=42", "42"),
            ("https://cloud.example.com/index.php/apps/files/?fileid=42&dir=/", "42"),

            // Not file links
            ("https://cloud.example.com/f/", nil),
            ("https://cloud.example.com/f/abc", nil),
            ("https://cloud.example.com/f/42/more", nil),
            ("https://cloud.example.com/apps/files/?dir=/Documents", nil),
            ("https://cloud.example.com/apps/files/?fileid=", nil),
            ("https://cloud.example.com/apps/files/favorites/42", nil),
            ("https://cloud.example.com/s/AbCdEf123", nil),
            ("https://cloud.example.com/call/abc123", nil),

            // Other servers
            ("https://other.example.com/f/42", nil),
            ("https://cloud.example.com.evil.com/f/42", nil),
            ("https://cloud.example.comevil/f/42", nil),
            ("https://cloud.example.com:8443/f/42", nil),
            ("http://cloud.example.com/f/42", nil),
            ("https://evil.com/?https://cloud.example.com/f/42", nil)
        ]

        for testCase in cases {
            XCTAssertEqual(NCUtils.instanceFileId(fromLink: testCase.link, serverUrl: server), testCase.expected, testCase.link)
        }
    }

    func testInstanceFileIdFromLinkWithSubfolder() throws {
        let server = "https://example.com/nextcloud"

        XCTAssertEqual(NCUtils.instanceFileId(fromLink: "https://example.com/nextcloud/index.php/f/42", serverUrl: server), "42")
        XCTAssertEqual(NCUtils.instanceFileId(fromLink: "https://example.com/nextcloud/apps/files/files/42?dir=/", serverUrl: server), "42")
        XCTAssertEqual(NCUtils.instanceFileId(fromLink: "https://example.com/nextcloud/f/42", serverUrl: "\(server)/"), "42")
        XCTAssertNil(NCUtils.instanceFileId(fromLink: "https://example.com/f/42", serverUrl: server))
    }
}
