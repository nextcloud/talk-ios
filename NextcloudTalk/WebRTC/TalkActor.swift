//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import SwiftyAttributes

@objcMembers public class TalkActor: NSObject {

    public var id: String?
    public var type: String?

    /// Contains the raw displayName that was used to create the TalkActor
    public var rawDisplayName: String

    /// Takes deleted users and guests into account and returns the correct displayName
    /// Does **not** append a potential `cloudId`
    public var displayName: String {
        if rawDisplayName.isEmpty {
            if isDeleted {
                return NSLocalizedString("Deleted user", comment: "")
            } else {
                return NSLocalizedString("Guest", comment: "")
            }
        }

        return rawDisplayName
    }

    /// Takes deleted users and guests into account and returns it as `secondaryLabel`
    /// This also appends a potential `cloudId` as `tertiaryLabel` in parentheses
    public var attributedDisplayName: NSMutableAttributedString {
        let displayName = self.displayName
        let titleLabel = displayName.withTextColor(.secondaryLabel)

        if let remoteServer = cloudId {
            let remoteServerString = " (\(String(remoteServer)))"
            titleLabel.append(remoteServerString.withTextColor(.tertiaryLabel))
        } else if isGuest, !rawDisplayName.isEmpty {
            // Show guest indication only when we did not use the default "Guest" name
            let guestString = " (\(NSLocalizedString("guest", comment: "")))"
            titleLabel.append(guestString.withTextColor(.tertiaryLabel))
        }

        return titleLabel
    }

    init(actorId: String? = nil, actorType: String? = nil, actorDisplayName: String? = nil) {
        self.id = actorId
        self.type = actorType
        self.rawDisplayName = actorDisplayName ?? ""
    }

    public var isDeleted: Bool {
        return id == "deleted_users" && type == "deleted_users"
    }

    public var isFederated: Bool {
        return type == "federated_users"
    }

    public var isGuest: Bool {
        return type == "guests" || type == "emails"
    }

    public var cloudId: String? {
        guard isFederated, let remoteServer = id?.split(separator: "@").last else { return nil }

        return String(remoteServer)
    }

    /// The first (given) name of the actor, keeping the guest/deleted fallback of `displayName` intact
    public var firstName: String {
        guard !rawDisplayName.isEmpty else { return displayName }

        return TalkActor.firstName(fromDisplayName: rawDisplayName)
    }

    // MARK: - First name parsing

    /// Suffixes and post-nominal credentials that may follow a comma in a display name
    /// (e.g. "Martin Luther King, Jr." or "Mary Williams, BSN").
    /// Based on https://github.com/joshfraser/JavaScript-Name-Parser
    private static let suffixPattern = try! NSRegularExpression(
        pattern: "^(?:"
               + "i{1,3}|iv|v|senior|junior|jr|sr" // generational
               + "|phd|apr|rph|pe|md|ma|msc|bsc|ba|bs|dmd|cme|bsn|mba" // academic / professional
               + "|ceo|cto|cfo|coo" // job titles
               + ")$",
        options: [.caseInsensitive])

    /// Salutations / honorific prefixes that may precede a given name (e.g. "Dr. Jane Smith").
    private static let salutationPattern = try! NSRegularExpression(
        pattern: "^(?:mr|mrs|ms|miss|master|mister|dr|rev|fr|prof|herr|frau|mme|mlle|me|pr)$",
        options: [.caseInsensitive])

    /// Single-letter initial restricted to alphabetic scripts ("R.", "J", "А.").
    /// A single CJK character is a complete name component, not an initial.
    private static let initialPattern = try! NSRegularExpression(
        pattern: "^[\\p{script=Latin}\\p{script=Cyrillic}\\p{script=Greek}]$",
        options: [])

    /// Bracketed annotations: "Doe, John (Contracting)", "[Bot] Weather", "{tag}".
    private static let bracketPattern = try! NSRegularExpression(
        pattern: "\\([^()]*\\)|\\[[^\\[\\]]*\\]|\\{[^{}]*\\}",
        options: [])

    /// Normalizes a word for pattern matching (strips periods and commas, e.g. "Ph.D." => "PhD").
    private static func normalize(_ word: String) -> String {
        return word.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")
    }

    private static func matches(_ word: String, _ pattern: NSRegularExpression) -> Bool {
        let normalized = normalize(word)
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)

        return pattern.firstMatch(in: normalized, range: range) != nil
    }

    /// Returns the first (given) name of a display name.
    ///
    /// Handles the inverted enterprise-directory convention ("Lastname, Firstname"),
    /// comma-separated suffixes and credentials ("Martin Luther King, Jr.", "Jane Smith, MD"),
    /// bracketed annotations ("Doe, John (Contracting)", "[Bot] Weather") and salutations
    /// ("Prof. Dr. Jane Smith"). Falls back to the trimmed input if nothing better can be extracted.
    static func firstName(fromDisplayName fullName: String) -> String {
        func words(_ string: String) -> [String] {
            return string.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        }

        // Drop bracketed annotations: "Doe, John (Contracting)" => "Doe, John"
        let bracketRange = NSRange(fullName.startIndex..<fullName.endIndex, in: fullName)
        let cleanedName = bracketPattern
            .stringByReplacingMatches(in: fullName, range: bracketRange, withTemplate: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Word lists of comma-separated segments: "King, Martin Luther, Jr." => [["King"], ["Martin", "Luther"], ["Jr."]]
        var segments = cleanedName.components(separatedBy: ",")
            .map { words($0) }
            .filter { !$0.isEmpty }

        // Drop trailing segments consisting only of suffixes: [["King"], ["Martin", "Luther"], ["Jr."]] => [["King"], ["Martin", "Luther"]]
        while segments.count > 1, segments.last!.allSatisfy({ matches($0, suffixPattern) }) {
            segments.removeLast()
        }

        // A remaining comma indicates inverted "Lastname, Firstname" order: [["King"], ["Martin", "Luther"]] => ["Martin", "Luther"]
        var givenWords = (segments.count > 1 ? segments[1] : segments.first) ?? []

        // Skip leading salutations, also stacked ones: ["Prof.", "Dr.", "Jane", "Smith"] => ["Jane", "Smith"]
        while givenWords.count > 1, matches(givenWords[0], salutationPattern) {
            givenWords.removeFirst()
        }

        // "R. Jason Smith" goes by the middle name, but "R. J. Smith" goes by initials
        let firstName: String?
        if givenWords.count > 1, matches(givenWords[0], initialPattern), !matches(givenWords[1], initialPattern) {
            firstName = givenWords[1]
        } else {
            firstName = givenWords.first
        }

        return firstName
            ?? words(cleanedName).first
            ?? fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
