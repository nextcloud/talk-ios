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
import SwiftyAttributes

@objcMembers class ReferenceGithubPermalinkView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var referenceTypeIcon: UIImageView!
    @IBOutlet weak var referenceTitle: UILabel!
    @IBOutlet weak var referenceBody: UITextView!

    var url: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    func commonInit() {
        Bundle.main.loadNibNamed("ReferenceGithubPermalinkView", owner: self, options: nil)
        contentView.frame = self.bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        referenceTitle.text = ""
        referenceBody.text = ""
        referenceTypeIcon.image = nil

        // Remove padding from textView and adjust lineBreakMode
        referenceBody.textContainerInset = .zero
        referenceBody.textContainer.lineFragmentPadding = .zero
        referenceBody.textContainer.lineBreakMode = .byTruncatingTail
        referenceBody.textContainer.maximumNumberOfLines = 3

        let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleTap))
        contentView.addGestureRecognizer(tap)

        self.addSubview(contentView)
    }

    func handleTap() {
        if let url = url {
            NCUtils.openLink(inBrowser: url)
        }
    }

    // This method tries to remove "global" indentation, while keeping the "local" indentation
    //
    // Input:
    //          <div>
    //              Test
    //          </div>
    //
    // Output:
    // <div>
    //     Test
    // </div>
    func removeIndentation(for character: Character, in elements: [String]) -> [String] {
        let firstLines = elements
        var totalIndentation: Int?

        // Calculate the "global" indentation count
        for line in firstLines {
            // Check how many indentation characters are at the beginning of the string
            let lineIndentation = line.prefix(while: { $0 == character }).count

            if totalIndentation == nil {
                // There was no previous totalIdentation, so we use this one as a starting point
                totalIndentation = lineIndentation
            } else if lineIndentation < totalIndentation ?? 0 {
                // We found a line with a lower number of intendation characters -> use this
                totalIndentation = lineIndentation
            }
        }

        // Remove indentation for each line
        if let totalIndentation = totalIndentation, totalIndentation > 0 {
            var tempLines: [String] = []

            // Example: If we calculated a total indentation of 5, the search string would be "     "
            let searchString = String(repeating: character, count: totalIndentation)

            for line in firstLines {
                // Check if the search string actually appears in the current line
                if let range = line.range(of: searchString) {
                    // Detect if the search string is at the beginning of the current line
                    let startIndexOfRange = line.distance(from: line.startIndex, to: range.lowerBound)

                    if startIndexOfRange == 0 {
                        // Replace the global indentation at the beginning of this line and keep the rest
                        let replacedLine = line.replacingOccurrences(of: searchString, with: "", range: range)

                        tempLines.append(replacedLine)
                        continue
                    }
                }

                tempLines.append(line)
            }

            return tempLines
        } else {
            return elements
        }
    }

    func update(for reference: [String: AnyObject], and url: String) {
        self.url = url

        if let filePath = reference["filePath"] as? String {
            let filePathUrl = URL(string: filePath)
            self.referenceTitle.text = filePathUrl?.lastPathComponent
        }

        self.referenceTypeIcon.image = UIImage(named: "github")?.withTintColor(UIColor.systemGray)

        if let lines = reference["lines"] as? [String], !lines.isEmpty {
            let firstLines = Array(lines.prefix(upTo: min(3, lines.count) ))

            // Remove global indentation if possible
            var tempLines = removeIndentation(for: " ", in: firstLines)
            tempLines = removeIndentation(for: "\t", in: tempLines)

            var resultLines = NSAttributedString()

            // Each line should have its own lineBreakMode, therefore each line has a paragraph style attached
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byTruncatingTail

            let font = Font.systemFont(ofSize: 16)

            for line in tempLines {
                let attributedLine = line.withParagraphStyle(paragraphStyle).withFont(font).withTextColor(.secondaryLabel)
                resultLines += attributedLine + NSAttributedString(string: "\n")
            }

            self.referenceBody.attributedText = resultLines
        } else {
            self.referenceBody.text = ""
        }
    }
}
