//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

/// One media file of a group, shown as a square preview.
class GroupedFilePreviewTileView: UIControl {

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

    func setup(with file: NCMessageFileParameter, account: TalkAccount, size: CGFloat, hiddenCount: Int) {
        for constraint in self.sizeConstraints {
            constraint.constant = size
        }

        for constraint in self.playIconConstraints {
            constraint.constant = size / 2
        }

        let previewSize = Int(size * UIScreen.main.scale)

        self.previewImageView.setPreview(forFileId: file.parameterId, withWidth: previewSize, withHeight: previewSize, usingAccount: account)

        if let mimetype = file.mimetype, NCUtils.isVideo(fileType: mimetype) {
            self.playIconImageView.isHidden = false
        }

        if hiddenCount > 0 {
            self.overflowLabel.isHidden = false
            self.overflowLabel.text = "+\(hiddenCount)"
        }

        self.accessibilityLabel = file.name
        self.isAccessibilityElement = true
    }

    func prepareForReuse() {
        self.previewImageView.currentRequest?.cancel()
        self.previewImageView.image = nil
        self.playIconImageView.isHidden = true
        self.overflowLabel.isHidden = true
        self.overflowLabel.text = nil
    }
}
