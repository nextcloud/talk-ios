//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Testing
@testable import NextcloudTalk

struct UnitColorGeneratorTest {

    // See: https://github.com/nextcloud-libraries/nextcloud-vue/blob/76cc5dec7305f8e83b6380893e391d53770fb272/tests/unit/functions/usernameToColor/usernameToColor.spec.js#L10
    @Test(arguments: [
        (username: "", expectedHexColor: "#0082c9"),
        (username: ",", expectedHexColor: "#1e78c1"),
        (username: ".", expectedHexColor: "#c98879"),
        (username: "admin", expectedHexColor: "#d09e6d"),
        (username: "123e4567-e89b-12d3-a456-426614174000", expectedHexColor: "#bc5c91"),
        (username: "Akeel Robertson", expectedHexColor: "#9750a4"),
        (username: "Brayden Truong", expectedHexColor: "#d09e6d"),
        (username: "Daphne Roy", expectedHexColor: "#9750a4"),
        (username: "Ellena Wright Frederic Conway", expectedHexColor: "#c37285"),
        (username: "Gianluca Hills", expectedHexColor: "#d6b461"),
        (username: "Haseeb Stephens", expectedHexColor: "#d6b461"),
        (username: "Idris Mac", expectedHexColor: "#9750a4"),
        (username: "Kristi Fisher", expectedHexColor: "#0082c9"),
        (username: "Lillian Wall", expectedHexColor: "#bc5c91"),
        (username: "Lorelai Taylor", expectedHexColor: "#ddcb55"),
        (username: "Madina Knight", expectedHexColor: "#9750a4"),
        (username: "Meeting", expectedHexColor: "#c98879"),
        (username: "Private Circle", expectedHexColor: "#c37285"),
        (username: "Rae Hope", expectedHexColor: "#795aab"),
        (username: "Santiago Singleton", expectedHexColor: "#bc5c91"),
        (username: "Sid Combs", expectedHexColor: "#d09e6d"),
        (username: "TestCircle", expectedHexColor: "#499aa2"),
        (username: "Tom Mörtel", expectedHexColor: "#248eb5"),
        (username: "Vivienne Jacobs", expectedHexColor: "#1e78c1"),
        (username: "Zaki Cortes", expectedHexColor: "#6ea68f"),
        (username: "a user", expectedHexColor: "#5b64b3"),
        (username: "admin@cloud.example.com", expectedHexColor: "#9750a4"),
        (username: "another user", expectedHexColor: "#ddcb55"),
        (username: "asd", expectedHexColor: "#248eb5"),
        (username: "bar", expectedHexColor: "#0082c9"),
        (username: "foo", expectedHexColor: "#d09e6d"),
        (username: "wasd", expectedHexColor: "#b6469d"),
        (username: "مرحبا بالعالم", expectedHexColor: "#c98879"),
        (username: "🙈", expectedHexColor: "#b6469d")
    ])
    func usernameToColor(_ testCase: (username: String, expectedHexColor: String)) {
        let userColor = ColorGenerator.shared.usernameToColor(testCase.username)
        let userHexColor = NCUtils.hexString(fromColor: userColor)

        #expect(userHexColor.lowercased() == testCase.expectedHexColor.lowercased())
    }
}
