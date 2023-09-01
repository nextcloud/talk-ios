//
// Copyright (c) 2023 Marcel Müller <marcel-mueller@gmx.de>
//
// Author Marcel Müller <marcel-mueller@gmx.de>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import CDMarkdownKit
import UIKit

@objcMembers class SwiftMarkdownObjCBridge: NSObject {

    static let markdownParser: CDMarkdownParser = {
        let markdownParser = CDMarkdownParser(font: .systemFont(ofSize: 16), fontColor: NCAppBranding.chatForegroundColor())

        markdownParser.code.backgroundColor = .secondarySystemBackground
        markdownParser.code.font =  CDFont.monospacedSystemFont(ofSize: 16, weight: .regular)

        markdownParser.syntax.backgroundColor = .secondarySystemBackground
        markdownParser.syntax.font =  CDFont.monospacedSystemFont(ofSize: 16, weight: .regular)

        markdownParser.squashNewlines = false
        markdownParser.overwriteExistingStyle = false
        markdownParser.trimLeadingWhitespaces = false

        markdownParser.image.enabled = false

        // Don't update the font when we have a listing/quote, just the paragraph style
        markdownParser.list.font = nil
        markdownParser.list.color = nil

        markdownParser.quote.font = nil
        markdownParser.quote.color = nil

        return markdownParser
    }()

    static func parseMarkdown(markdownString: NSAttributedString) -> NSMutableAttributedString {
        return NSMutableAttributedString(attributedString: markdownParser.parse(markdownString))
    }
}
