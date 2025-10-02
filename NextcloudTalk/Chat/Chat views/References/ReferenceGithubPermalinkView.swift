//
// SPDX-FileCopyrightText: 2023 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftyAttributes

@objcMembers class ReferenceGithubPermalinkView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var referenceTypeIcon: UIImageView!
    @IBOutlet weak var referenceTitle: UILabel!
    @IBOutlet weak var referenceBody: UITextView!

    var url: String?
    var allLines: [String]?
    var lineBegin = 0
    var lineEnd = 0
    var fileName = ""
    var owner = ""
    var repo = ""

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
        if let url = url, let allLines = allLines {
            // Use a monospaced font here to make overlaying the two textViews possible
            guard let font = Font(name: "Menlo", size: 16) else {
                return
            }

            // In case of a single line reference, we don't receive a lineEnd property
            if self.lineEnd < self.lineBegin {
                self.lineEnd = self.lineBegin
            }

            // Calculate the size/width of the line numbers at the front of each line
            let sizeOfLineNumbersAndTab = ("\(self.lineEnd):  " as NSString).size(withAttributes: [NSAttributedString.Key.font: font])

            // Create a paragraph with
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.headIndent = sizeOfLineNumbersAndTab.width.rounded(.up)

            // We have actually two different attributed strings, one has line numbers prefixed to the actual line
            // and one is without line numbers to allow overlaying it in the view controller
            var sourceWithNumbers = NSAttributedString()
            var sourceWithoutNumbers = NSAttributedString()

            var lineCounter = self.lineBegin

            // Remove any global indentation (preview only does it for the first 3 lines)
            var tempLines = removeIndentation(for: " ", in: allLines)
            tempLines = removeIndentation(for: "\t", in: tempLines)

            // We need to pad the line numbers with a space to have them align properly
            // so we determine the character count of the largest linenumber
            let maximumLineNumberLength = String(lineEnd).count

            for line in tempLines {
                // Tabs might have a bad impact on indentation, so we replace them by default with spaces
                var tempLine = line.replacingOccurrences(of: "\t", with: "   ")

                // Empty lines have a different height in the textview, so we replace them with a space
                if line.isEmpty {
                    tempLine = " "
                }

                // Create the plain source code as a attributed string
                let formattedLine = tempLine.withFont(font).withTextColor(.label) + "\n".attributedString
                sourceWithoutNumbers += formattedLine

                // Make sure the line numbers are probably padded to the left
                let lineCounterString = String(lineCounter)
                let lineNumberString = String(repeating: " ", count: maximumLineNumberLength - lineCounterString.count) + lineCounterString

                // Create the source code as a attributed string including the line counter
                var attributedLineNumber = lineNumberString.withTextColor(.secondaryLabel) + ":  ".withTextColor(.secondaryLabel)
                attributedLineNumber = attributedLineNumber.withFont(font)

                // Include a paragraph style to make sure that breaked lines are indented after the line numbers
                let formattedLineWithLineNumber = attributedLineNumber + formattedLine
                sourceWithNumbers += formattedLineWithLineNumber.withParagraphStyle(paragraphStyle)

                lineCounter += 1
            }

            let permalinkVC = GithubPermalinkViewController(url: url,
                                                            sourceWithLineNumbers: sourceWithNumbers,
                                                            sourceWithoutLineNumbers: sourceWithoutNumbers,
                                                            owner: self.owner,
                                                            repo: self.repo,
                                                            filePath: self.fileName,
                                                            lineNumberWidth: sizeOfLineNumbersAndTab.width)

            let navigationVC = UINavigationController(rootViewController: permalinkVC)
            NCUserInterfaceController.sharedInstance().mainViewController.present(navigationVC, animated: true)
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
            } else if lineIndentation < totalIndentation ?? 0, !line.isEmpty {
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
        self.referenceTypeIcon.image = UIImage(named: "github")?.withTintColor(.systemGray)

        let font = Font.systemFont(ofSize: 15)

        if let type = reference["github_type"] as? String, type == "code-error" {
            referenceTitle.text = NSLocalizedString("GitHub API error", comment: "")

            if let bodyDict = reference["body"] as? [String: String],
               let body = bodyDict["message"] {

                referenceBody.attributedText = body.withFont(font).withTextColor(.secondaryLabel)
            } else {
                referenceBody.attributedText = NSLocalizedString("Unknown error", comment: "").withFont(font).withTextColor(.secondaryLabel)
            }

            return
        }

        if let filePath = reference["filePath"] as? String {
            let filePathUrl = URL(string: filePath)
            self.referenceTitle.text = filePathUrl?.lastPathComponent
            self.fileName = filePathUrl?.lastPathComponent ?? ""
        }

        self.lineBegin = reference["lineBegin"] as? Int ?? 0
        self.lineEnd = reference["lineEnd"] as? Int ?? 0
        self.owner = reference["owner"] as? String ?? ""
        self.repo = reference["repo"] as? String ?? ""

        if let lines = reference["lines"] as? [String], !lines.isEmpty {
            // Remove global indentation if possible
            let previewLines = Array(lines.prefix(upTo: min(3, lines.count)))
            var tempLines = removeIndentation(for: " ", in: previewLines)
            tempLines = removeIndentation(for: "\t", in: tempLines)

            var previewString = NSAttributedString()

            // Each line should have its own lineBreakMode, therefore each line has a paragraph style attached
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineBreakMode = .byTruncatingTail

            for line in tempLines {
                let attributedLine = line.withParagraphStyle(paragraphStyle).withFont(font).withTextColor(.secondaryLabel)
                previewString += attributedLine + NSAttributedString(string: "\n")
            }

            self.allLines = lines
            self.referenceBody.attributedText = previewString
        } else {
            self.allLines = []
            self.referenceBody.text = ""
        }
    }
}
