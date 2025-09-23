//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVKit
import AVFoundation
import Foundation
import UIKit
import SwiftyGif

@objc protocol NCMediaViewerPageViewControllerDelegate {
    @objc func mediaViewerPageZoomDidChange(_ controller: NCMediaViewerPageViewController, _ scale: Double)
    @objc func mediaViewerPageMediaDidLoad(_ controller: NCMediaViewerPageViewController)
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
        errorText.numberOfLines = 0
        errorText.textAlignment = .center

        errorView.addSubview(errorImage)
        errorView.addSubview(errorText)

        NSLayoutConstraint.activate([
            errorImage.topAnchor.constraint(equalTo: errorView.topAnchor),
            errorImage.widthAnchor.constraint(equalToConstant: 150),
            errorImage.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
            errorImage.centerXAnchor.constraint(equalTo: errorView.centerXAnchor),
            errorText.topAnchor.constraint(equalTo: errorImage.bottomAnchor, constant: 10),
            errorText.bottomAnchor.constraint(equalTo: errorView.bottomAnchor),
            errorText.centerXAnchor.constraint(equalTo: errorView.centerXAnchor),
            errorText.leadingAnchor.constraint(equalTo: errorView.leadingAnchor, constant: 10),
            errorText.trailingAnchor.constraint(equalTo: errorView.trailingAnchor, constant: -10)
        ])

        return errorView
    }()

    private lazy var downscaledWarningView = {
        let warningView = UIView()
        warningView.translatesAutoresizingMaskIntoConstraints = false

        let warningImage = UIImageView()
        warningImage.image = UIImage(systemName: "exclamationmark.triangle.fill")
        warningImage.contentMode = .scaleAspectFit
        warningImage.translatesAutoresizingMaskIntoConstraints = false
        warningImage.tintColor = .systemYellow
        warningImage.setContentHuggingPriority(.required, for: .horizontal)

        let warningText = UILabel()
        warningText.translatesAutoresizingMaskIntoConstraints = false
        warningText.text = NSLocalizedString("A low resolution version is displayed", comment: "")

        warningView.addSubview(warningImage)
        warningView.addSubview(warningText)

        NSLayoutConstraint.activate([
            warningImage.leftAnchor.constraint(equalTo: warningView.leftAnchor),
            warningImage.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
            warningImage.centerYAnchor.constraint(equalTo: warningView.centerYAnchor),
            warningText.leadingAnchor.constraint(equalTo: warningImage.trailingAnchor, constant: 10),
            warningText.bottomAnchor.constraint(equalTo: warningView.bottomAnchor),
            warningText.centerYAnchor.constraint(equalTo: warningView.centerYAnchor),
            warningText.trailingAnchor.constraint(equalTo: warningView.trailingAnchor, constant: -10)
        ])

        return warningView
    }()

    public var currentImage: UIImage? {
        return self.imageView.image
    }

    public var currentVideoURL: URL?

    private var playerViewController: AVPlayerViewController?

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

        AllocationTracker.shared.addAllocation("NCMediaViewerPageViewController")
    }

    deinit {
        self.removePlayerViewControllerIfNeeded()
        AllocationTracker.shared.removeAllocation("NCMediaViewerPageViewController")
    }

    override func viewWillDisappear(_ animated: Bool) {
        self.playerViewController?.player?.pause()
    }

    override func viewDidLayoutSubviews() {
        // Make sure we have the correct bounds and center the view correctly
        self.zoomableView.resizeContentView()
    }

    func showErrorView() {
        self.imageView.image = nil
        self.removePlayerViewControllerIfNeeded()
        self.view.addSubview(self.errorView)

        NSLayoutConstraint.activate([
            self.errorView.leadingAnchor.constraint(greaterThanOrEqualTo: self.view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            self.errorView.trailingAnchor.constraint(greaterThanOrEqualTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            self.errorView.centerXAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerXAnchor),
            self.errorView.centerYAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerYAnchor)
        ])
    }

    func showWarningView() {
        self.view.addSubview(self.downscaledWarningView)

        NSLayoutConstraint.activate([
            self.downscaledWarningView.leadingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            self.downscaledWarningView.trailingAnchor.constraint(greaterThanOrEqualTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            self.downscaledWarningView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        ])
    }

    // MARK: - NCChatFileController delegate
    func fileControllerDidLoadFile(_ fileController: NCChatFileController, with fileStatus: NCChatFileStatus) {
        self.activityIndicator.stopAnimating()
        self.activityIndicator.isHidden = true

        guard let localPath = fileStatus.fileLocalPath, let mimetype = message.file()?.mimetype else {
            self.showErrorView()
            return
        }

        if NCUtils.isImage(fileType: mimetype) {
            displayImage(from: localPath)
        } else if NCUtils.isVideo(fileType: mimetype) {
            playVideo(from: localPath)
        } else {
            self.showErrorView()
        }
    }

    func fileControllerDidFailLoadingFile(_ fileController: NCChatFileController, withFileId fileId: String, withErrorDescription errorDescription: String) {
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

    private func displayImage(from localPath: String) {
        guard var image = UIImage(contentsOfFile: localPath) else {
            self.showErrorView()
            return
        }

        // Downscale images that are too large and require too much memory
        if image.size.width > 2048 ||  image.size.height > 2048 {
            let newSize = AVMakeRect(aspectRatio: image.size, insideRect: .init(x: 0, y: 0, width: 2048, height: 2048)).size
            guard let scaledImage = NCUtils.renderAspectImage(image: image, ofSize: newSize, centerImage: false)
            else {
                self.showErrorView()
                return
            }

            image = scaledImage
            self.showWarningView()
        }

        if message.file() != nil, message.isAnimatableGif,
           let data = try? Data(contentsOf: URL(fileURLWithPath: localPath)),
           let gifImage = try? UIImage(gifData: data) {

            self.imageView.setGifImage(gifImage)
        } else {
            self.imageView.image = image
        }

        // Adjust the view to the new image (use the non-gif version here for correct dimensions)
        self.zoomableView.contentViewSize = image.size
        self.zoomableView.resizeContentView()

        self.zoomableView.isHidden = false
        self.imageView.isHidden = false

        removePlayerViewControllerIfNeeded()
        self.delegate?.mediaViewerPageMediaDidLoad(self)
    }

    private func playVideo(from localPath: String) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }

        let videoURL = URL(fileURLWithPath: localPath)
        self.currentVideoURL = videoURL
        let player = AVPlayer(url: videoURL)
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        self.playerViewController = playerViewController

        self.addChild(playerViewController)
        self.view.addSubview(playerViewController.view)
        playerViewController.view.frame = self.view.bounds
        playerViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerViewController.didMove(toParent: self)

        // Automatically start video playback with sound muted
        player.isMuted = true
        player.play()

        self.zoomableView.contentViewSize = playerViewController.view.bounds.size
        self.zoomableView.resizeContentView()
        self.zoomableView.isHidden = false
        self.imageView.isHidden = true

        self.delegate?.mediaViewerPageMediaDidLoad(self)
    }

    private func removePlayerViewControllerIfNeeded() {
        if let playerVC = self.playerViewController {
            playerVC.player?.replaceCurrentItem(with: nil)
            playerVC.willMove(toParent: nil)
            playerVC.view.removeFromSuperview()
            playerVC.removeFromParent()
            self.playerViewController = nil
            self.currentVideoURL = nil
        }
    }
}
