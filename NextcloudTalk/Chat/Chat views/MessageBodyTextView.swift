//
// SPDX-FileCopyrightText: 2020 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import SwiftUI
import CDMarkdownKit

struct MessageBodyTextViewWrapper: UIViewRepresentable {
    let attributedText: NSAttributedString

    func makeUIView(context: Context) -> MessageBodyTextView {
        let textView = MessageBodyTextView()

        // The intrinsic width of a non-scrolling text view is the whole text on a single line, don't let that drive the layout
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        return textView
    }

    func updateUIView(_ textView: MessageBodyTextView, context: Context) {
        textView.attributedText = attributedText
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView textView: MessageBodyTextView, context: Context) -> CGSize? {
        // Without a concrete width there's nothing to wrap the text at, fall back to the intrinsic size
        guard let width = proposal.width, width > 0, width < .greatestFiniteMagnitude else { return nil }

        // Since textContainerInset and lineFragmentPadding are zero, the used rect is the full height we need
        textView.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        textView.layoutManager.ensureLayout(for: textView.textContainer)

        let usedRect = textView.layoutManager.usedRect(for: textView.textContainer)

        return CGSize(width: width, height: ceil(usedRect.height))
    }
}

class MessageBodyTextView: UITextView, UITextViewDelegate {

    init() {
        let textStorage = NSTextStorage()

        let layoutManager = SwiftMarkdownObjCBridge.getLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer()
        layoutManager.addTextContainer(textContainer)

        super.init(frame: .zero, textContainer: textContainer)

        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func commonInit() {
        self.dataDetectorTypes = .all
        self.textContainer.lineFragmentPadding = 0
        self.textContainerInset = .zero
        self.translatesAutoresizingMaskIntoConstraints = false

        // Set background color to clear to allow cell selection color to be visible
        self.backgroundColor = .clear
        self.isEditable = false
        self.isScrollEnabled = false
        self.delegate = self

        let codeBlockGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleCodeBlockTap(_:)))

        // Don't swallow the touch, links and the message context menu need to see it as well
        codeBlockGestureRecognizer.cancelsTouchesInView = false
        self.addGestureRecognizer(codeBlockGestureRecognizer)
    }

    override func awakeFromNib() {
        // Note: Init from storyboard my still be TextKit2, since there's no custom layout manager
        super.awakeFromNib()
        commonInit()
    }

    override var intrinsicContentSize: CGSize {
        let superSize = super.intrinsicContentSize

        // When a paragraphStyle with firstLineHeadIndent/headIndent is used, the
        // intrinsicContentSize might not be accurate and the last word/character is wrapped,
        // due to the size being too small. In that case usedRectForTextContainer reports
        // a non-zero x value, we add to the width of the intrinsicContentSize
        if superSize.width < CGFloat(UInt16.max) {
            let usedRect = self.layoutManager.usedRect(for: self.textContainer)

            if usedRect.origin.x > 0 {
                return CGSize(width: superSize.width + usedRect.origin.x, height: superSize.height)
            }
        }

        return superSize
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return false
    }

    // https://stackoverflow.com/a/44878203
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // In case scrolling is enabled, we need to allow touch recognition, as we can't scroll otherwise
        if self.isScrollEnabled {
            return true
        }

        guard let attributedText = self.attributedText, let startIndex = self.characterIndex(at: point), startIndex < attributedText.length
        else { return false }

        if attributedText.attribute(.link, at: startIndex, effectiveRange: nil) != nil {
            return true
        }

        // Code blocks need to receive touches as well, to be able to open them in a scrollable view
        return self.codeBlockRange(at: point) != nil
    }

    // MARK: - Code blocks

    private func characterIndex(at point: CGPoint) -> Int? {
        guard let position = self.closestPosition(to: point),
              let range = self.tokenizer.rangeEnclosingPosition(position, with: .character, inDirection: .layout(.left))
        else { return nil }

        return self.offset(from: self.beginningOfDocument, to: range.start)
    }

    private func codeBlockRange(at point: CGPoint) -> NSRange? {
        guard let attributedText = self.attributedText, let index = self.characterIndex(at: point), index < attributedText.length
        else { return nil }

        var effectiveRange = NSRange()

        // Inline code is styled like a code block, only the attribute set by the parser tells them apart
        guard attributedText.attribute(.syntaxBlock, at: index, effectiveRange: &effectiveRange) != nil else { return nil }

        return effectiveRange
    }

    @objc private func handleCodeBlockTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let point = gestureRecognizer.location(in: self)

        guard let attributedText = self.attributedText, let index = self.characterIndex(at: point), index < attributedText.length,
              // A detected link inside a code block is handled by the text view itself
              attributedText.attribute(.link, at: index, effectiveRange: nil) == nil,
              let range = self.codeBlockRange(at: point)
        else { return }

        // The block keeps the newline before the closing fence, but leading spaces are part of the code
        let code = attributedText.attributedSubstring(from: range).string.trimmingCharacters(in: .newlines)

        guard !code.isEmpty else { return }

        let codeViewController = GithubPermalinkViewController(codeBlock: code)
        let navigationController = UINavigationController(rootViewController: codeViewController)

        NCUserInterfaceController.sharedInstance().mainViewController.present(navigationController, animated: true)
    }

    // MARK: - UITextView delegate

    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        if NCUtils.isInstanceRoomLink(link: URL.absoluteString) {
            NCRoomsManager.shared.startChat(withRoomToken: URL.lastPathComponent)
            return false
        }

        return true
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        if !NSEqualRanges(textView.selectedRange, NSRange(location: 0, length: 0)) {
            textView.selectedRange = NSRange(location: 0, length: 0)
        }
    }
}
