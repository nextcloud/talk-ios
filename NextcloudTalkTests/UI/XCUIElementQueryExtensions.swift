//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import XCTest

extension XCUIElementQuery {

    func labelContains(_ searchString: String) -> XCUIElement {
        let predicateLabel = NSPredicate(format: "label CONTAINS[c] %@", searchString)
        return self.element(matching: predicateLabel)
    }

    func valueContains(_ searchString: String) -> XCUIElement {
        let predicateLabel = NSPredicate(format: "value CONTAINS[c] %@", searchString)
        return self.element(matching: predicateLabel)
    }

}
