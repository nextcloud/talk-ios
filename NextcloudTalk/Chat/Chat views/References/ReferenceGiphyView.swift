//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import SDWebImage

@objcMembers class ReferenceGiphyView: UIView {

    /// Used until the GIF has loaded, if the reference doesn't carry any dimensions
    private static let defaultAspectRatio: CGFloat = 4.0 / 3.0

    /// Reports the GIF's aspect ratio, so the reference view can take that shape rather than stretching
    /// across the message. Called with what the reference claims, then with the GIF's real dimensions
    /// once loaded – the two don't always agree.
    var aspectRatioHandler: ((CGFloat) -> Void)?

    private var url: String?
    private var imageAspectRatioConstraint: NSLayoutConstraint?

    private lazy var imageView: SDAnimatedImageView = {
        let imageView = SDAnimatedImageView()
        // Normally nothing to fit, the reference view being in the GIF's own aspect ratio. This only
        // takes over for a GIF so wide that it runs out of width, which it letterboxes rather than crops.
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .clear
        return imageView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.commonInit()
    }

    private func commonInit() {
        // No background of its own: the surrounding reference view provides the card fill
        self.addSubview(self.imageView)
        self.imageView.translatesAutoresizingMaskIntoConstraints = false

        // Left aligned and edge to edge: the reference view clips to its own rounded corners, so the GIF
        // reads as the card itself rather than as a thumbnail inset into one.
        //
        // The aspect ratio is applied here *and* reported to the reference view, which looks redundant
        // but isn't: the card's own width constraint stops participating once the message text settles
        // its size and the bubble re-solves, at which point the card stretches. Sizing the image view
        // as well keeps the GIF correct and against the leading edge regardless.
        NSLayoutConstraint.activate([
            self.imageView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.imageView.topAnchor.constraint(equalTo: self.topAnchor),
            self.imageView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            self.imageView.widthAnchor.constraint(lessThanOrEqualTo: self.widthAnchor)
        ])

        self.applyAspectRatio(Self.defaultAspectRatio)

        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.handleTap)))
    }

    func handleTap() {
        guard let url = self.url else { return }

        NCUtils.openLinkInBrowser(link: url)
    }

    func update(for reference: [String: AnyObject], and url: String) {
        self.url = url

        // What the reference claims, so the width is roughly right before the GIF has even loaded
        self.applyAspectRatio(Self.aspectRatio(from: reference) ?? Self.defaultAspectRatio)

        guard let proxiedUrlString = reference["proxied_url"] as? String,
              let proxiedUrl = URL(string: proxiedUrlString)
        else {
            self.imageView.image = nil
            return
        }

        self.imageView.sd_setImage(with: proxiedUrl,
                                   placeholderImage: nil,
                                   options: [],
                                   context: NCAPIController.sharedInstance().giphyReferenceImageContext,
                                   progress: nil) { [weak self] image, _, _, _ in
            guard let self, let image, image.size.width > 0, image.size.height > 0 else { return }

            // The loaded GIF is the authority – the renditions the reference lists don't always match
            // it, and any difference shows up as the GIF not filling the card
            self.applyAspectRatio(image.size.width / image.size.height)
        }
    }

    private func applyAspectRatio(_ aspectRatio: CGFloat) {
        self.imageAspectRatioConstraint?.isActive = false

        // Gives way to the width available, so a panorama-like GIF is fitted instead of overflowing
        let constraint = self.imageView.widthAnchor.constraint(equalTo: self.imageView.heightAnchor, multiplier: aspectRatio)
        constraint.priority = .defaultHigh
        constraint.isActive = true

        self.imageAspectRatioConstraint = constraint

        self.aspectRatioHandler?(aspectRatio)
    }

    /// The API spreads Giphy's own gif object into the reference, so the renditions – and with them the
    /// dimensions – are there without having to load the GIF first. Only an estimate, see the caller.
    private static func aspectRatio(from reference: [String: AnyObject]) -> CGFloat? {
        guard let images = reference["images"] as? [String: Any] else { return nil }

        for renditionName in ["fixed_width", "original", "downsized"] {
            guard let rendition = images[renditionName] as? [String: Any],
                  let width = Self.dimension(from: rendition["width"]),
                  let height = Self.dimension(from: rendition["height"]),
                  width > 0, height > 0
            else { continue }

            return width / height
        }

        return nil
    }

    /// Giphy reports the dimensions as strings
    private static func dimension(from value: Any?) -> CGFloat? {
        if let string = value as? String, let number = Double(string) {
            return CGFloat(number)
        }

        return (value as? NSNumber).map { CGFloat($0.doubleValue) }
    }
}
