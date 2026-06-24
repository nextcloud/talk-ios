//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import SDWebImage

class GiphyGifCell: UICollectionViewCell {

    static let identifier = "GiphyGifCell"

    /// Animated rather than plain, so SDWebImage streams the GIF's frames with a bounded buffer –
    /// which a whole grid of GIFs needs a lot more than a single chat message does.
    private let imageView: SDAnimatedImageView = {
        let imageView = SDAnimatedImageView()
        // The cell has the GIF's own aspect ratio, so filling crops nothing – it only avoids
        // hairlines of the background where the item height had to be rounded to a whole point.
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .secondarySystemBackground
        imageView.layer.cornerRadius = 8.0
        return imageView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.contentView.addSubview(self.imageView)
        self.imageView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            self.imageView.topAnchor.constraint(equalTo: self.contentView.topAnchor),
            self.imageView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor),
            self.imageView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor),
            self.imageView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        self.imageView.sd_cancelCurrentImageLoad()
        self.imageView.image = nil
    }

    /// Displays a GIF, using the same context it was measured with so that it comes out of the cache.
    /// SDWebImage applies a cached GIF right away, loads an evicted one in the background, and drops
    /// a load whose cell was reused in the meantime.
    func setGif(_ gif: GiphyGif, context: [SDWebImageContextOption: Any]?) {
        self.imageView.sd_setImage(with: gif.thumbnailUrl, placeholderImage: nil, options: [], context: context)
    }
}
