//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

class PollMessageView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var pollImageLabel: UILabel!
    @IBOutlet weak var pollTitleTextView: UITextView!

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    func commonInit() {
        Bundle.main.loadNibNamed("PollMessageView", owner: self, options: nil)
        contentView.frame = self.bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.addSubview(contentView)

        // Poll image
        pollImageLabel.attributedText = pollImageAttributedString()

        // Poll title
        configureTitleTextView(with: pollTitleTextView)
    }

    func pollImageAttributedString() -> NSAttributedString {
        guard let pollImage = UIImage(systemName: "chart.bar") else {
            return NSAttributedString()
        }

        return NSAttributedString(attachment: NSTextAttachment(image: pollImage))
            .withFont(.preferredFont(for: .body, weight: .medium))
            .withTextColor(.label)
    }

    func configureTitleTextView(with textView: UITextView) {
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.font = .preferredFont(for: .body, weight: .medium)
    }

    func pollMessageBodyHeight(with title: String, width: CGFloat) -> CGFloat {
        let pollImageWidth = pollImageAttributedString().boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).width
        let titleTextViewMaxWidth = ceil(width - (pollImageWidth + 30)) // 3 * padding (10)

        let titleTextView = UITextView(frame: .zero)
        configureTitleTextView(with: titleTextView)
        titleTextView.text = title

        let titleTextViewHeight = ceil(titleTextView.sizeThatFits(CGSize(width: titleTextViewMaxWidth, height: CGFloat.greatestFiniteMagnitude)).height)

        return titleTextViewHeight + 20 // 2 * padding (10)
    }
}
