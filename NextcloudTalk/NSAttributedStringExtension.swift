//
// SPDX-FileCopyrightText: 2025 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

extension NSAttributedString {

    /// Initializes an attributed string by replacing placeholders with provided arguments.
    ///
    /// - Parameters:
    ///   - format: The attributed string containing placeholders (only allowed `%@` or positional ones like`%1$@`).
    ///   - args: The arguments to replace the placeholders.
    convenience init?(format: NSAttributedString, _ args: CVarArg...) {
        let mutableAttributedString = NSMutableAttributedString(attributedString: format)

        // Regex patterns for positional placeholders (%1$@, %2$@,…) and non-positional placeholder (%@)
        let positionalRegexPattern = "%(\\d+)\\$@"
        let nonPositionalRegexPattern = "%@"

        guard let positionalRegex = try? NSRegularExpression(pattern: positionalRegexPattern, options: []),
              let nonPositionalRegex = try? NSRegularExpression(pattern: nonPositionalRegexPattern, options: []) else {
            print("Regex creation failed")
            return nil
        }

        let positionalPlaceholders = positionalRegex.matches(in: mutableAttributedString.string, range: NSRange(location: 0, length: mutableAttributedString.length))
        let containsPositionalPlaceholders = !positionalPlaceholders.isEmpty
        let regex = containsPositionalPlaceholders ? positionalRegex : nonPositionalRegex

        guard (containsPositionalPlaceholders && positionalPlaceholders.count == args.count) ||
                (!containsPositionalPlaceholders && args.count == 1) else {
            print("Incorrect number of arguments")
            return nil
        }

        while let match = regex.firstMatch(in: mutableAttributedString.string, range: NSRange(location: 0, length: mutableAttributedString.length)) {
            let matchRange = match.range
            var replacementArg: CVarArg?

            if containsPositionalPlaceholders, match.numberOfRanges > 1,
               // Get range of the capture group (\d+) in the positional regex %(\d+)\$@ and convert it into a Range<String.Index>
               let range = Range(match.range(at: 1), in: mutableAttributedString.string),
               let position = Int(mutableAttributedString.string[range]), position > 0, position <= args.count {
                replacementArg = args[position - 1]
            } else if !args.isEmpty {
                replacementArg = args.first
            }

            // If there's no valid argument to replace, something went wrong
            guard let arg = replacementArg else {
                print("Missing argument for placeholder at range \(matchRange)")
                return nil
            }

            // Convert the argument to an attributed string
            let replacement: NSAttributedString
            if let attributedStringArg = arg as? NSAttributedString {
                replacement = attributedStringArg
            } else {
                replacement = NSAttributedString(string: "\(arg)")
            }

            mutableAttributedString.replaceCharacters(in: matchRange, with: replacement)
        }

        self.init(attributedString: mutableAttributedString)
    }
}
