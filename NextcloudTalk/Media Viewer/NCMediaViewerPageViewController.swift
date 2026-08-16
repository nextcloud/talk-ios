//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVKit
import AVFoundation
import Foundation
import SDWebImage
import UIKit
import SwiftyGif

@objc protocol NCMediaViewerPageViewControllerDelegate {
    @objc func mediaViewerPageZoomDidChange(_ controller: NCMediaViewerPageViewController, _ scale: Double)
    @objc func mediaViewerPageStateDidChange(_ controller: NCMediaViewerPageViewController)
}

@objcMembers class NCMediaViewerPageViewController: UIViewController, NCChatFileControllerDelegate, NCZoomableViewDelegate {

    // What the user is looking at. Never goes back to a lower quality state on its own.
    private enum MediaState {
        case idle
        case placeholder
        case preview
        case full
        case failed
    }

    public weak var delegate: NCMediaViewerPageViewControllerDelegate?

    public let message: NCChatMessage
    private let account: TalkAccount
    private let fileDownloader: NCChatFileController

    // How long the preview stays up before we go for the original file. Keeps a fast swipe through
    // many pictures from starting a download for every single one of them.
    private let downloadDelay: TimeInterval = 1
    private let indicatorRevealDelay: TimeInterval = 0.4

    // We decode enough pixels to stay sharp up to this zoom. Zooming further is not prevented,
    // the image just gets soft, same as it did with the previous fixed limit.
    private let sharpUpToZoomScale: CGFloat = 3

    private var state: MediaState = .idle
    private var expectsPreview = false
    private var isCurrentPage = false
    private var isDownloading = false
    private var downloadDidFail = false
    private var displayedFileIsValidated = false
    private var displayedFileFingerprint: String?
    private var lastLaidOutBounds: CGRect?
    private var previewRequest: SDWebImageCombinedOperation?
    private var pendingDownload: DispatchWorkItem?
    private var pendingIndicatorReveal: DispatchWorkItem?

    // The original file on disk, set once it is available
    public private(set) var sharableFileURL: URL?

    // What is on screen right now, preview or original. Used as the share sheet's thumbnail.
    public private(set) var displayedImage: UIImage?

    private var sharableFileHandlers: [(URL?) -> Void] = []

    // Where the original file ends up, known before it is downloaded. Lets the share sheet build
    // its activity list while the download is still running.
    public var expectedFileURL: URL? {
        guard let path = self.message.file()?.path else { return nil }

        let fileName = (path as NSString).lastPathComponent

        return URL(fileURLWithPath: (self.fileDownloader.tempDirectoryPath as NSString).appendingPathComponent(fileName))
    }

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

    private var playerViewController: AVPlayerViewController?

    private lazy var activityIndicator = {
        let indicator = NCActivityIndicator(frame: .init(x: 0, y: 0, width: 100, height: 100))
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.cycleColors = [.lightGray]

        return indicator
    }()

    private lazy var downloadIndicator = {
        let downloadIndicator = MediaDownloadIndicatorView(frame: .zero)
        downloadIndicator.isHidden = true

        return downloadIndicator
    }()

