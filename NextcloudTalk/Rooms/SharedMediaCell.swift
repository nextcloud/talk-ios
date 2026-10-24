//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import SDWebImage

class SharedMediaCell: UICollectionViewCell {

    static let identifier = "SharedMediaCell"

    /// Decoding a blurhash generates a bitmap synchronously on the main thread, once per file is enough
    private static let blurhashPlaceholderCache = NSCache<NSString, UIImage>()

    private var fileId: String?
    private var previewRequest: SDWebImageCombinedOperation?
    private var isVideo = false

    private lazy var downloadObserver = ChatFileDownloadObserver { [weak self] change in
        self?.downloadDidChange(change)
    }

    private let downloadIndicator: MediaDownloadIndicatorView = {
        let downloadIndicator = MediaDownloadIndicatorView(frame: .zero)
        downloadIndicator.isHidden = true
        return downloadIndicator
    }()

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        return imageView
    }()

    private let fileIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        return imageView
    }()

    private let playIconView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(paletteColors: [UIColor.white.withAlphaComponent(0.8), UIColor.black.withAlphaComponent(0.6)])
        let imageView = UIImageView(image: UIImage(systemName: "play.circle.fill")?.withConfiguration(configuration))
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        return imageView
    }()

    private let captionView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        return view
    }()

    private let actorLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(for: .caption1, weight: .semibold)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.contentView.backgroundColor = .secondarySystemGroupedBackground
        self.contentView.layer.cornerRadius = 8.0
        self.contentView.clipsToBounds = true
        self.updateBorder()

        self.isAccessibilityElement = true
        self.accessibilityTraits = .button

        self.contentView.addSubview(self.imageView)
        self.contentView.addSubview(self.fileIconView)
        self.contentView.addSubview(self.playIconView)
        self.contentView.addSubview(self.captionView)
        self.contentView.addSubview(self.downloadIndicator)
        self.captionView.addSubview(self.actorLabel)

        for view in [self.imageView, self.fileIconView, self.playIconView, self.captionView, self.actorLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            self.imageView.topAnchor.constraint(equalTo: self.contentView.topAnchor),
            self.imageView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor),
            self.imageView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor),
            self.imageView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor),

            self.fileIconView.centerXAnchor.constraint(equalTo: self.contentView.centerXAnchor),
            self.fileIconView.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor),
            self.fileIconView.widthAnchor.constraint(equalToConstant: 48),
            self.fileIconView.heightAnchor.constraint(equalToConstant: 48),

            self.playIconView.centerXAnchor.constraint(equalTo: self.contentView.centerXAnchor),
            self.playIconView.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor),
            self.playIconView.widthAnchor.constraint(equalToConstant: 44),
            self.playIconView.heightAnchor.constraint(equalToConstant: 44),

            self.downloadIndicator.centerXAnchor.constraint(equalTo: self.contentView.centerXAnchor),
            self.downloadIndicator.centerYAnchor.constraint(equalTo: self.contentView.centerYAnchor),

            self.captionView.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor),
            self.captionView.trailingAnchor.constraint(equalTo: self.contentView.trailingAnchor),
            self.captionView.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor),

            self.actorLabel.topAnchor.constraint(equalTo: self.captionView.topAnchor, constant: 4),
            self.actorLabel.bottomAnchor.constraint(equalTo: self.captionView.bottomAnchor, constant: -4),
            self.actorLabel.leadingAnchor.constraint(equalTo: self.captionView.leadingAnchor, constant: 8),
            self.actorLabel.trailingAnchor.constraint(equalTo: self.captionView.trailingAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) ||
            self.traitCollection.displayScale != previousTraitCollection?.displayScale {
            self.updateBorder()
        }
    }

    private func updateBorder() {
        // A CGColor doesn't follow dark mode by itself
        self.contentView.layer.borderColor = UIColor.label.withAlphaComponent(0.18).resolvedColor(with: self.traitCollection).cgColor
        self.contentView.layer.borderWidth = 1 / max(self.traitCollection.displayScale, 1)
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        self.previewRequest?.cancel()
        self.previewRequest = nil
        self.fileId = nil
        self.imageView.image = nil
        self.fileIconView.isHidden = true
        self.downloadObserver.fileParameter = nil
        self.showsDownload(false)
    }

    func configure(with message: NCChatMessage, aspectRatio: CGFloat, showsServerPreview: Bool, account: TalkAccount) {
        let file = message.file()
        let actorDisplayName = message.actorDisplayName ?? ""

        self.fileId = file?.parameterId
        self.actorLabel.text = actorDisplayName
        self.captionView.isHidden = actorDisplayName.isEmpty
        self.isVideo = NCUtils.isVideo(fileType: file?.mimetype ?? "")
        self.downloadObserver.fileParameter = file
        // A download started before this cell showed the file only reports its next change
        self.showsDownload(file.flatMap { ChatFileDownloader.shared.downloadStatus(forFileId: $0.parameterId)?.isDownloading } ?? false)
        self.accessibilityLabel = [file?.name ?? "", actorDisplayName].filter { !$0.isEmpty }.joined(separator: ", ")

        guard let file, file.previewAvailable else {
            self.showFileIcon(for: file)
            return
        }

        self.imageView.image = Self.blurhashPlaceholder(for: file, aspectRatio: aspectRatio)

        guard showsServerPreview else {
            if self.imageView.image == nil {
                self.showFileIcon(for: file)
            }

            return
        }

        // Same as the chat cells, so the media viewer finds it cached, the server rounds it up to 1024 px anyway
        let previewHeight = Int(3 * fileMessageCellFileMaxPreviewHeight)
        let fileId = file.parameterId

        self.previewRequest = NCAPIController.sharedInstance().getPreviewForFile(fileId, width: -1, height: previewHeight, forAccount: account) { [weak self] image, _ in
            guard let self, self.fileId == fileId else { return }

            if let image {
                self.imageView.image = image
            } else {
                self.showFileIcon(for: file)
            }
        }
    }

    private func downloadDidChange(_ change: ChatFileDownloadObserver.Change) {
        switch change {
        case .isDownloading(let isDownloading):
            self.showsDownload(isDownloading)
        case .progress(let progress):
            self.showsDownload(true)

            if let progress {
                self.downloadIndicator.setProgress(progress)
            }
        }
    }

    private func showsDownload(_ showsDownload: Bool) {
        if showsDownload, self.downloadIndicator.isHidden {
            self.downloadIndicator.showProgress()
        } else if !showsDownload {
            self.downloadIndicator.stopAnimating()
        }

        self.downloadIndicator.isHidden = !showsDownload
        self.playIconView.isHidden = showsDownload || !self.isVideo
    }

    private func showFileIcon(for file: NCMessageFileParameter?) {
        self.imageView.image = nil
        self.fileIconView.image = UIImage(named: NCUtils.previewImage(forMimeType: file?.mimetype))
        self.fileIconView.isHidden = false
    }

    private static func blurhashPlaceholder(for file: NCMessageFileParameter, aspectRatio: CGFloat) -> UIImage? {
        guard let blurhash = file.blurhash, aspectRatio > 0 else { return nil }

        let placeholderSize = CGSize(width: 20, height: (20 / aspectRatio).rounded())
        let cacheKey = "\(blurhash)-\(Int(placeholderSize.height))" as NSString

        if let cached = self.blurhashPlaceholderCache.object(forKey: cacheKey) {
            return cached
        }

        guard let decoded = UIImage(blurHash: blurhash, size: placeholderSize) else { return nil }

        self.blurhashPlaceholderCache.setObject(decoded, forKey: cacheKey)

        return decoded
    }
}

