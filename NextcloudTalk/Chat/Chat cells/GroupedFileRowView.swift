//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit

/// One file of a group that has no preview, shown as a row with its name.
class GroupedFileRowView: UIView {

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

    /// Replaces the indicator of a pending upload with a clock while it waits for its retry, a checkmark once uploaded
    private lazy var stateImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = .secondaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        return imageView
    }()

    private var fileParameter: NCMessageFileParameter?
    private var uploadJobId: String?

    private lazy var labelStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [self.nameLabel, self.detailLabel])
        stackView.axis = .vertical
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false
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

        self.backgroundColor = chatBubbleCardFill
        self.layer.cornerRadius = chatBubbleCardCornerRadius
        self.layer.masksToBounds = true

        self.addSubview(self.iconImageView)
        self.addSubview(self.labelStackView)
        self.addSubview(self.downloadIndicator)
        self.addSubview(self.stateImageView)

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
            self.downloadIndicator.heightAnchor.constraint(equalToConstant: 20),

            self.stateImageView.centerXAnchor.constraint(equalTo: self.downloadIndicator.centerXAnchor),
            self.stateImageView.centerYAnchor.constraint(equalTo: self.downloadIndicator.centerYAnchor),
            self.stateImageView.widthAnchor.constraint(equalToConstant: 18),
            self.stateImageView.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    func setup(with message: NCChatMessage, maximumWidth: CGFloat) {
        guard let file = message.file() else { return }

        self.maximumWidthConstraint?.constant = maximumWidth
        self.maximumWidthConstraint?.isActive = maximumWidth > 0

        self.fileParameter = file
        self.uploadJobId = message.backgroundUploadJobId

        if let uploadState = message.backgroundUploadState, uploadState != .failed {
            if let symbolName = uploadState.symbolName {
                self.showStateImage(named: symbolName)
            } else {
                self.showDownload(withProgress: message.backgroundUploadProgress)
            }
        } else if let fileStatus = file.fileStatus, fileStatus.isDownloading {
            self.showDownload(withProgress: fileStatus.canReportProgress ? Float(fileStatus.downloadProgress) : 0)
        }

        self.iconImageView.image = UIImage(named: NCUtils.previewImage(forMimeType: file.mimetype))
        self.nameLabel.text = file.name
        self.detailLabel.text = file.shortDescription

        self.accessibilityLabel = [file.name, file.shortDescription].compactMap { $0 }.joined(separator: ", ")
        self.accessibilityTraits = .button
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

    func updateUploadProgress(_ progress: Float, forJobId jobId: String) {
        guard self.uploadJobId == jobId else { return }

        self.showDownload(withProgress: progress)
    }

    private func showStateImage(named systemName: String) {
        self.hideDownload()
        self.stateImageView.image = UIImage(systemName: systemName)
        self.stateImageView.isHidden = false
    }

    private func showDownload(withProgress progress: Float) {
        self.stateImageView.isHidden = true
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