    private lazy var videoPlayButton = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 64)
            .applying(UIImage.SymbolConfiguration(paletteColors: [UIColor.white.withAlphaComponent(0.9), UIColor.black.withAlphaComponent(0.5)]))

        let videoPlayButton = UIButton(type: .system)
        videoPlayButton.translatesAutoresizingMaskIntoConstraints = false
        videoPlayButton.setImage(UIImage(systemName: "play.circle.fill")?.withConfiguration(configuration), for: .normal)
        videoPlayButton.isHidden = true
        videoPlayButton.accessibilityLabel = NSLocalizedString("Play", comment: "Start playing a video")
        videoPlayButton.addAction(UIAction { [weak self] _ in
            self?.startDownloadNow()
        }, for: .touchUpInside)

        return videoPlayButton
    }()

    init(message: NCChatMessage, account: TalkAccount) {
        self.message = message
        self.account = account

        self.fileDownloader = NCChatFileController(account: account)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        self.view.addSubview(self.zoomableView)
        self.view.addSubview(self.activityIndicator)
        self.view.addSubview(self.videoPlayButton)
        self.view.addSubview(self.downloadIndicator)

        NSLayoutConstraint.activate([
            self.zoomableView.leftAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leftAnchor),
            self.zoomableView.rightAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.rightAnchor),
            self.zoomableView.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.zoomableView.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            self.activityIndicator.centerXAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerXAnchor),
            self.activityIndicator.centerYAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerYAnchor),
            self.videoPlayButton.centerXAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerXAnchor),
            self.videoPlayButton.centerYAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerYAnchor),
            self.downloadIndicator.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            self.downloadIndicator.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])

        self.zoomableView.replaceContentView(self.imageView)

        fileDownloader.delegate = self

        self.navigationItem.title = self.message.file()?.name

        NotificationCenter.default.addObserver(self, selector: #selector(didChangeDownloadProgress(notification:)), name: NSNotification.Name.NCChatFileControllerDidChangeDownloadProgress, object: nil)

        self.startLoading()

        AllocationTracker.shared.addAllocation("NCMediaViewerPageViewController")
    }

    deinit {
        self.pendingDownload?.cancel()
        self.pendingIndicatorReveal?.cancel()
        self.previewRequest?.cancel()
        self.fileDownloader.cancelDownload()
        self.flushSharableFileHandlers(with: nil)
        self.removePlayerViewControllerIfNeeded()
        AllocationTracker.shared.removeAllocation("NCMediaViewerPageViewController")
    }

    override func viewWillDisappear(_ animated: Bool) {
        self.playerViewController?.player?.pause()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Only re-fit when our bounds actually changed. Assigning a new image invalidates the image
        // view's intrinsic content size, which can trigger a layout pass, and resizing here
        // unconditionally would throw away the zoom and pan the user set.
        guard self.zoomableView.bounds != self.lastLaidOutBounds else { return }

        self.lastLaidOutBounds = self.zoomableView.bounds
        self.zoomableView.resizeContentView()
    }

    // MARK: - Page state

    func didBecomeCurrentPage() {
        self.isCurrentPage = true

        guard self.isViewLoaded else { return }

        self.scheduleDownloadIfNeeded()
    }

    func didResignCurrentPage() {
        self.isCurrentPage = false

        self.pendingDownload?.cancel()
        self.pendingDownload = nil

        // A download for a page the user swiped past only slows down the one they are looking at
        if self.state != .full {
            self.fileDownloader.cancelDownload()
            self.isDownloading = false
            self.updateProgressPresentation()
        }
    }

    // MARK: - Sharing

    ///
    /// Hands over the original file, downloading it first if needed.
    ///
    /// The completion is always called on the main queue, with nil when the file could not be
    /// downloaded.
    ///
    func requestSharableFile(completion: @escaping (URL?) -> Void) {
        if let sharableFileURL = self.sharableFileURL {
            completion(sharableFileURL)
            return
        }

        self.sharableFileHandlers.append(completion)

        // The user is waiting for it now, so skip the delay we normally give the preview
        self.startDownloadNow()
    }

    private func flushSharableFileHandlers(with url: URL?) {
        let handlers = self.sharableFileHandlers
        self.sharableFileHandlers = []

        handlers.forEach { $0(url) }
    }

    // MARK: - Loading

    private func startLoading() {
        guard let file = self.message.file() else {
            self.showErrorView()
            self.state = .failed
            return
        }

        // Reuse a file we already downloaded before asking the server whether it is still current.
        // downloadFile() below validates it and swaps in a new one if it was replaced.
        if let path = file.path,
           let cachedURL = self.fileDownloader.cachedFileURL(forFileNamed: (path as NSString).lastPathComponent, expectedSize: file.size ?? 0) {

            self.displayFile(at: cachedURL, isValidated: false)
            self.flushSharableFileHandlers(with: cachedURL)
        } else if self.canUsePreview(for: file) {
            self.expectsPreview = true
            self.showBlurhashPlaceholder(for: file)
            self.requestPreview(for: file)
        }

        self.updateProgressPresentation()
        self.scheduleDownloadIfNeeded()
    }

    // Animated gifs and files without a server-side preview go straight to the download, like the
    // chat cells do.
    private func canUsePreview(for file: NCMessageFileParameter) -> Bool {
        guard file.previewAvailable, !self.message.isAnimatableGif, let mimetype = file.mimetype else { return false }

        return NCUtils.isImage(fileType: mimetype) || NCUtils.isVideo(fileType: mimetype)
    }

    private func showBlurhashPlaceholder(for file: NCMessageFileParameter) {
        guard let blurhash = file.blurhash, file.width > 0, file.height > 0 else { return }

        let aspectRatio = CGFloat(file.height) / CGFloat(file.width)

        guard let placeholder = UIImage(blurHash: blurhash, size: .init(width: 20, height: 20 * aspectRatio)) else { return }

        self.display(image: placeholder, contentSize: .init(width: file.width, height: file.height), crossfade: false)
        self.state = .placeholder
    }

    private func requestPreview(for file: NCMessageFileParameter) {
        // Same size the chat cell asks for, so this usually resolves straight from the cache
        let requestedHeight = Int(3 * fileMessageCellFileMaxPreviewHeight)

        self.previewRequest = NCAPIController.sharedInstance().getPreviewForFile(file.parameterId, width: -1, height: requestedHeight, forAccount: self.account) { [weak self] image, error in
            guard let self else { return }

            // This can be called twice, once from the cache and once after the refresh, and might
            // also lose the race against a finished download
            guard self.state == .idle || self.state == .placeholder || self.state == .preview else { return }

            guard let image, error == nil else {
                self.previewDidFail()
                return
            }

            self.display(image: image, contentSize: image.size, crossfade: self.state == .placeholder)
            self.setState(.preview)
        }
    }

    private func previewDidFail() {
        // Refreshing an already displayed preview can fail, which changes nothing for us
        guard self.state != .preview else { return }

        self.expectsPreview = false

        // There is nothing to look at, so get the original as soon as possible
        self.pendingDownload?.cancel()
        self.pendingDownload = nil
        self.scheduleDownloadIfNeeded()
        self.updateProgressPresentation()
    }

    private func scheduleDownloadIfNeeded() {
        guard self.isCurrentPage, !self.displayedFileIsValidated, self.pendingDownload == nil, !self.isDownloading else { return }

        let delay = self.expectsPreview ? self.downloadDelay : 0

        let workItem = DispatchWorkItem { [weak self] in
            self?.pendingDownload = nil
            self?.startDownload()
        }

        self.pendingDownload = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func startDownloadNow() {
        self.pendingDownload?.cancel()
        self.pendingDownload = nil
        self.startDownload()
    }

    private func startDownload() {
        guard !self.isDownloading, !self.displayedFileIsValidated, let fileId = self.message.file()?.parameterId else { return }

        self.isDownloading = true
        self.downloadDidFail = false
        self.updateProgressPresentation()

        self.fileDownloader.downloadFile(withFileId: fileId)
    }

    // MARK: - Display

    private var displayPixelSize: CGFloat {
        // We may be asked before the first layout, so fall back until we find something usable
        var viewportSize = self.zoomableView.bounds.size

        if viewportSize.width < 1 || viewportSize.height < 1 {
            viewportSize = self.view.bounds.size
        }

        if viewportSize.width < 1 || viewportSize.height < 1 {
            viewportSize = self.view.window?.windowScene?.screen.bounds.size ?? .init(width: 1024, height: 1024)
        }

        return MediaImageDownsampler.recommendedPixelSize(forViewportSize: viewportSize, displayScale: self.traitCollection.displayScale, zoomScale: self.sharpUpToZoomScale)
    }

    private func displayFile(at url: URL, isValidated: Bool) {
        guard let mimetype = self.message.file()?.mimetype else {
            self.handleFailure()
            return
        }

        self.displayedFileFingerprint = self.fingerprint(of: url)

        if NCUtils.isVideo(fileType: mimetype) {
            self.sharableFileURL = url
            self.displayedFileIsValidated = isValidated
            self.playVideo(from: url)
        } else if NCUtils.isImage(fileType: mimetype) {
            if self.message.isAnimatableGif {
                self.displayGif(at: url, isValidated: isValidated)
            } else {
                self.displayImage(at: url, isValidated: isValidated)
            }
        } else {
            self.handleFailure()
        }
    }

    private func displayImage(at url: URL, isValidated: Bool) {
        let maxPixelSize = self.displayPixelSize

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let image = MediaImageDownsampler.decodeImage(at: url, maxPixelSize: maxPixelSize)

            DispatchQueue.main.async {
                guard let self else { return }

                guard let image else {
                    self.handleFailure()
                    return
                }

                self.sharableFileURL = url
                self.displayedFileIsValidated = isValidated
                self.display(image: image, contentSize: image.size, crossfade: self.state == .preview || self.state == .placeholder)
                self.setState(.full)
            }
        }
    }

    private func displayGif(at url: URL, isValidated: Bool) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let data = try? Data(contentsOf: url),
                  let gifImage = try? UIImage(gifData: data),
                  // The gif image itself reports a zero size, so take the dimensions from a still
                  let sizeReference = UIImage(data: data)
            else {
                DispatchQueue.main.async { self?.handleFailure() }
                return
            }

            DispatchQueue.main.async {
                guard let self else { return }

                self.sharableFileURL = url
                self.displayedFileIsValidated = isValidated
                self.displayedImage = sizeReference
                self.imageView.setGifImage(gifImage)
                self.applyContentSize(sizeReference.size)
                self.showContent()
                self.setState(.full)
            }
        }
    }

    private func display(image: UIImage, contentSize: CGSize, crossfade: Bool) {
        self.displayedImage = image

        if crossfade, self.imageView.image != nil {
            UIView.transition(with: self.imageView, duration: 0.2, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                self.imageView.image = image
            }
        } else {
            self.imageView.image = image
        }

        self.applyContentSize(contentSize)
        self.showContent()
    }

    ///
    /// Adopts a new content size, keeping what the user is looking at.
    ///
    /// Only the aspect ratio matters for the layout, so replacing a preview with the original of the
    /// same shape needs no geometry change at all and the zoom and pan simply stay as they are.
    ///
    private func applyContentSize(_ contentSize: CGSize) {
        guard !self.aspectMatches(self.zoomableView.contentViewSize, contentSize) else { return }

        let restoreRect = self.zoomableView.isZoomed ? self.zoomableView.normalizedVisibleRect : nil

        self.zoomableView.contentViewSize = contentSize
        self.lastLaidOutBounds = self.zoomableView.bounds

        if let restoreRect {
            self.zoomableView.restoreVisibleRect(restoreRect)
        } else {
            self.zoomableView.resizeContentView()
        }
    }

    // Identifies the file we loaded. NCChatFileController replaces a stale cached file, which
    // changes both values, so an unchanged fingerprint means there is nothing to load again.
    private func fingerprint(of url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modificationDate = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? Int
        else { return nil }

        return "\(modificationDate.timeIntervalSince1970)-\(size)"
    }

    private func aspectMatches(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        guard lhs.width > 0, lhs.height > 0, rhs.width > 0, rhs.height > 0 else { return false }

        return abs((lhs.width / lhs.height) - (rhs.width / rhs.height)) < 0.01
    }

    private func showContent() {
        self.zoomableView.isHidden = false
        self.imageView.isHidden = false
        self.errorView.removeFromSuperview()
    }

    private func setState(_ newState: MediaState) {
        self.state = newState
        self.updateProgressPresentation()
        self.delegate?.mediaViewerPageStateDidChange(self)
    }

    func showErrorView() {
        self.imageView.image = nil
        self.displayedImage = nil
        self.removePlayerViewControllerIfNeeded()

        guard self.errorView.superview == nil else { return }

        self.view.addSubview(self.errorView)

        NSLayoutConstraint.activate([
            self.errorView.leadingAnchor.constraint(greaterThanOrEqualTo: self.view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            self.errorView.trailingAnchor.constraint(greaterThanOrEqualTo: self.view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            self.errorView.centerXAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerXAnchor),
            self.errorView.centerYAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerYAnchor)
        ])
    }

    private func handleFailure() {
        self.isDownloading = false
        self.downloadDidFail = true

        // A preview is a lot better than an error view, so keep showing it and offer a retry
        if self.state == .preview || self.state == .full {
            self.updateProgressPresentation()
            return
        }

        self.showErrorView()
        self.setState(.failed)
    }

    // MARK: - Progress

    private func updateProgressPresentation() {
        let hasVisibleMedia = self.state == .preview || self.state == .full

        if hasVisibleMedia || self.state == .failed {
            self.activityIndicator.stopAnimating()
            self.activityIndicator.isHidden = true
        } else {
            self.activityIndicator.isHidden = false
            self.activityIndicator.startAnimating()
        }

        self.videoPlayButton.isHidden = !(self.state == .preview && NCUtils.isVideo(fileType: self.message.file()?.mimetype ?? ""))

        if hasVisibleMedia, self.isDownloading {
            self.revealDownloadIndicator()
        } else if self.state == .preview, self.downloadDidFail {
            // The download failed while a preview is up, so let the user try again
            self.showDownloadRetry()
        } else {
            self.hideDownloadIndicator()
        }
    }

    private func revealDownloadIndicator() {
        guard self.pendingIndicatorReveal == nil else { return }

        // Already up, most likely showing the retry from a previous attempt
        guard self.downloadIndicator.isHidden else {
            self.downloadIndicator.showProgress()
            return
        }

        // Do not flash an indicator for a download that finishes right away
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }

            self.pendingIndicatorReveal = nil

            guard self.isDownloading else { return }

            self.downloadIndicator.showProgress()
            self.downloadIndicator.alpha = 0
            self.downloadIndicator.isHidden = false

            UIView.animate(withDuration: 0.2) {
                self.downloadIndicator.alpha = 1
            }
        }

        self.pendingIndicatorReveal = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + self.indicatorRevealDelay, execute: workItem)
    }

    private func showDownloadRetry() {
        self.pendingIndicatorReveal?.cancel()
        self.pendingIndicatorReveal = nil

        self.downloadIndicator.showRetry { [weak self] in
            self?.startDownloadNow()
        }

        self.downloadIndicator.alpha = 1
        self.downloadIndicator.isHidden = false
    }

    private func hideDownloadIndicator() {
        self.pendingIndicatorReveal?.cancel()
        self.pendingIndicatorReveal = nil

        guard !self.downloadIndicator.isHidden else { return }

        UIView.animate(withDuration: 0.2) {
            self.downloadIndicator.alpha = 0
        } completion: { _ in
            self.downloadIndicator.isHidden = true
            self.downloadIndicator.stopAnimating()
        }
    }

    func didChangeDownloadProgress(notification: Notification) {
        DispatchQueue.main.async {
            guard let fileParameter = self.message.file(),
                  let receivedStatus = NCChatFileStatus.getStatus(from: notification, for: fileParameter),
                  receivedStatus.canReportProgress
            else { return }

            self.activityIndicator.indicatorMode = .determinate
            self.activityIndicator.setProgress(Float(receivedStatus.downloadProgress), animated: true)
            self.downloadIndicator.setProgress(Float(receivedStatus.downloadProgress))
        }
    }

    // MARK: - NCChatFileController delegate

    func fileControllerDidLoadFile(_ fileController: NCChatFileController, with fileStatus: NCChatFileStatus) {
        self.isDownloading = false

        guard let localPath = fileStatus.fileLocalPath else {
            self.handleFailure()
            return
        }

        let url = URL(fileURLWithPath: localPath)

        // The file is on disk, a pending share does not have to wait for it to be decoded
        self.flushSharableFileHandlers(with: url)

        // We might already show this exact file from the optimistic cache check. The server just
        // confirmed it is still current, so there is nothing to load again.
        if self.state == .full, self.sharableFileURL == url,
           let fingerprint = self.displayedFileFingerprint, fingerprint == self.fingerprint(of: url) {

            self.displayedFileIsValidated = true
            self.setState(.full)
            return
        }

        self.displayFile(at: url, isValidated: true)
    }

    func fileControllerDidFailLoadingFile(_ fileController: NCChatFileController, withFileId fileId: String, withErrorDescription errorDescription: String) {
        print("Error downloading picture: " + errorDescription)

        self.flushSharableFileHandlers(with: nil)
        self.handleFailure()
    }

    // MARK: - NCZoomableView delegate

    func contentViewZoomDidChange(_ view: NCZoomableView, _ scale: Double) {
        self.delegate?.mediaViewerPageZoomDidChange(self, scale)
    }

    // MARK: - Video

    private func playVideo(from videoURL: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set audio session category: \(error)")
        }

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

        // The player is not the still image, so there is no zoom to preserve here
        self.zoomableView.contentViewSize = playerViewController.view.bounds.size
        self.zoomableView.resizeContentView()
        self.zoomableView.isHidden = false
        self.imageView.isHidden = true

        self.view.bringSubviewToFront(self.downloadIndicator)

        self.setState(.full)
    }

    private func removePlayerViewControllerIfNeeded() {
        if let playerVC = self.playerViewController {
            playerVC.player?.replaceCurrentItem(with: nil)
            playerVC.willMove(toParent: nil)
            playerVC.view.removeFromSuperview()
            playerVC.removeFromParent()
            self.playerViewController = nil
        }
    }
}
