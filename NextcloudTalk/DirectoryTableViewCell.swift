//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

@objcMembers public class DirectoryTableViewCell: UITableViewCell {

    @IBOutlet weak var fileImageView: FilePreviewImageView!
    @IBOutlet weak var fileNameLabel: UILabel!
    @IBOutlet weak var fileInfoLabel: UILabel!

    public static var identifier = "DirectoryCellIdentifier"
    public static var nibName = "DirectoryTableViewCell"
    public static var cellHeight = 60.0

    public var fileParameter: NCMessageFileParameter?
    internal var activityIndicator: MDCActivityIndicator?

    public override func awakeFromNib() {
        super.awakeFromNib()

        NotificationCenter.default.addObserver(self, selector: #selector(didChangeIsDownloading(notification:)), name: NSNotification.Name.NCChatFileControllerDidChangeIsDownloading, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(didChangeDownloadProgress(notification:)), name: NSNotification.Name.NCChatFileControllerDidChangeDownloadProgress, object: nil)
    }

    public override func prepareForReuse() {
        super.prepareForReuse()

        // Fix problem of rendering downloaded image in a reused cell
        self.fileImageView.currentRequest?.cancel()

        self.fileImageView.image = nil
        self.fileNameLabel.text = ""
        self.fileInfoLabel.text = ""
        self.fileParameter = nil

        self.accessoryView = nil
        self.activityIndicator = nil
    }

    func didChangeIsDownloading(notification: Notification) {
        DispatchQueue.main.async {
            // Make sure this notification is really for this cell
            guard let fileParameter = self.fileParameter,
                  let receivedStatus = NCChatFileStatus.getStatus(from: notification, for: fileParameter)
            else { return }

            if receivedStatus.isDownloading, self.activityIndicator == nil {
                // Immediately show an indeterminate indicator as long as we don't have a progress value
                self.addActivityIndicator(with: 0)
            } else if !receivedStatus.isDownloading, self.activityIndicator != nil {
                self.accessoryView = nil
                self.activityIndicator = nil
            }
        }
    }

    func didChangeDownloadProgress(notification: Notification) {
        DispatchQueue.main.async {
            // Make sure this notification is really for this cell
            guard let fileParameter = self.fileParameter,
                  let receivedStatus = NCChatFileStatus.getStatus(from: notification, for: fileParameter)
            else { return }

            if self.activityIndicator != nil {
                // Switch to determinate-mode and show progress
                if receivedStatus.canReportProgress {
                    self.activityIndicator?.indicatorMode = .determinate
                    self.activityIndicator?.setProgress(Float(receivedStatus.downloadProgress), animated: true)
                }
            } else {
                // Make sure we have an activity indicator added to this cell
                self.addActivityIndicator(with: Float(receivedStatus.downloadProgress))
            }
        }
    }

    func addActivityIndicator(with progress: Float) {
        let indicator = MDCActivityIndicator(frame: .init(x: 0, y: 0, width: 20, height: 20))
        self.activityIndicator = indicator

        indicator.radius = 7.0
        indicator.cycleColors = [.lightGray]

        if progress > 0 {
            indicator.indicatorMode = .determinate
            indicator.setProgress(progress, animated: false)
        }

        indicator.startAnimating()
        self.accessoryView = indicator
    }

}
