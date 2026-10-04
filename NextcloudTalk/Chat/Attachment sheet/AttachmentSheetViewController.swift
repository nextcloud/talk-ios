//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Photos
import UIKit

@MainActor
protocol AttachmentSheetViewControllerDelegate: AnyObject {
    /// The user chose one of the items of the strip, or the camera tile. The sheet stays open, the delegate closes it.
    func attachmentSheet(_ sheet: AttachmentSheetViewController, didChoose action: AttachmentSheetAction)

    /// The selected photos and videos were written to files. The sheet stays open, the delegate closes it.
    func attachmentSheet(_ sheet: AttachmentSheetViewController, didExport files: [AttachmentAssetExporter.ExportedFile])
}

/// What the "+" button of the chat shows: a sheet with the recent photos and videos, and a strip with everything
/// else that can be shared at the bottom.
final class AttachmentSheetViewController: UIViewController, AttachmentGridViewControllerDelegate {

    weak var delegate: AttachmentSheetViewControllerDelegate?

    private let actions: [AttachmentSheetAction]
    private let grid = AttachmentGridViewController()

    private var previewSession: AttachmentCameraPreviewSession?
    private var isVisible = false
    private var exportTask: Task<Void, Never>?
    private var exportToken = UUID()

    private var hasCameraTile: Bool {
        return self.actions.contains(.camera)
    }

    // MARK: - Views

    private lazy var sendButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .capsule
        configuration.buttonSize = .large

