//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

/// One file of a group that has no preview, shown as a row with its name.
class GroupedFileRowView: UIControl {

    static let cardPadding = 8.0

    private lazy var iconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var nameLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }()

    private lazy var detailLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        return label
    }()

    /// Shown while the file is downloading, with its progress once the download reports one
    private lazy var downloadIndicator: MDCActivityIndicator = {
        let indicator = MDCActivityIndicator(frame: .init(x: 0, y: 0, width: 20, height: 20))
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.radius = 6
        indicator.strokeWidth = 1.5
        indicator.cycleColors = [.secondaryLabel]
        indicator.isHidden = true
        return indicator
    }()

    private var fileParameter: NCMessageFileParameter?

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

    override var isHighlighted: Bool {
        didSet {
            self.alpha = self.isHighlighted ? 0.6 : 1.0
        }
    }

    private func setupRowView() {
        self.translatesAutoresizingMaskIntoConstraints = false

        self.backgroundColor = chatBubbleCardFill
        self.layer.cornerRadius = chatBubbleCardCornerRadius
        self.layer.masksToBounds = true

        self.addSubview(self.iconImageView)
        self.addSubview(self.labelStackView)
        self.addSubview(self.downloadIndicator)

        let rowHeight = GroupedFilePreviewView.fileRowHeight
        let iconSize = UIFont.preferredFont(forTextStyle: .body).lineHeight + UIFont.preferredFont(forTextStyle: .footnote).lineHeight

        let maximumWidthConstraint = self.widthAnchor.constraint(lessThanOrEqualToConstant: 0)
        self.maximumWidthConstraint = maximumWidthConstraint

        NSLayoutConstraint.activate([
            self.heightAnchor.constraint(equalToConstant: rowHeight),

            self.iconImageView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: GroupedFileRowView.cardPadding),
            self.iconImageView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.iconImageView.widthAnchor.constraint(equalToConstant: iconSize),
            self.iconImageView.heightAnchor.constraint(equalToConstant: iconSize),

            self.labelStackView.leadingAnchor.constraint(equalTo: self.iconImageView.trailingAnchor, constant: 8),
            self.labelStackView.trailingAnchor.constraint(equalTo: self.downloadIndicator.leadingAnchor, constant: -8),
            self.labelStackView.centerYAnchor.constraint(equalTo: self.centerYAnchor),

            self.downloadIndicator.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -GroupedFileRowView.cardPadding),
            self.downloadIndicator.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            self.downloadIndicator.widthAnchor.constraint(equalToConstant: 20),
            self.downloadIndicator.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    func setup(with file: NCMessageFileParameter, maximumWidth: CGFloat) {
        self.maximumWidthConstraint?.constant = maximumWidth
        self.maximumWidthConstraint?.isActive = maximumWidth > 0

        self.fileParameter = file

        if let fileStatus = file.fileStatus, fileStatus.isDownloading {
            self.showDownload(withProgress: fileStatus.canReportProgress ? Float(fileStatus.downloadProgress) : 0)
        }

        self.iconImageView.image = UIImage(named: NCUtils.previewImage(forMimeType: file.mimetype))
        self.nameLabel.text = file.name
        self.detailLabel.text = file.shortDescription

        self.accessibilityLabel = [file.name, file.shortDescription].compactMap { $0 }.joined(separator: ", ")
        self.isAccessibilityElement = true
    }

    func updateDownloadStatus(from notification: Notification) {
        guard let fileParameter = self.fileParameter,
              let status = NCChatFileStatus.getStatus(from: notification, for: fileParameter)
        else { return }

        if status.isDownloading {
            self.showDownload(withProgress: status.canReportProgress ? Float(status.downloadProgress) : 0)
        } else {
            self.hideDownload()
        }
    }

    private func showDownload(withProgress progress: Float) {
        self.downloadIndicator.isHidden = false

        if progress > 0 {
            self.downloadIndicator.indicatorMode = .determinate
            self.downloadIndicator.setProgress(progress, animated: true)
        } else {
            self.downloadIndicator.indicatorMode = .indeterminate
        }

        self.downloadIndicator.startAnimating()
    }

    private func hideDownload() {
        self.downloadIndicator.stopAnimating()
        self.downloadIndicator.isHidden = true
    }
}
