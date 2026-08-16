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

        guard let position = self.closestPosition(to: point),
              let range = self.tokenizer.rangeEnclosingPosition(position, with: .character, inDirection: .layout(.left))
        else { return false }

        let startIndex = self.offset(from: self.beginningOfDocument, to: range.start)

        return self.attributedText.attribute(.link, at: startIndex, effectiveRange: nil) != nil
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
