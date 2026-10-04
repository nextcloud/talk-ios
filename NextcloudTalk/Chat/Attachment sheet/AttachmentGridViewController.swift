//
// SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import AVFoundation
import Photos
import Toast
import UIKit

@MainActor
protocol AttachmentGridViewControllerDelegate: AnyObject {
    func attachmentGridDidChangeSelection(_ grid: AttachmentGridViewController)
    func attachmentGridDidTapCamera(_ grid: AttachmentGridViewController)
}

/// The recent photos and videos of the library in a grid of three columns, with the live camera as first tile.
/// Asks for access to the library when it is shown, and adapts to limited access and to no access.
final class AttachmentGridViewController: UIViewController,
                                          UICollectionViewDataSource,
                                          UICollectionViewDelegate,
                                          UICollectionViewDataSourcePrefetching,
                                          PHPhotoLibraryChangeObserver {

    /// The most items that can be selected at once
    static let maxSelection = kShareConfirmationMaxItems

    private static let columns = 3
    private static let spacing: CGFloat = 2

    weak var delegate: AttachmentGridViewControllerDelegate?

    /// Whether the first tile opens the camera
    var showsCameraTile = false {
        didSet {
            guard self.showsCameraTile != oldValue, self.isViewLoaded else { return }
            self.collectionView.reloadData()
        }
    }

    /// The session to show in the camera tile. Without a session, the tile shows an icon.
    var cameraSession: AVCaptureSession? {
        didSet { self.updateCameraTile() }
    }

    /// The selected items, in the order they were selected in
    private(set) var selectedAssets: [PHAsset] = []

    private var fetchResult: PHFetchResult<PHAsset>?
    private let imageManager = PHCachingImageManager()
    private var isObservingLibrary = false
    private var isRequestingAuthorization = false

    private lazy var thumbnailOptions: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return options
    }()

    // MARK: - Views

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: self.makeLayout())
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.register(AttachmentAssetCell.self, forCellWithReuseIdentifier: AttachmentAssetCell.reuseIdentifier)
        collectionView.register(AttachmentCameraCell.self, forCellWithReuseIdentifier: AttachmentCameraCell.reuseIdentifier)
        collectionView.accessibilityIdentifier = "attachmentSheetGrid"
        return collectionView
    }()

    private lazy var limitedAccessBanner: UIView = {
        let label = UILabel()
        label.text = NSLocalizedString("You allowed access to some of your photos only", comment: "Shown in the attachment sheet when the access to the photo library is limited")
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 0

        var configuration = UIButton.Configuration.plain()
        configuration.title = NSLocalizedString("Select more photos", comment: "Opens the system picker to allow access to more photos")
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 0)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.preferredFont(forTextStyle: .footnote)
            return attributes
        }

        let button = UIButton(configuration: configuration)
        button.addAction(UIAction { [weak self] _ in self?.presentLimitedLibraryPicker() }, for: .touchUpInside)
        button.accessibilityIdentifier = "attachmentSheetSelectMorePhotos"
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stackView = UIStackView(arrangedSubviews: [label, button])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 12)
        stackView.isHidden = true

        return stackView
    }()

    private let deniedLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var allowAccessButton: UIButton = {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = NSLocalizedString("Allow access", comment: "Button to allow access to the photo library in the settings")
        configuration.cornerStyle = .capsule

        let button = UIButton(configuration: configuration)
        button.addAction(UIAction { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }, for: .touchUpInside)
        button.accessibilityIdentifier = "attachmentSheetAllowAccess"
        return button
    }()

    private lazy var deniedView: UIView = {
        let imageView = UIImageView(image: UIImage(systemName: "photo.on.rectangle.angled"))
        imageView.tintColor = .secondaryLabel
        imageView.contentMode = .scaleAspectFit
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40, weight: .light)
        imageView.isAccessibilityElement = false

        let stackView = UIStackView(arrangedSubviews: [imageView, self.deniedLabel, self.allowAccessButton])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 12

        let container = UIView()
        container.addSubview(stackView)
        container.isHidden = true

        NSLayoutConstraint.activate([
            stackView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stackView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            stackView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32)
        ])

        return container
    }()

    // MARK: - Lifecycle

    deinit {
        if self.isObservingLibrary {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view.backgroundColor = .clear

        let contentStack = UIStackView(arrangedSubviews: [self.limitedAccessBanner, self.collectionView])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        self.limitedAccessBanner.setContentHuggingPriority(.required, for: .vertical)
        self.collectionView.setContentHuggingPriority(.defaultLow, for: .vertical)

        self.deniedView.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(contentStack)
        self.view.addSubview(self.deniedView)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: self.view.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),

            self.deniedView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.deniedView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.deniedView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.deniedView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
        ])

        // The access can be changed in the settings while the sheet is open
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)

        self.refreshAuthorization()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        self.imageManager.stopCachingImagesForAllAssets()

        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.updateCameraTile()
        }
    }

    @objc private func applicationDidBecomeActive() {
        self.refreshAuthorization()
    }

    // MARK: - Photo library access

    /// Shows the grid, or what replaces it, depending on what the user allowed. Asks for access when that
    /// was not decided yet.
    private func refreshAuthorization() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch status {
        case .notDetermined:
            guard !self.isRequestingAuthorization else { return }
            self.isRequestingAuthorization = true

            PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
                DispatchQueue.main.async { [weak self] in
                    self?.isRequestingAuthorization = false
                    self?.refreshAuthorization()
                }
            }
        case .authorized:
            self.showGrid(isLimited: false)
        case .limited:
            self.showGrid(isLimited: true)
        case .denied:
            self.showNoAccess(isRestricted: false)
        case .restricted:
            self.showNoAccess(isRestricted: true)
        @unknown default:
            self.showNoAccess(isRestricted: false)
        }
    }

    private func showGrid(isLimited: Bool) {
        self.deniedView.isHidden = true
        self.collectionView.isHidden = false
        self.limitedAccessBanner.isHidden = !isLimited

        if !self.isObservingLibrary {
            PHPhotoLibrary.shared().register(self)
            self.isObservingLibrary = true
        }

        if self.fetchResult == nil {
            self.fetchAssets()
        }
    }

    private func showNoAccess(isRestricted: Bool) {
        if self.isObservingLibrary {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
            self.isObservingLibrary = false
        }

        self.fetchResult = nil
        self.imageManager.stopCachingImagesForAllAssets()
        self.setSelectedAssets([])

        if isRestricted {
            self.deniedLabel.text = NSLocalizedString("Access to your photos is restricted on this device", comment: "Shown in the attachment sheet when the photo library can not be used")
        } else {
            self.deniedLabel.text = NSLocalizedString("Allow access to your photos to see your recent photos and videos here", comment: "Shown in the attachment sheet when the access to the photo library was denied")
        }

        self.allowAccessButton.isHidden = isRestricted
        self.collectionView.reloadData()
        self.collectionView.isHidden = true
        self.limitedAccessBanner.isHidden = true
        self.deniedView.isHidden = false
    }

    private func fetchAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d",
                                        PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)

        self.fetchResult = PHAsset.fetchAssets(with: options)
        self.collectionView.reloadData()
    }

    private func presentLimitedLibraryPicker() {
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: self)
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in
            self?.handleLibraryChange(changeInstance)
        }
    }

    private func handleLibraryChange(_ change: PHChange) {
        guard let fetchResult, let details = change.changeDetails(for: fetchResult) else { return }

        self.fetchResult = details.fetchResultAfterChanges

        // Selected items can be edited or deleted in the meantime
        var newSelection: [PHAsset] = []

        for asset in self.selectedAssets {
            guard let assetDetails = change.changeDetails(for: asset) else {
                newSelection.append(asset)
                continue
            }

            if assetDetails.objectWasDeleted {
                continue
            }

            let updatedAsset: PHAsset? = assetDetails.objectAfterChanges
            newSelection.append(updatedAsset ?? asset)
        }

        self.imageManager.stopCachingImagesForAllAssets()
        self.setSelectedAssets(newSelection)
        self.collectionView.reloadData()
    }

    // MARK: - Selection

    private func setSelectedAssets(_ assets: [PHAsset]) {
        let changed = assets.map { $0.localIdentifier } != self.selectedAssets.map { $0.localIdentifier }
        self.selectedAssets = assets

        if changed {
            self.refreshVisibleSelectionStates()
            self.delegate?.attachmentGridDidChangeSelection(self)
        }
    }

    /// Forgets the selection, for example after the items were sent
    func clearSelection() {
        self.setSelectedAssets([])
    }

    private func selectionIndex(of assetIdentifier: String) -> Int? {
        guard let index = self.selectedAssets.firstIndex(where: { $0.localIdentifier == assetIdentifier }) else { return nil }
        return index + 1
    }

    private func refreshVisibleSelectionStates() {
        for case let cell as AttachmentAssetCell in self.collectionView.visibleCells {
            if let identifier = cell.representedAssetIdentifier {
                cell.setSelectionIndex(self.selectionIndex(of: identifier))
            }
        }
    }

    private func toggleSelection(of asset: PHAsset) {
        var newSelection = self.selectedAssets

        if let index = newSelection.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
            newSelection.remove(at: index)
        } else if newSelection.count >= Self.maxSelection {
            let message = String.localizedStringWithFormat(NSLocalizedString("You can select up to %ld items", comment: "Shown when more photos and videos are selected than can be sent at once"), Self.maxSelection)

            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            UIAccessibility.post(notification: .announcement, argument: message)
            self.view.makeToast(message, duration: 2, point: CGPoint(x: self.view.bounds.midX, y: self.view.bounds.midY), title: nil, image: nil, completion: nil)
            return
        } else {
            newSelection.append(asset)
        }

        self.setSelectedAssets(newSelection)
    }

    // MARK: - Camera tile

    private func updateCameraTile() {
        guard self.isViewLoaded, self.showsCameraTile,
              let cell = self.collectionView.cellForItem(at: IndexPath(item: 0, section: 0)) as? AttachmentCameraCell
        else { return }

        cell.configure(session: self.cameraSession, interfaceOrientation: CameraCaptureHelpers.interfaceOrientation(of: self.view))
    }

    // MARK: - Layout

    private func makeLayout() -> UICollectionViewLayout {
        let spacing = Self.spacing
        let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0 / CGFloat(Self.columns)), heightDimension: .fractionalHeight(1.0))
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .fractionalWidth(1.0 / CGFloat(Self.columns)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitem: item, count: Self.columns)
        group.interItemSpacing = .fixed(spacing)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = spacing
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0)

        return UICollectionViewCompositionalLayout(section: section)
    }

    /// The size thumbnails are requested in, in pixels. Prefetching needs the same size as the cells, or the cache is not used.
    private var thumbnailSize: CGSize {
        let width = (self.collectionView.bounds.width - Self.spacing * CGFloat(Self.columns - 1)) / CGFloat(Self.columns)
        let side = max(width, 80) * self.traitCollection.displayScale
        return CGSize(width: side, height: side)
    }

    // MARK: - Collection view

    private var cameraTileCount: Int {
        return self.showsCameraTile ? 1 : 0
    }

    private func asset(at indexPath: IndexPath) -> PHAsset? {
        let index = indexPath.item - self.cameraTileCount

        guard index >= 0, let fetchResult, index < fetchResult.count else { return nil }
        return fetchResult.object(at: index)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard self.fetchResult != nil else { return 0 }
        return self.cameraTileCount + (self.fetchResult?.count ?? 0)
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if self.showsCameraTile, indexPath.item == 0 {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AttachmentCameraCell.reuseIdentifier, for: indexPath)

            if let cameraCell = cell as? AttachmentCameraCell {
                cameraCell.configure(session: self.cameraSession, interfaceOrientation: CameraCaptureHelpers.interfaceOrientation(of: self.view))
            }

            return cell
        }

        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AttachmentAssetCell.reuseIdentifier, for: indexPath)

        guard let assetCell = cell as? AttachmentAssetCell, let asset = self.asset(at: indexPath) else { return cell }

        let identifier = asset.localIdentifier
        assetCell.representedAssetIdentifier = identifier
        assetCell.configure(for: asset)
        assetCell.setSelectionIndex(self.selectionIndex(of: identifier))

        assetCell.imageRequestID = self.imageManager.requestImage(for: asset,
                                                                  targetSize: self.thumbnailSize,
                                                                  contentMode: .aspectFill,
                                                                  options: self.thumbnailOptions) { [weak assetCell] image, _ in
            guard let assetCell, assetCell.representedAssetIdentifier == identifier else { return }
            assetCell.setThumbnail(image)
        }

        return assetCell
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let assetCell = cell as? AttachmentAssetCell, assetCell.imageRequestID != PHInvalidImageRequestID {
            self.imageManager.cancelImageRequest(assetCell.imageRequestID)
            assetCell.imageRequestID = PHInvalidImageRequestID
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)

        if self.showsCameraTile, indexPath.item == 0 {
            self.delegate?.attachmentGridDidTapCamera(self)
            return
        }

        if let asset = self.asset(at: indexPath) {
            self.toggleSelection(of: asset)
        }
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let assets = indexPaths.compactMap { self.asset(at: $0) }

        self.imageManager.startCachingImages(for: assets, targetSize: self.thumbnailSize, contentMode: .aspectFill, options: self.thumbnailOptions)
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let assets = indexPaths.compactMap { self.asset(at: $0) }

        self.imageManager.stopCachingImages(for: assets, targetSize: self.thumbnailSize, contentMode: .aspectFill, options: self.thumbnailOptions)
    }
}
