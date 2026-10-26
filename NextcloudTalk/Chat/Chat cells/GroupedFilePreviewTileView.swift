//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

/// One media file of a group, shown as a square preview.
class GroupedFilePreviewTileView: UIView {

    private lazy var previewImageView: FilePreviewImageView = {
        let imageView = FilePreviewImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = chatMessageCellPreviewCornerRadius
        imageView.backgroundColor = .secondarySystemFill
        return imageView
    }()

    private lazy var playIconImageView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(paletteColors: [UIColor.white.withAlphaComponent(0.8),
                                                                       UIColor.black.withAlphaComponent(0.6)])
        let imageView = UIImageView(image: UIImage(systemName: "play.circle.fill")?.withConfiguration(configuration))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isHidden = true
        return imageView
    }()

    /// Dims the last tile to stand for the media that did not fit the row
    private lazy var overflowLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.textColor = .white
        label.font = .preferredFont(for: .title3, weight: .bold)
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.backgroundColor = .black.withAlphaComponent(0.5)
        label.layer.cornerRadius = chatMessageCellPreviewCornerRadius
        label.clipsToBounds = true
        label.isHidden = true
        return label
    }()

    // Inside the preview for its rounded corners, below the "+N" badge
    private lazy var uploadOverlayView = FileUploadOverlayView(style: .covering)

    // Above the "+N" badge, for all the files it stands for
    private lazy var badgeUploadOverlayView = FileUploadOverlayView(style: .corner)

    private var badgeMessages: [NCChatMessage] = []

    /// The files shared in the background this tile shows the upload of.
    private(set) var uploadJobIds: Set<String> = []

    private var sizeConstraints: [NSLayoutConstraint] = []
    private var playIconConstraints: [NSLayoutConstraint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setupTileView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setupTileView()
    }

    private func setupTileView() {
        self.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.previewImageView)
        self.addSubview(self.playIconImageView)
        self.addSubview(self.overflowLabel)
        self.uploadOverlayView.pin(to: self.previewImageView)
        self.badgeUploadOverlayView.pin(to: self)

        self.sizeConstraints = [
            self.widthAnchor.constraint(equalToConstant: 0),
            self.heightAnchor.constraint(equalToConstant: 0)
        ]

        self.playIconConstraints = [
            self.playIconImageView.widthAnchor.constraint(equalToConstant: 0),
            self.playIconImageView.heightAnchor.constraint(equalToConstant: 0)
        ]

        NSLayoutConstraint.activate(self.sizeConstraints + self.playIconConstraints + [

            self.previewImageView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.previewImageView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.previewImageView.topAnchor.constraint(equalTo: self.topAnchor),
            self.previewImageView.bottomAnchor.constraint(equalTo: self.bottomAnchor),

            self.playIconImageView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            self.playIconImageView.centerYAnchor.constraint(equalTo: self.centerYAnchor),

            self.overflowLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.overflowLabel.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.overflowLabel.topAnchor.constraint(equalTo: self.topAnchor),
            self.overflowLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])
    }

    /// - Parameter badgeMessages: The files a "+N" badge stands for, this one included. Empty for a tile without badge.
    func setup(with message: NCChatMessage, account: TalkAccount, size: CGFloat, badgeMessages: [NCChatMessage] = []) {
        guard let file = message.file() else { return }

        for constraint in self.sizeConstraints {
            constraint.constant = size
        }

        for constraint in self.playIconConstraints {
            constraint.constant = size / 2
        }

        let previewSize = Int(size * UIScreen.main.scale)

        let referenceId = message.referenceId ?? ""

        if let upload = message.backgroundUpload {
            self.previewImageView.setLocalPreview(forReferenceId: referenceId, fileURL: upload.fileURL, maximumPixelSize: previewSize)
        } else if !referenceId.isEmpty, FilePreviewImageView.hasLocalPreview(forReferenceId: referenceId, maximumPixelSize: previewSize) {
            // Shared from this device, so the posted file keeps the preview it had while uploading
            self.previewImageView.setLocalPreview(forReferenceId: referenceId, fileURL: nil, maximumPixelSize: previewSize)
        } else {
            self.previewImageView.setPreview(forFileId: file.parameterId, withWidth: previewSize, withHeight: previewSize, usingAccount: account)
        }

        self.badgeMessages = badgeMessages

        if badgeMessages.isEmpty {
            self.uploadJobIds = Set([message.backgroundUploadJobId].compactMap { $0 })
            self.uploadOverlayView.update(for: message)
        } else {
            self.uploadJobIds = Set(badgeMessages.compactMap { $0.backgroundUploadJobId })
            self.badgeUploadOverlayView.update(state: badgeMessages.combinedBackgroundUploadState, progress: badgeMessages.combinedBackgroundUploadProgress)

            self.overflowLabel.isHidden = false
            self.overflowLabel.text = "+\(badgeMessages.count)"
        }

        if let mimetype = file.mimetype, NCUtils.isVideo(fileType: mimetype) {
            self.playIconImageView.isHidden = false
        }

        self.accessibilityLabel = file.name
        self.accessibilityTraits = .button
        self.isAccessibilityElement = true
    }

    func updateUploadProgress(_ progress: Float) {
        if self.badgeMessages.isEmpty {
            self.uploadOverlayView.showUpload(withProgress: progress)
        } else {
            // The progress of each file is read again from the uploader
            self.badgeUploadOverlayView.update(state: self.badgeMessages.combinedBackgroundUploadState, progress: self.badgeMessages.combinedBackgroundUploadProgress)
        }
    }

    func prepareForReuse() {
        self.previewImageView.cancelPreview()
        self.previewImageView.image = nil
        self.badgeMessages = []
        self.uploadJobIds = []
        self.uploadOverlayView.hide()
        self.badgeUploadOverlayView.hide()
        self.playIconImageView.isHidden = true
        self.overflowLabel.isHidden = true
        self.overflowLabel.text = nil
    }
}
