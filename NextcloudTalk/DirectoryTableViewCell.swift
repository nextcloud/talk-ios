//
// Copyright (c) 2024 Marcel Müller <marcel.mueller@nextcloud.com>
//
// Author Ivan Sein <ivan@nextcloud.com>
// Author Marcel Müller <marcel.mueller@nextcloud.com>
//
// GNU GPL version 3 or any later version
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation

@objcMembers public class DirectoryTableViewCell: UITableViewCell {

    @IBOutlet weak var fileImageView: UIImageView!
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
        self.fileImageView.cancelImageDownloadTask()

        self.fileImageView.image = nil
        self.fileNameLabel.text = ""
        self.fileInfoLabel.text = ""
    }

    func didChangeIsDownloading(notification: Notification) {
        DispatchQueue.main.async {
            // Make sure this notification is really for this cell
            guard let receivedStatus = notification.userInfo?["fileStatus"] as? NCChatFileStatus,
                  let fileParameter = self.fileParameter,
                  receivedStatus.fileId == fileParameter.parameterId,
                  receivedStatus.filePath == fileParameter.path
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
            guard let receivedStatus = notification.userInfo?["fileStatus"] as? NCChatFileStatus,
                  let fileParameter = self.fileParameter,
                  receivedStatus.fileId == fileParameter.parameterId,
                  receivedStatus.filePath == fileParameter.path
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
