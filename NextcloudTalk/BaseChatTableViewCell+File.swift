//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

extension BaseChatTableViewCell {

    func setupForFileCell(with message: NCChatMessage, with account: TalkAccount) {
        if self.filePreviewImageView == nil {
            // Preview image view
            let filePreviewImageView = FilePreviewImageView(frame: .init(x: 0, y: 0, width: fileMessageCellFileMaxPreviewHeight, height: fileMessageCellFileMaxPreviewWidth))
            self.filePreviewImageView = filePreviewImageView

            filePreviewImageView.translatesAutoresizingMaskIntoConstraints = false
            filePreviewImageView.layer.cornerRadius = chatMessageCellPreviewCornerRadius
            filePreviewImageView.layer.masksToBounds = true
            filePreviewImageView.contentMode = .scaleAspectFit

            self.messageBodyView.addSubview(filePreviewImageView)

            let previewTap = UITapGestureRecognizer(target: self, action: #selector(filePreviewTapped))
            filePreviewImageView.addGestureRecognizer(previewTap)
            filePreviewImageView.isUserInteractionEnabled = true

            // PlayIcon for video files with preview
            let filePreviewPlayIconImageView = UIImageView(frame: .init(x: 0, y: 0, width: fileMessageCellFileMaxPreviewHeight, height: fileMessageCellFileMaxPreviewWidth))
            self.filePreviewPlayIconImageView = filePreviewPlayIconImageView

            filePreviewPlayIconImageView.isHidden = true
            filePreviewPlayIconImageView.tintColor = .init(white: 1.0, alpha: 0.8)
            filePreviewPlayIconImageView.image = .init(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(weight: .black))

            filePreviewImageView.addSubview(filePreviewPlayIconImageView)
            filePreviewImageView.bringSubviewToFront(filePreviewPlayIconImageView)

            // Activity indicator while loading previews
            let filePreviewActivityIndicator = MDCActivityIndicator(frame: .init(x: 0, y: 0, width: fileMessageCellMinimumHeight, height: fileMessageCellMinimumHeight))
            self.filePreviewActivityIndicator = filePreviewActivityIndicator

            filePreviewActivityIndicator.translatesAutoresizingMaskIntoConstraints = false
            filePreviewActivityIndicator.radius = fileMessageCellMinimumHeight / 2
            filePreviewActivityIndicator.cycleColors = [.systemGray2]
            filePreviewActivityIndicator.indicatorMode = .indeterminate

            filePreviewImageView.addSubview(filePreviewActivityIndicator)

            NSLayoutConstraint.activate([
                filePreviewActivityIndicator.centerYAnchor.constraint(equalTo: filePreviewImageView.centerYAnchor),
                filePreviewActivityIndicator.centerXAnchor.constraint(equalTo: filePreviewImageView.centerXAnchor)
            ])

            // Add everything to messageBodyView
            let heightConstraint = filePreviewImageView.heightAnchor.constraint(equalToConstant: fileMessageCellFileMaxPreviewHeight)
            let widthConstraint = filePreviewImageView.widthAnchor.constraint(equalToConstant: fileMessageCellFileMaxPreviewWidth)

            self.filePreviewImageViewHeightConstraint = heightConstraint
            self.filePreviewImageViewWidthConstraint = widthConstraint

            let messageTextView = MessageBodyTextView()
            self.messageTextView = messageTextView

            messageTextView.translatesAutoresizingMaskIntoConstraints = false

            self.messageBodyView.addSubview(messageTextView)

            NSLayoutConstraint.activate([
                filePreviewImageView.leftAnchor.constraint(equalTo: self.messageBodyView.leftAnchor),
                filePreviewImageView.topAnchor.constraint(equalTo: self.messageBodyView.topAnchor),
                heightConstraint,
                widthConstraint,
                messageTextView.leftAnchor.constraint(equalTo: self.messageBodyView.leftAnchor),
                messageTextView.rightAnchor.constraint(equalTo: self.messageBodyView.rightAnchor),
                messageTextView.topAnchor.constraint(equalTo: filePreviewImageView.bottomAnchor, constant: 10),
                messageTextView.bottomAnchor.constraint(equalTo: self.messageBodyView.bottomAnchor)
            ])

            NotificationCenter.default.addObserver(self, selector: #selector(didChangeIsDownloading(notification:)), name: NSNotification.Name.NCChatFileControllerDidChangeIsDownloading, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(didChangeDownloadProgress(notification:)), name: NSNotification.Name.NCChatFileControllerDidChangeDownloadProgress, object: nil)
        }

        guard let filePreviewImageView = self.filePreviewImageView,
              let messageTextView = self.messageTextView
        else { return }

        messageTextView.attributedText = message.parsedMarkdownForChat()

        if message.message == "{file}" {
            messageTextView.dataDetectorTypes = []
        } else {
            messageTextView.dataDetectorTypes = .all
        }

        self.requestPreview(for: message, with: account)

        if !message.sendingFailed {
            if message.isTemporary {
                self.addActivityIndicator(with: 0)
            } else if let fileStatus = message.file().fileStatus {
                if fileStatus.isDownloading, fileStatus.downloadProgress < 1 {
                    self.addActivityIndicator(with: Float(fileStatus.downloadProgress))
                }
            }
        }

        if let contactImage = message.file().contactPhotoImage() {
            filePreviewImageView.image = contactImage
        }
    }

    func prepareForReuseFileCell() {
        self.filePreviewImageView?.cancelImageDownloadTask()
        self.filePreviewImageView?.layer.borderWidth = 0
        self.filePreviewImageView?.image = nil
        self.filePreviewPlayIconImageView?.isHidden = true

        self.clearFileStatusView()
    }

    // MARK: - Preview

    func requestPreview(for message: NCChatMessage, with account: TalkAccount) {
        // Don't request a preview if we know that there's none
        guard let file = message.file(), file.previewAvailable else {
            self.showFallbackIcon(for: message)

            return
        }

        // In case we can determine the height before requesting the preview, adjust the imageView constraints accordingly
        if file.previewImageHeight > 0 {
            self.filePreviewImageViewHeightConstraint?.constant = CGFloat(file.previewImageHeight)
        } else {
            let estimatedPreviewHeight = BaseChatTableViewCell.getEstimatedPreviewSize(for: message)

            if estimatedPreviewHeight > 0 {
                self.filePreviewImageViewHeightConstraint?.constant = estimatedPreviewHeight
            }
        }

        self.filePreviewActivityIndicator?.isHidden = false
        self.filePreviewActivityIndicator?.startAnimating()

        if message.isAnimatableGif {
            self.requestGifPreview(for: message, with: account)
        } else {
            self.requestDefaultPreview(for: message, with: account)
        }
    }

    func requestGifPreview(for message: NCChatMessage, with account: TalkAccount) {
        guard let fileId = message.file()?.parameterId else { return }

        let fileControllerWrapper = NCChatFileControllerWrapper()
        self.fileControllerWrapper = fileControllerWrapper

        fileControllerWrapper.downloadFile(withFileId: fileId) { fileLocalPath in
            // Check if we are still on the same cell
            guard let cellMessage = self.message, let imageView = self.filePreviewImageView, cellMessage.file().parameterId == fileId
            else {
                // Different cell, don't do anything
                return
            }

            guard let fileLocalPath, let data = try? Data(contentsOf: URL(fileURLWithPath: fileLocalPath)),
                  let gifImage = try? UIImage(gifData: data), let baseImage = UIImage(data: data) else {

                // No gif, try to request a normal preview
                self.requestDefaultPreview(for: message, with: account)
                return
            }

            imageView.setGifImage(gifImage)
            self.adjustImageView(toImageSize: baseImage, ofMessage: message)
        }
    }

    func requestDefaultPreview(for message: NCChatMessage, with account: TalkAccount) {
        guard let file = message.file() else { return }

        let requestedHeight = Int(3 * fileMessageCellFileMaxPreviewHeight)
        guard let previewRequest = NCAPIController.sharedInstance().createPreviewRequest(forFile: file.parameterId, withMaxHeight: requestedHeight, using: account) else { return }

        self.filePreviewImageView?.setImageWith(previewRequest, placeholderImage: nil, success: {  [weak self] _, _, image in
            guard let self, let imageView = self.filePreviewImageView else { return }

            imageView.image = image
            self.adjustImageView(toImageSize: image, ofMessage: message)
        }, failure: { _, _, _ in
            self.showFallbackIcon(for: message)
        })
    }

    func adjustImageView(toImageSize image: UIImage, ofMessage message: NCChatMessage) {
        guard let imageView = self.filePreviewImageView, let file = message.file() else { return }

        let isVideoFile = NCUtils.isVideo(fileType: file.mimetype)
        let isMediaFile = isVideoFile || NCUtils.isImage(fileType: file.mimetype)

        self.filePreviewActivityIndicator?.isHidden = true
        self.filePreviewActivityIndicator?.stopAnimating()

        let imageSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let previewSize = BaseChatTableViewCell.getPreviewSize(from: imageSize, isMediaFile)

        if !previewSize.width.isFinite || !previewSize.height.isFinite {
            self.showFallbackIcon(for: message)
            return
        }

        imageView.layer.borderColor = UIColor.secondarySystemFill.cgColor
        imageView.layer.borderWidth = 1

        self.filePreviewImageViewHeightConstraint?.constant = previewSize.height
        self.filePreviewImageViewWidthConstraint?.constant = previewSize.width

        if isVideoFile {
            // only show the play icon if there is an image preview (not on top of the default video placeholder)
            self.filePreviewPlayIconImageView?.isHidden = false
            // if the video preview is very narrow, make the play icon fit inside
            self.filePreviewPlayIconImageView?.frame = CGRect(x: 0, y: 0, width: min(min(previewSize.height, previewSize.width), fileMessageCellVideoPlayIconSize), height: min(min(previewSize.height, previewSize.width), fileMessageCellVideoPlayIconSize))
            self.filePreviewPlayIconImageView?.center = CGPoint(x: previewSize.width / 2.0, y: previewSize.height / 2.0)
        }

        self.delegate?.cellHasDownloadedImagePreview(withHeight: ceil(previewSize.height), for: message)
    }

    func showFallbackIcon(for message: NCChatMessage) {
        let imageName = NCUtils.previewImage(forMimeType: message.file().mimetype)

        if let image = UIImage(named: imageName) {
            let size = CGSize(width: fileMessageCellFileMaxPreviewWidth, height: fileMessageCellFileMaxPreviewHeight)

            if let renderedImage = NCUtils.renderAspectImage(image: image, ofSize: size, centerImage: false) {
                self.filePreviewImageView?.image = renderedImage

                self.filePreviewImageViewHeightConstraint?.constant = renderedImage.size.height
                self.filePreviewImageViewWidthConstraint?.constant = renderedImage.size.width
            }
        }

        self.filePreviewActivityIndicator?.isHidden = true
        self.filePreviewActivityIndicator?.stopAnimating()
    }

    @objc
    func filePreviewTapped() {
        guard let message = self.message,
              let fileParameter = message.file(),
              fileParameter.path != nil, fileParameter.link != nil
        else { return }

        self.delegate?.cellWants(toDownloadFile: fileParameter, for: message)
    }

    // MARK: - Preview height calculation

    static func getPreviewSize(from imageSize: CGSize, _ isMediaFile: Bool) -> CGSize {
        var width = imageSize.width
        var height = imageSize.height

        let previewMaxHeight = isMediaFile ? fileMessageCellMediaFilePreviewHeight : fileMessageCellFileMaxPreviewHeight
        let previewMaxWidth = isMediaFile ? fileMessageCellMediaFileMaxPreviewWidth : fileMessageCellFileMaxPreviewWidth

        if height < fileMessageCellMinimumHeight {
            let ratio = fileMessageCellMinimumHeight / height
            width *= ratio

            if width > previewMaxWidth {
                width = previewMaxWidth
            }

            height = fileMessageCellMinimumHeight
        } else {
            if height > previewMaxHeight {
                let ratio = previewMaxHeight / height
                width *= ratio
                height = previewMaxHeight
            }

            if width > previewMaxWidth {
                let ratio = previewMaxWidth / width
                width = previewMaxWidth
                height *= ratio
            }
        }

        return CGSize(width: width, height: height)
    }

    static func getEstimatedPreviewSize(for message: NCChatMessage?) -> CGFloat {
        guard let message, let fileParameter = message.file() else { return 0 }

        // We don't have any information about the image to display
        if fileParameter.width == 0 && fileParameter.height == 0 {
            return 0
        }

        // We can only estimate the height for images and videos
        if !NCUtils.isVideo(fileType: fileParameter.mimetype), !NCUtils.isImage(fileType: fileParameter.mimetype) {
            return 0
        }

        let imageSize = CGSize(width: CGFloat(fileParameter.width), height: CGFloat(fileParameter.height))
        let previewSize = self.getPreviewSize(from: imageSize, true)

        return ceil(previewSize.height)
    }

    // MARK: - File status / activity indicator

    func clearFileStatusView() {
            self.fileActivityIndicator?.stopAnimating()
            self.fileActivityIndicator?.removeFromSuperview()
            self.fileActivityIndicator = nil
    }

    func addActivityIndicator(with progress: Float) {
        self.clearFileStatusView()

        let fileActivityIndicator = MDCActivityIndicator(frame: .init(x: 0, y: 0, width: 20, height: 20))
        self.fileActivityIndicator = fileActivityIndicator

        fileActivityIndicator.radius = 7
        fileActivityIndicator.cycleColors = [.systemGray2]

        if progress > 0 {
            fileActivityIndicator.indicatorMode = .determinate
            fileActivityIndicator.setProgress(progress, animated: false)
        }

        fileActivityIndicator.startAnimating()
        fileActivityIndicator.heightAnchor.constraint(equalToConstant: 20).isActive = true
        self.statusView.addArrangedSubview(fileActivityIndicator)
    }

    // MARK: - File notifications

    @objc func didChangeIsDownloading(notification: Notification) {
        DispatchQueue.main.async {
            // Make sure this notification is really for this cell
            guard let fileParameter = self.message?.file(),
                  let receivedStatus = NCChatFileStatus.getStatus(from: notification, for: fileParameter)
            else { return }

            if receivedStatus.isDownloading, self.fileActivityIndicator == nil {
                // Immediately show an indeterminate indicator as long as we don't have a progress value
                self.addActivityIndicator(with: 0)
            } else if !receivedStatus.isDownloading, self.fileActivityIndicator != nil {
                self.clearFileStatusView()
            }
        }
    }

    @objc func didChangeDownloadProgress(notification: Notification) {
        DispatchQueue.main.async {
            // Make sure this notification is really for this cell
            guard let fileParameter = self.message?.file(),
                  let receivedStatus = NCChatFileStatus.getStatus(from: notification, for: fileParameter)
            else { return }

            if self.fileActivityIndicator != nil {
                // Switch to determinate-mode and show progress
                if receivedStatus.canReportProgress {
                    self.fileActivityIndicator?.indicatorMode = .determinate
                    self.fileActivityIndicator?.setProgress(Float(receivedStatus.downloadProgress), animated: true)
                }
            } else {
                // Make sure we have an activity indicator added to this cell
                self.addActivityIndicator(with: Float(receivedStatus.downloadProgress))
            }
        }
    }
}