        let button = UIButton(configuration: configuration)
        button.addAction(UIAction { [weak self] _ in self?.startExport() }, for: .touchUpInside)
        button.accessibilityIdentifier = "attachmentSheetSend"
        return button
    }()

    private lazy var sendContainer: UIView = {
        let container = UIView()
        self.sendButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(self.sendButton)
        container.isHidden = true

        NSLayoutConstraint.activate([
            self.sendButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            self.sendButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            self.sendButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            self.sendButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16)
        ])

        return container
    }()

    private lazy var progressView: UIProgressView = {
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        return progressView
    }()

    private lazy var progressLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    /// Covers the sheet while the selected items are written to files, which takes a while for items in iCloud
    private lazy var progressOverlay: UIView = {
        var cancelConfiguration = UIButton.Configuration.plain()
        cancelConfiguration.title = NSLocalizedString("Cancel", comment: "")

        let cancelButton = UIButton(configuration: cancelConfiguration)
        cancelButton.addAction(UIAction { [weak self] _ in self?.cancelExport() }, for: .touchUpInside)
        cancelButton.accessibilityIdentifier = "attachmentSheetCancelExport"

        let stackView = UIStackView(arrangedSubviews: [self.progressLabel, self.progressView, cancelButton])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 16

        let overlay = UIView()
        overlay.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)
        overlay.addSubview(stackView)
        overlay.isHidden = true

        NSLayoutConstraint.activate([
            stackView.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            stackView.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 32),
            stackView.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -32)
        ])

        return overlay
    }()

    // MARK: - Init

    init(actions: [AttachmentSheetAction]) {
        self.actions = actions

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.previewSession?.stop()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .systemBackground

        self.grid.delegate = self
        self.grid.showsCameraTile = self.hasCameraTile
        self.addChild(self.grid)
        self.grid.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.grid.view)
        self.grid.didMove(toParent: self)

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.heightAnchor.constraint(equalToConstant: 1 / max(self.traitCollection.displayScale, 1)).isActive = true

        let bottomStack = UIStackView(arrangedSubviews: [self.sendContainer, separator, self.makeActionStrip()])
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        bottomStack.axis = .vertical
        self.view.addSubview(bottomStack)

        self.progressOverlay.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(self.progressOverlay)

        NSLayoutConstraint.activate([
            // Leaves room for the grabber
            self.grid.view.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 24),
            self.grid.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.grid.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            self.grid.view.bottomAnchor.constraint(equalTo: bottomStack.topAnchor),

            bottomStack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            bottomStack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            bottomStack.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),

            self.progressOverlay.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.progressOverlay.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.progressOverlay.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.progressOverlay.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
        ])

        // The camera is released when the app is left, and taken again when it's back
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)

        // Files of earlier sends are not needed anymore
        DispatchQueue.global(qos: .utility).async {
            AttachmentAssetExporter.removeOldExports()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.isVisible = true
        self.startPreviewIfPossible()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Also called when the sheet is moved behind another screen
        self.isVisible = false
        self.stopPreview()
    }

    // MARK: - Strip

    private func makeActionStrip() -> UIView {
        let stackView = UIStackView(arrangedSubviews: self.actions.map { self.makeStripButton(for: $0) })
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.alignment = .fill
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),

            // Fills the width when there are only a few items, scrolls when there are many
            stackView.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor),
            scrollView.heightAnchor.constraint(equalTo: stackView.heightAnchor)
        ])

        return scrollView
    }

    private func makeStripButton(for action: AttachmentSheetAction) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = action.title
        configuration.image = self.stripImage(for: action)
        configuration.imagePlacement = .top
        configuration.imagePadding = 6
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.preferredFont(forTextStyle: .caption2)
            return attributes
        }

        let button = UIButton(configuration: configuration)
        button.addAction(UIAction { [weak self] _ in self?.choose(action) }, for: .touchUpInside)
        button.accessibilityIdentifier = action.accessibilityIdentifier
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true

        return button
    }

    /// Symbols fit the strip as they are, images of the app are brought to the same size
    private func stripImage(for action: AttachmentSheetAction) -> UIImage? {
        guard let image = action.image else { return nil }

        if image.isSymbolImage {
            return image.applyingSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 20))
        }

        let size = CGSize(width: 24, height: 24)
        let scaledImage = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }

        return scaledImage.withRenderingMode(.alwaysTemplate)
    }

    private func choose(_ action: AttachmentSheetAction) {
        // The camera of the chat is opened after the sheet is closed, so the preview needs to have let go of it
        if action == .camera {
            self.stopPreview { [weak self] in
                guard let self else { return }
                self.delegate?.attachmentSheet(self, didChoose: action)
            }
        } else {
            self.stopPreview()
            self.delegate?.attachmentSheet(self, didChoose: action)
        }
    }

    // MARK: - Camera preview

    /// The camera is only started when it's allowed already and not needed for a call
    private var canShowLivePreview: Bool {
        return self.hasCameraTile
            && AttachmentCameraPreviewSession.isCameraAuthorized
            && !AttachmentCameraPreviewSession.isCameraBusyWithCall
    }

    private func startPreviewIfPossible() {
        guard self.isVisible, self.canShowLivePreview else { return }

        let previewSession = self.previewSession ?? AttachmentCameraPreviewSession()
        self.previewSession = previewSession

        previewSession.start()
        self.grid.cameraSession = previewSession.session
    }

    private func stopPreview(completion: (() -> Void)? = nil) {
        self.grid.cameraSession = nil

        guard let previewSession else {
            completion?()
            return
        }

        previewSession.stop(completion: completion)
    }

    @objc private func applicationWillResignActive() {
        self.stopPreview()
    }

    @objc private func applicationDidBecomeActive() {
        self.startPreviewIfPossible()
    }

    // MARK: - Grid delegate

    func attachmentGridDidChangeSelection(_ grid: AttachmentGridViewController) {
        let count = grid.selectedAssets.count

        if count > 0 {
            self.sendButton.configuration?.title = String.localizedStringWithFormat(NSLocalizedString("Send (%ld)", comment: "Sends the selected photos and videos, the number is how many"), count)
        }

        UIView.animate(withDuration: 0.2) {
            self.sendContainer.isHidden = count == 0
            self.view.layoutIfNeeded()
        }
    }

    func attachmentGridDidTapCamera(_ grid: AttachmentGridViewController) {
        self.choose(.camera)
    }

    // MARK: - Export

    private func startExport() {
        let assets = self.grid.selectedAssets
        guard !assets.isEmpty, self.exportTask == nil else { return }

        self.setExportInProgress(true)
        self.updateExportProgress(index: 0, count: assets.count, fraction: 0)

        // A cancelled export finishes in the background, so it must not clear the task of a newer one
        let token = UUID()
        self.exportToken = token

        self.exportTask = Task {
            await self.export(assets)

            if self.exportToken == token {
                self.exportTask = nil
            }
        }
    }

    private func export(_ assets: [PHAsset]) async {
        var directory: URL?

        do {
            let exportDirectory = try AttachmentAssetExporter.makeExportDirectory()
            directory = exportDirectory

            var files: [AttachmentAssetExporter.ExportedFile] = []

            for (index, asset) in assets.enumerated() {
                try Task.checkCancellation()
                self.updateExportProgress(index: index, count: assets.count, fraction: 0)

                let file = try await AttachmentAssetExporter.export(asset, into: exportDirectory) { [weak self] fraction in
                    self?.updateExportProgress(index: index, count: assets.count, fraction: fraction)
                }

                files.append(file)
            }

            try Task.checkCancellation()

            self.setExportInProgress(false)
            self.delegate?.attachmentSheet(self, didExport: files)
        } catch {
            if let directory {
                try? FileManager.default.removeItem(at: directory)
            }

            // The overlay was removed when the export was cancelled
            guard !(error is CancellationError), !Task.isCancelled else { return }

            self.setExportInProgress(false)
            self.showExportError(error)
        }
    }

    private func cancelExport() {
        self.exportTask?.cancel()
        self.exportTask = nil
        self.exportToken = UUID()
        self.setExportInProgress(false)
    }

    private func setExportInProgress(_ inProgress: Bool) {
        self.progressOverlay.isHidden = !inProgress
        self.isModalInPresentation = inProgress

        if inProgress {
            UIAccessibility.post(notification: .screenChanged, argument: self.progressLabel)
        }
    }

    private func updateExportProgress(index: Int, count: Int, fraction: Double) {
        self.progressLabel.text = String.localizedStringWithFormat(NSLocalizedString("Preparing %1$ld of %2$ld…", comment: "Photos and videos are being prepared for sending, the numbers are the current one and all of them"), index + 1, count)
        self.progressView.progress = Float((Double(index) + fraction) / Double(count))
    }

    private func showExportError(_ error: Error) {
        let alert = UIAlertController(title: NSLocalizedString("Could not prepare the selected items", comment: "Title of an error shown when photos or videos could not be read from the photo library"),
                                      message: error.localizedDescription,
                                      preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))
        self.present(alert, animated: true)
    }
}
