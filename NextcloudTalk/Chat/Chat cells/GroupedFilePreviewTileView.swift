//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

extension NCMessageFileParameter {

    /// Whether the file is shown as a preview tile rather than as a row with its name.
    ///
    /// Only media the server can render a preview of: everything else would be a tile showing the
    /// same generic icon, which says less than the file name does.
    var isPreviewableMedia: Bool {
        guard let mimetype = self.mimetype, self.previewAvailable else { return false }

        return NCUtils.isImage(fileType: mimetype) || NCUtils.isVideo(fileType: mimetype)
    }

    /// The extension and the size of the file, as shown next to its name in a group.
    var shortDescription: String {
        let fileExtension = (self.name as NSString?)?.pathExtension.uppercased() ?? ""
        let size = self.size ?? 0
        let formattedSize = size > 0 ? ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) : ""

        return [fileExtension, formattedSize].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

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
        // Deliberately not a PaddedLabel: its insets leave a shrunken tile too little room, and the
        // badge truncates to an ellipsis instead of showing the count
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

/// One file of a group that has no preview, shown as a row with its name.
class GroupedFileRowView: UIControl {

    private lazy var iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }()

    private lazy var detailLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        return label
    }()

    private lazy var labelStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [self.nameLabel, self.detailLabel])
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false
        // Otherwise hit testing stops here and the row itself never sees the tap
        stackView.isUserInteractionEnabled = false
        return stackView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setupRowView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.setupRowView()
    }

    private var maximumWidthConstraint: NSLayoutConstraint?

    private func setupRowView() {
        self.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.iconImageView)
        self.addSubview(self.labelStackView)

        let rowHeight = GroupedFilePreviewView.fileRowHeight

        // A long file name truncates against this instead of widening the row past the bubble,
        // where the part sticking out would draw but take no taps
        let maximumWidthConstraint = self.widthAnchor.constraint(lessThanOrEqualToConstant: 0)
        self.maximumWidthConstraint = maximumWidthConstraint

        NSLayoutConstraint.activate([
            self.heightAnchor.constraint(equalToConstant: rowHeight),

            self.iconImageView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.iconImageView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.iconImageView.widthAnchor.constraint(equalToConstant: rowHeight * 0.7),
            self.iconImageView.heightAnchor.constraint(equalToConstant: rowHeight * 0.7),

            self.labelStackView.leadingAnchor.constraint(equalTo: self.iconImageView.trailingAnchor, constant: 8),
            self.labelStackView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.labelStackView.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
    }

    func setup(with file: NCMessageFileParameter, maximumWidth: CGFloat) {
        self.maximumWidthConstraint?.constant = maximumWidth
        self.maximumWidthConstraint?.isActive = maximumWidth > 0

        self.iconImageView.image = UIImage(named: NCUtils.previewImage(forMimeType: file.mimetype))
        self.nameLabel.text = file.name
        self.detailLabel.text = file.shortDescription

        self.accessibilityLabel = [file.name, file.shortDescription].compactMap { $0 }.joined(separator: ", ")
        self.isAccessibilityElement = true
    }
}
