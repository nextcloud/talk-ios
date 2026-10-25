//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

#if canImport(FoundationModels)
import FoundationModels
#endif

// Short reply suggestions for the last message in a chat, generated with Apple's on-device language model.
// Messages never leave the device for this. Only available on devices with Apple Intelligence (iOS 26 and later).
enum SmartReplies {

    struct ContextMessage: Equatable {
        let author: String
        let isOwnMessage: Bool
        let text: String
    }

    static let maxContextMessages = 8
    static let maxReplyLength = 60
    static let maxReplies = 3

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            return model.isAvailable && model.supportsLocale(Locale.current)
        }
        #endif

        return false
    }

    static var isEnabled: Bool {
        return NCUserDefaults.smartRepliesEnabled() && self.isAvailable
    }

    /// Only text messages from somebody else are answered, and only when the last message is one
    static func shouldSuggestReplies(to messages: [ContextMessage]) -> Bool {
        guard let lastMessage = messages.last else { return false }

        return !lastMessage.isOwnMessage && !lastMessage.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func prompt(for messages: [ContextMessage]) -> String {
        let conversation = messages.suffix(maxContextMessages).map { message in
            let author = message.isOwnMessage ? "Me" : message.author
            let text = message.text.replacingOccurrences(of: "\n", with: " ")
            return "\(author): \(text)"
        }.joined(separator: "\n")

        return """
        Conversation:
        \(conversation)

        Suggest three different short replies that "Me" could send next.
        """
    }

    /// Removes empty, too long and duplicate suggestions
    static func cleaned(_ replies: [String]) -> [String] {
        var result = [String]()

        for reply in replies {
            var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)

            // The model sometimes quotes the replies
            if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") {
                text = String(text.dropFirst().dropLast())
            }

            guard !text.isEmpty, text.count <= maxReplyLength,
                  !result.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame })
            else { continue }

            result.append(text)
        }

        return Array(result.prefix(maxReplies))
    }

    static func suggestions(for messages: [ContextMessage]) async -> [String] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), isAvailable {
            return await SmartReplyGenerator.suggestions(for: messages)
        }
        #endif

        return []
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct SmartReplySuggestions {
    @Guide(description: "Three short, different replies, each at most eight words", .count(3))
    var replies: [String]
}

@available(iOS 26.0, *)
enum SmartReplyGenerator {

    private static let instructions = """
        You suggest replies for a chat app. The replies are sent by the user, called "Me".
        Write them in the same language as the last message.
        Keep each reply short, natural and friendly, like a person would type it on a phone.
        Never make up facts, dates or promises. An emoji is fine, but not required.
        """

    static func suggestions(for messages: [SmartReplies.ContextMessage]) async -> [String] {
        let session = LanguageModelSession(instructions: instructions)

        do {
            let response = try await session.respond(to: SmartReplies.prompt(for: messages), generating: SmartReplySuggestions.self)
            return SmartReplies.cleaned(response.content.replies)
        } catch {
            // E.g. guardrails, or the model is busy. No suggestions are better than wrong ones.
            NCLog.log("Could not generate reply suggestions: \(error.localizedDescription)")
            return []
        }
    }
}
#endif

// MARK: - View

// A row of suggestions shown above the input bar
class SuggestedRepliesView: UIView {

    var onSelect: ((String) -> Void)?
    // Called when the row appears or disappears, so the chat can make room for it
    var onVisibilityChange: ((Bool) -> Void)?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    private(set) var replies: [String] = []

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.isHidden = true
        self.alpha = 0

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.clipsToBounds = false
        addSubview(scrollView)

        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        self.accessibilityLabel = NSLocalizedString("Suggested replies", comment: "")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ replies: [String]) {
        self.replies = replies
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for reply in replies {
            var configuration = UIButton.Configuration.tinted()
            configuration.title = reply
            configuration.cornerStyle = .capsule
            configuration.baseForegroundColor = NCAppBranding.elementColor()
            configuration.baseBackgroundColor = NCAppBranding.elementColor()
            configuration.titleLineBreakMode = .byTruncatingTail
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)

            let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                HapticFeedback.selection()
                self?.onSelect?(reply)
            })

            button.accessibilityHint = NSLocalizedString("Double tap to use this reply", comment: "")
            stackView.addArrangedSubview(button)
        }

        scrollView.contentOffset = .zero

        guard self.isHidden || self.alpha < 1 else { return }

        self.isHidden = false
        self.onVisibilityChange?(true)
        UIView.animate(withDuration: 0.2) {
            self.alpha = 1
        }
    }

    func hide() {
        guard !self.replies.isEmpty || !self.isHidden else { return }

        self.replies = []
        self.onVisibilityChange?(false)

        UIView.animate(withDuration: 0.2) {
            self.alpha = 0
        } completion: { _ in
            if self.replies.isEmpty {
                self.isHidden = true
            }
        }
    }
}
