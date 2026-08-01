//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers class ReferenceDefaultView: UIView {

    @IBOutlet var contentView: UIView!
    @IBOutlet weak var referenceThumbnailView: UIImageView!
    @IBOutlet weak var referenceName: UILabel!
    @IBOutlet weak var referenceDescription: UITextView!
    @IBOutlet weak var referenceLink: UILabel!

    /// Used until the thumbnail has loaded
    private static let defaultAspectRatio: CGFloat = 1.0

    /// Keeps room for the text, in place of the nib's minimum width on the text stack – that reserved it
    /// in a way the thumbnail could never reach its own aspect ratio within.
    private static let maximumImageWidthRatio: CGFloat = 0.45

    var url: String?

    private var thumbnailWidthConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    func commonInit() {
        Bundle.main.loadNibNamed("ReferenceDefaultView", owner: self, options: nil)
        contentView.frame = self.bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        referenceName.text = ""
        referenceDescription.text = ""
        referenceLink.text = ""

        // Remove padding from textView
        referenceDescription.textContainerInset = .zero
        referenceDescription.textContainer.lineFragmentPadding = .zero

        // Edge to edge in its own aspect ratio, as in the Giphy reference: the reference view clips to
        // its rounded corners, so the thumbnail needs neither an inset nor a corner radius of its own.
        referenceThumbnailView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            referenceThumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            referenceThumbnailView.topAnchor.constraint(equalTo: contentView.topAnchor),
            referenceThumbnailView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            referenceThumbnailView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: Self.maximumImageWidthRatio)
        ])

        setThumbnailAspectRatio(Self.defaultAspectRatio)

        let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleTap))
        contentView.addGestureRecognizer(tap)

        self.addSubview(contentView)
    }

    func handleTap() {
        if let url = url {
            NCUtils.openLinkInBrowser(link: url)
        }
    }

    func update(for reference: [String: String?]?, and url: String) {
        self.url = url

        guard let reference = reference else {
            referenceName.isHidden = true
            referenceDescription.isHidden = true
            referenceLink.text = url

            hideThumbnail()
            return
        }

        referenceName.text = reference["name"] ?? ""
        referenceDescription.text = reference["description"] ?? ""
        referenceLink.text = reference["link"] ?? ""

        if referenceDescription.text.isEmpty {
            referenceDescription.isHidden = true
        }

        if let thumbUrlString = reference["thumb"] as? String, let thumbUrl = URL(string: thumbUrlString) {
            referenceThumbnailView.sd_setImage(with: thumbUrl, placeholderImage: nil, options: [.retryFailed, .refreshCached]) { [weak self] image, error, _, _ in
                guard let self else { return }

                guard error == nil, let image, image.size.width > 0, image.size.height > 0 else {
                    self.hideThumbnail()
                    return
                }

                // Open Graph carries no dimensions, so unlike the Giphy reference the aspect ratio is
                // only known here. The height is fixed, so this widens the thumbnail, never the message.
                self.referenceThumbnailView.contentMode = .scaleAspectFill
                self.setThumbnailAspectRatio(image.size.width / image.size.height)
            }
        } else {
            hideThumbnail()
        }
    }

    /// Collapses the thumbnail rather than standing a glyph in for it, leaving the reference as text. The
    /// view stays in place, at no width: the nib pins the text to *its* trailing edge, so removing it
    /// would leave the text with nothing to hang from. The 10pt gap becomes the text's leading inset,
    /// matching the trailing side.
    func hideThumbnail() {
        referenceThumbnailView.image = nil
        setThumbnailWidth(referenceThumbnailView.widthAnchor.constraint(equalToConstant: 0))
    }

    private func setThumbnailAspectRatio(_ aspectRatio: CGFloat) {
        setThumbnailWidth(referenceThumbnailView.widthAnchor.constraint(equalTo: referenceThumbnailView.heightAnchor, multiplier: aspectRatio))
    }

    private func setThumbnailWidth(_ constraint: NSLayoutConstraint) {
        thumbnailWidthConstraint?.isActive = false

        // Below the required maximum, so a panorama-like thumbnail is cropped instead of taking over
        constraint.priority = .defaultHigh
        constraint.isActive = true

        thumbnailWidthConstraint = constraint
    }
}
