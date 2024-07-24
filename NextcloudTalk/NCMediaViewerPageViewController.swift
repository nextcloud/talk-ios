//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import UIKit

@objc protocol NCMediaViewerPageViewControllerDelegate {
    @objc func mediaViewerPageZoomDidChange(_ controller: NCMediaViewerPageViewController, _ scale: Double)
    @objc func mediaViewerPageImageDidLoad(_ controller: NCMediaViewerPageViewController)
}

@objcMembers class NCMediaViewerPageViewController: UIViewController, NCChatFileControllerDelegate, NCZoomableViewDelegate {

    public weak var delegate: NCMediaViewerPageViewControllerDelegate?

    public let message: NCChatMessage
    private let fileDownloader = NCChatFileController()

    private lazy var zoomableView = {
        let zoomableView = NCZoomableView()
        zoomableView.translatesAutoresizingMaskIntoConstraints = false
        zoomableView.disablePanningOnInitialZoom = true
        zoomableView.delegate = self

        return zoomableView
    }()

    private lazy var imageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.isUserInteractionEnabled = true

        return imageView
    }()

    private lazy var errorView = {
        let errorView = UIView()
        errorView.translatesAutoresizingMaskIntoConstraints = false

        let iconConfiguration = UIImage.SymbolConfiguration(pointSize: 36)

        let errorImage = UIImageView()
        errorImage.image = UIImage(systemName: "photo")?.withConfiguration(iconConfiguration)
        errorImage.contentMode = .scaleAspectFit
        errorImage.translatesAutoresizingMaskIntoConstraints = false
        errorImage.tintColor = .secondaryLabel

        let errorText = UILabel()
        errorText.translatesAutoresizingMaskIntoConstraints = false
        errorText.text = NSLocalizedString("An error occurred downloading the picture", comment: "")

        errorView.addSubview(errorImage)
        errorView.addSubview(errorText)

        NSLayoutConstraint.activate([
            errorImage.topAnchor.constraint(equalTo: errorView.topAnchor),
            errorImage.widthAnchor.constraint(equalToConstant: 150),
            errorImage.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
            errorImage.centerXAnchor.constraint(equalTo: errorView.centerXAnchor),
            errorText.topAnchor.constraint(equalTo: errorImage.bottomAnchor, constant: 10),
            errorText.bottomAnchor.constraint(equalTo: errorView.bottomAnchor),
            errorText.centerXAnchor.constraint(equalTo: errorView.centerXAnchor)
        ])

        return errorView
    }()

    public var currentImage: UIImage? {
        return self.imageView.image
    }

    private lazy var activityIndicator = {
        let indicator = NCActivityIndicator(frame: .init(x: 0, y: 0, width: 100, height: 100))
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.cycleColors = [.lightGray]

        return indicator
    }()

    init(message: NCChatMessage) {
        self.message = message

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        self.view.addSubview(self.zoomableView)
        self.view.addSubview(self.activityIndicator)

        NSLayoutConstraint.activate([
            self.zoomableView.leftAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leftAnchor),
            self.zoomableView.rightAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.rightAnchor),
            self.zoomableView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.zoomableView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            self.activityIndicator.centerXAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerXAnchor),
            self.activityIndicator.centerYAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerYAnchor)
        ])

        self.zoomableView.replaceContentView(self.imageView)
        self.activityIndicator.startAnimating()

        fileDownloader.delegate = self
        fileDownloader.downloadFile(fromMessage: self.message.file())

        self.navigationItem.title = self.message.file().name

        NotificationCenter.default.addObserver(self, selector: #selector(didChangeDownloadProgress(notification:)), name: NSNotification.Name.NCChatFileControllerDidChangeDownloadProgress, object: nil)
    }

    override func viewDidLayoutSubviews() {
        // Make sure we have the correct bounds and center the view correctly
        self.zoomableView.resizeContentView()
    }

    func showErrorView() {
        self.view.addSubview(self.errorView)

        NSLayoutConstraint.activate([
            self.errorView.leadingAnchor.constraint(greaterThanOrEqualTo: self.view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            self.errorView.trailingAnchor.constraint(greaterThanOrEqualTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            self.errorView.centerXAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerXAnchor),
            self.errorView.centerYAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerYAnchor)
        ])
    }

    // MARK: - NCChatFileController delegate

    func fileControllerDidLoadFile(_ fileController: NCChatFileController, with fileStatus: NCChatFileStatus) {
        self.activityIndicator.stopAnimating()
        self.activityIndicator.isHidden = true

        if let localPath = fileStatus.fileLocalPath, let image = UIImage(contentsOfFile: localPath) {
            self.imageView.image = image

            // Adjust the view to the new image
            self.zoomableView.contentViewSize = image.size
            self.zoomableView.resizeContentView()

            self.delegate?.mediaViewerPageImageDidLoad(self)
        } else {
            self.imageView.image = nil
            self.showErrorView()

            print("Error in fileControllerDidLoadFile getting UIImage")
        }
    }

    func fileControllerDidFailLoadingFile(_ fileController: NCChatFileController, withErrorDescription errorDescription: String) {
        self.activityIndicator.stopAnimating()
        self.activityIndicator.isHidden = true

        self.showErrorView()

        print("Error downloading picture: " + errorDescription)
    }

    func didChangeDownloadProgress(notification: Notification) {
        DispatchQueue.main.async {
            // Make sure this notification is really for this view controller
            guard let userInfo = notification.userInfo,
                  let receivedStatus = userInfo["fileStatus"] as? NCChatFileStatus,
                  let fileParameter = self.message.file(),
                  receivedStatus.fileId == fileParameter.parameterId,
                  receivedStatus.filePath == fileParameter.path
            else { return }

            // Switch to determinate mode and set the progress
            if receivedStatus.canReportProgress {
                self.activityIndicator.indicatorMode = .determinate
                self.activityIndicator.setProgress(Float(receivedStatus.downloadProgress), animated: true)
            }
        }
    }

    // MARK: - NCZoomableView delegate

    func contentViewZoomDidChange(_ view: NCZoomableView, _ scale: Double) {
        self.delegate?.mediaViewerPageZoomDidChange(self, scale)
    }
}