class SharedMediaSectionHeaderView: UICollectionReusableView {

    static let identifier = "SharedMediaSectionHeaderView"

    // Same style as the date headers in the chat
    private static var titleFont: UIFont {
        return UIFont.preferredFont(forTextStyle: .footnote)
    }

    /// Follows the text size, as the layout needs it before any header exists
    static var height: CGFloat {
        return (self.titleFont.lineHeight + PaddedLabel.textInsets.top + PaddedLabel.textInsets.bottom + 16).rounded(.up)
    }

    private let titleLabel: PaddedLabel = {
        let label = PaddedLabel()
        label.textColor = .secondaryLabel
        label.accessibilityTraits = .header
        return label
    }()

    private let titleBackgroundView: UIView = {
        let view = UIView()
        view.clipsToBounds = true
        return view
    }()

    private var titleGlassView: UIVisualEffectView?

    override init(frame: CGRect) {
        super.init(frame: frame)

        if #available(iOS 26.0, *) {
            self.titleGlassView = self.titleBackgroundView.addGlassView()
            self.titleGlassView?.layer.masksToBounds = true
        } else {
            self.titleBackgroundView.backgroundColor = .secondarySystemGroupedBackground
        }

        self.addSubview(self.titleBackgroundView)
        self.addSubview(self.titleLabel)
        self.titleBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            self.titleLabel.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.titleLabel.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: self.leadingAnchor),
            self.titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: self.trailingAnchor),

            self.titleBackgroundView.topAnchor.constraint(equalTo: self.titleLabel.topAnchor),
            self.titleBackgroundView.bottomAnchor.constraint(equalTo: self.titleLabel.bottomAnchor),
            self.titleBackgroundView.leadingAnchor.constraint(equalTo: self.titleLabel.leadingAnchor),
            self.titleBackgroundView.trailingAnchor.constraint(equalTo: self.titleLabel.trailingAnchor)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // The height follows the text size. Glass draws its own edges, so clipping it is not enough
        let cornerRadius = self.titleBackgroundView.bounds.height / 2

        self.titleBackgroundView.layer.cornerRadius = cornerRadius
        self.titleGlassView?.layer.cornerRadius = cornerRadius
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setTitle(_ title: String) {
        self.titleLabel.font = Self.titleFont
        self.titleLabel.text = title
    }
}
