//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import CDMarkdownKit
import UIKit

@objcMembers class SwiftMarkdownObjCBridge: NSObject {

    static let markdownParser: CDMarkdownParser = {
        let markdownParser = CDMarkdownParser(font: .preferredFont(forTextStyle: .body), fontColor: .label)

        markdownParser.code.backgroundColor = .tertiarySystemGroupedBackground
        markdownParser.code.font = .monospacedPreferredFont(forTextStyle: .body)

        markdownParser.syntax.backgroundColor = .tertiarySystemGroupedBackground
        markdownParser.syntax.font = .monospacedPreferredFont(forTextStyle: .body)

        markdownParser.squashNewlines = false
        markdownParser.overwriteExistingStyle = false
        markdownParser.trimLeadingWhitespaces = false
        markdownParser.automaticLinkDetectionEnabled = false

        markdownParser.image.enabled = false

        // Don't update the font when we have a listing/quote (to not override any mentions), just the paragraph style
        markdownParser.list.font = nil
        markdownParser.list.color = nil

        // To correctly position list elements, we need to tell CDMarkdownKit the font to use for sizing
        markdownParser.list.indicatorFont = .preferredFont(forTextStyle: .body)

        markdownParser.quote.font = nil
        markdownParser.quote.color = nil

        return markdownParser
    }()

    static func parseMarkdown(markdownString: NSAttributedString) -> NSMutableAttributedString {
        return NSMutableAttributedString(attributedString: markdownParser.parse(markdownString))
    }

    static func getLayoutManager() -> CDMarkdownLayoutManager {
        let manager = CDMarkdownLayoutManager()
        manager.roundAllCorners = true
        return manager
    }
}
