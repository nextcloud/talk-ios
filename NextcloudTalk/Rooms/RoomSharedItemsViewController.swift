//
// SPDX-FileCopyrightText: 2022 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import UIKit
import AVFoundation
import QuickLook
import PassKit

class RoomSharedItemsViewController: UIViewController,
                                     UITableViewDataSource,
                                     UITableViewDelegate,
                                     UICollectionViewDataSource,
                                     UICollectionViewDelegate,
                                     WaterfallLayoutDelegate,
                                     MediaViewerMessageSource,
                                     SharedAudioCellDelegate,
                                     AVAudioPlayerDelegate,
                                     QLPreviewControllerDelegate,
                                     QLPreviewControllerDataSource,
                                     VLCKitVideoViewControllerDelegate {

    private struct MediaSection {
        let month: DateComponents
        let title: String
        var items: [NCChatMessage]
    }

    let room: NCRoom
    private let itemsOverviewLimit: Int = 1
    private let itemLimit: Int = 100

    /// Reserved below the content for the loading indicator, also how close to the end it shows
    private static let loadingMoreIndicatorHeight: CGFloat = 44.0

    private static let mediaViewerPrefetchDistance = 10

    private static let fileItemTypes: Set<String> = [kSharedItemTypeMedia, kSharedItemTypeFile, kSharedItemTypeAudio,
                                                     kSharedItemTypeVoice, kSharedItemTypeRecording]

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return formatter
    }()

    private var sharedItemsOverview: [String: [NCChatMessage]] = [:]
    private var currentItemType: String = "all"
    /// All loaded items of the current type, newest first
    private var currentItems: [NCChatMessage] = []
    private var mediaSections: [MediaSection] = []
    private var currentLastItemId: Int = -1
    private var hasMore = true
    private var isLoading = false
    // Bumped on every type change, so responses for the previous type are ignored
    private var generation = 0
    private var loadTask: URLSessionDataTask?

    private var audioPlayer: AVAudioPlayer?
    private var audioPlayerMessageId: Int?
    // The last play request, so a slow download doesn't start playing over a newer one
    private var pendingAudioMessageId: Int?
    private var audioProgressTimer: Timer?

    private var previewControllerFilePath: String = ""
    private var isPreviewControllerShown: Bool = false

    weak var previewChatViewController: ContextChatViewController?
    weak var previewNavigationChatViewController: NCNavigationController?

    private var isShowingMedia: Bool {
        return self.currentItemType == kSharedItemTypeMedia
    }

    private var activeScrollView: UIScrollView {
        return self.isShowingMedia ? self.collectionView : self.tableView
    }

    private lazy var sharedItemsBackgroundView = PlaceholderView(for: .insetGrouped)

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 64, bottom: 0, right: 0)
        tableView.tableFooterView = UIView()
        tableView.register(UINib(nibName: DirectoryTableViewCell.nibName, bundle: nil), forCellReuseIdentifier: DirectoryTableViewCell.identifier)
        tableView.register(SharedFileCell.self, forCellReuseIdentifier: SharedFileCell.identifier)
        tableView.register(SharedAudioCell.self, forCellReuseIdentifier: SharedAudioCell.identifier)
        tableView.register(SharedLocationCell.self, forCellReuseIdentifier: SharedLocationCell.identifier)
        tableView.estimatedRowHeight = 80
        return tableView
    }()

    private lazy var waterfallLayout: WaterfallLayout = {
        let layout = WaterfallLayout()
        layout.delegate = self
        return layout
    }()

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: self.waterfallLayout)
        collectionView.backgroundColor = .systemGroupedBackground
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(SharedMediaCell.self, forCellWithReuseIdentifier: SharedMediaCell.identifier)
        collectionView.register(SharedMediaSectionHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: SharedMediaSectionHeaderView.identifier)
        return collectionView
    }()

    /// Pinned to the screen, a footer would move while scrolling and as items are appended
    private lazy var loadingMoreIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = true
        indicator.color = .secondaryLabel
        return indicator
    }()

    init(room: NCRoom) {
        self.room = room
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NCAppBranding.styleViewController(self)

        self.navigationItem.title = NSLocalizedString("Shared items", comment: "")
        self.view.backgroundColor = .systemGroupedBackground

        self.view.addSubview(self.tableView)
        self.view.addSubview(self.collectionView)
        self.view.addSubview(self.loadingMoreIndicator)

        self.tableView.translatesAutoresizingMaskIntoConstraints = false
        self.collectionView.translatesAutoresizingMaskIntoConstraints = false
        self.loadingMoreIndicator.translatesAutoresizingMaskIntoConstraints = false

        // Set once, so the content never shifts when the indicator comes and goes
        self.tableView.contentInset.bottom = Self.loadingMoreIndicatorHeight
        self.collectionView.contentInset.bottom = Self.loadingMoreIndicatorHeight

        NSLayoutConstraint.activate([
            self.tableView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.tableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.tableView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.tableView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),

            self.collectionView.topAnchor.constraint(equalTo: self.view.topAnchor),
            self.collectionView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            self.collectionView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            self.collectionView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),

            self.loadingMoreIndicator.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            self.loadingMoreIndicator.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])

        self.collectionView.isHidden = true
        self.getItemsOverview()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { _ in
            self.collectionView.collectionViewLayout.invalidateLayout()
        })
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if self.isMovingFromParent || self.isBeingDismissed {
            self.stopAudio()
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        // The layout insets for the horizontal safe area, which can change without the width changing
        self.collectionView.collectionViewLayout.invalidateLayout()
    }

    func availableItemTypes() -> [String] {
        var availableItemTypes: [String] = []
        for itemType in sharedItemsOverview.keys {
            guard let items = sharedItemsOverview[itemType] else {continue}
            if !items.isEmpty {
                availableItemTypes.append(itemType)
            }
        }
        return availableItemTypes.sorted(by: { $0 < $1 })
    }

    // MARK: - Loading

    func getItemsOverview() {
        guard let account = room.account else { return }

        showFetchingItemsPlaceholderView()

        NCAPIController.sharedInstance()
            .getSharedItemsOverview(inRoom: room.token, withLimit: itemsOverviewLimit, forAccount: account) { itemsOverview, error in
                if error == nil {
                    self.sharedItemsOverview = itemsOverview ?? [:]
                    let availableItemTypes = self.availableItemTypes()
                    if availableItemTypes.isEmpty {
                        self.hideFetchingItemsPlaceholderView()
                    } else if availableItemTypes.contains(kSharedItemTypeMedia) {
                        self.setupViewForItemType(itemType: kSharedItemTypeMedia)
                    } else if availableItemTypes.contains(kSharedItemTypeFile) {
                        self.setupViewForItemType(itemType: kSharedItemTypeFile)
                    } else if let firstItemType = availableItemTypes.first {
                        self.setupViewForItemType(itemType: firstItemType)
                    }
                } else {
                    self.hideFetchingItemsPlaceholderView()
                }
            }
    }

    func setupViewForItemType(itemType: String) {
        self.loadTask?.cancel()
        self.stopAudio()

        self.generation += 1
        self.currentItemType = itemType
        self.currentLastItemId = -1
        self.hasMore = true
        self.isLoading = false

        self.removeAllItems()

        self.tableView.isHidden = self.isShowingMedia
        self.collectionView.isHidden = !self.isShowingMedia
        self.tableView.backgroundView = nil
        self.collectionView.backgroundView = nil

        setupTitleButtonForItemType(itemType: itemType)
        loadMoreItems()
    }

    private func removeAllItems() {
        // Read first, so UIKit checks the delete against its real counts even if it never loaded them
        let removedSectionCount = self.collectionView.numberOfSections

        self.currentItems = []
        self.mediaSections = []

        self.tableView.reloadData()
        self.tableView.setContentOffset(CGPoint(x: 0, y: -self.tableView.adjustedContentInset.top), animated: false)

        guard removedSectionCount > 0 else { return }

        // Not reloadData(), it only applies at the next layout pass, after the new type's first insert
        UIView.performWithoutAnimation {
            self.collectionView.deleteSections(IndexSet(0..<removedSectionCount))
            self.collectionView.setContentOffset(CGPoint(x: 0, y: -self.collectionView.adjustedContentInset.top), animated: false)
        }
    }

    private func loadMoreItemsIfNearBottom() {
        guard self.hasMore, !self.isLoading, !self.currentItems.isEmpty else { return }
        guard self.distanceToBottom < self.activeScrollView.bounds.height else { return }

        self.loadMoreItems()
    }

    private var distanceToBottom: CGFloat {
        let scrollView = self.activeScrollView
        let maximumOffset = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom

        return maximumOffset - scrollView.contentOffset.y
    }

    private func loadMoreItems() {
        guard self.hasMore, !self.isLoading, let account = room.account else { return }

        let myGeneration = self.generation

        self.isLoading = true

        if self.currentItems.isEmpty {
            self.showFetchingItemsPlaceholderView()
        }

        self.updateLoadingMoreIndicator()

        self.loadTask = NCAPIController.sharedInstance()
            .getSharedItems(ofType: currentItemType, fromLastMessageId: currentLastItemId, inRoom: room.token,
                            withLimit: itemLimit, forAccount: account) { [weak self] items, lastItemId, error in
                guard let self, myGeneration == self.generation else { return }

                self.isLoading = false

                if error == nil, let sharedItems = items {
                    // Unshared files still come back, parsed into a plain comment without a file parameter
                    let isFileType = Self.fileItemTypes.contains(self.currentItemType)
                    let filteredItems = sharedItems.filter { !isFileType || $0.file() != nil }
                    let sortedItems = filteredItems.sorted(by: { $0.messageId > $1.messageId })

                    self.currentLastItemId = lastItemId
                    // The server filters after applying the limit, so only an empty page marks the end
                    self.hasMore = !sharedItems.isEmpty && lastItemId > 0

                    self.appendItems(sortedItems)
                } else {
                    self.hasMore = false
                }

                self.hideFetchingItemsPlaceholderView()
                self.updateLoadingMoreIndicator()

                // A page may not fill the screen, and nothing else would request the next one
                self.loadMoreItemsIfNearBottom()
            }
    }

    private func appendItems(_ items: [NCChatMessage]) {
        guard !items.isEmpty else { return }

        self.currentItems.append(contentsOf: items)

        guard self.isShowingMedia else {
            self.tableView.reloadData()
            return
        }

        // Read first, so UIKit checks the insert against its real counts even if it never loaded them
        let oldSectionCount = self.collectionView.numberOfSections
        var insertedIndexPaths: [IndexPath] = []

        for message in items {
            let date = Date(timeIntervalSince1970: TimeInterval(message.timestamp))
            let month = Calendar.current.dateComponents([.year, .month], from: date)

            if let lastSection = self.mediaSections.indices.last, self.mediaSections[lastSection].month == month {
                self.mediaSections[lastSection].items.append(message)

                if lastSection < oldSectionCount {
                    insertedIndexPaths.append(IndexPath(item: self.mediaSections[lastSection].items.count - 1, section: lastSection))
                }
            } else {
                self.mediaSections.append(MediaSection(month: month, title: Self.monthFormatter.string(from: date), items: [message]))
            }
        }

        self.collectionView.performBatchUpdates {
            self.collectionView.insertSections(IndexSet(oldSectionCount..<self.mediaSections.count))
            self.collectionView.insertItems(at: insertedIndexPaths)
        }
    }

    /// Only for someone waiting at the end, the initial load has the placeholder
    private func updateLoadingMoreIndicator() {
        let showsIndicator = self.isLoading && !self.currentItems.isEmpty && self.distanceToBottom < Self.loadingMoreIndicatorHeight

        if showsIndicator {
            self.loadingMoreIndicator.startAnimating()
        } else {
            self.loadingMoreIndicator.stopAnimating()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView == self.activeScrollView else { return }

        self.loadMoreItemsIfNearBottom()

        self.updateLoadingMoreIndicator()
    }

    // MARK: - User interface

    func setupTitleButtonForItemType(itemType: String) {
        let itemTypeSelectorButton = UIButton(type: .custom)
        let buttonTitle = nameForItemType(itemType: itemType) + " ▼"
        itemTypeSelectorButton.setTitle(buttonTitle, for: .normal)
        itemTypeSelectorButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        itemTypeSelectorButton.setTitleColor(NCAppBranding.themeTextColor(), for: .normal)
        if #available(iOS 26.0, *) {
            itemTypeSelectorButton.setTitleColor(.label, for: .normal)
        } else {
            itemTypeSelectorButton.setTitleColor(NCAppBranding.themeTextColor(), for: .normal)
        }
        self.navigationItem.titleView = itemTypeSelectorButton

        var menuActions: [UIAction] = []

        for itemType in availableItemTypes() {
            let itemTypeName = nameForItemType(itemType: itemType)
            let action = UIAction(title: itemTypeName, image: nil) { [unowned self] _ in
                self.setupViewForItemType(itemType: itemType)
            }

            if itemType == currentItemType {
                action.state = .on
            }

            menuActions.append(action)
        }

        itemTypeSelectorButton.showsMenuAsPrimaryAction = true
        itemTypeSelectorButton.menu = UIMenu(children: menuActions)
    }

    func showFetchingItemsPlaceholderView() {
        sharedItemsBackgroundView.placeholderView.isHidden = true
        sharedItemsBackgroundView.setImage(UIImage(systemName: "photo.on.rectangle.angled"))
        sharedItemsBackgroundView.placeholderImage.contentMode = .scaleAspectFit
        sharedItemsBackgroundView.placeholderTextView.text = NSLocalizedString("No shared items", comment: "")
        sharedItemsBackgroundView.loadingView.startAnimating()
        sharedItemsBackgroundView.loadingView.isHidden = false

        if self.isShowingMedia {
            self.collectionView.backgroundView = sharedItemsBackgroundView
        } else {
            self.tableView.backgroundView = sharedItemsBackgroundView
        }
    }

    func hideFetchingItemsPlaceholderView() {
        sharedItemsBackgroundView.loadingView.stopAnimating()
        sharedItemsBackgroundView.loadingView.isHidden = true
        sharedItemsBackgroundView.placeholderView.isHidden = !currentItems.isEmpty
    }

    func nameForItemType(itemType: String) -> String {
        switch itemType {
        case kSharedItemTypeAudio:
            return NSLocalizedString("Audios", comment: "")
        case kSharedItemTypeDeckcard:
            return NSLocalizedString("Deck cards", comment: "")
        case kSharedItemTypeFile:
            return NSLocalizedString("Files", comment: "")
        case kSharedItemTypeMedia:
            return NSLocalizedString("Media", comment: "Category of shared items in a conversation: images and videos")
        case kSharedItemTypeLocation:
            return NSLocalizedString("Locations", comment: "")
        case kSharedItemTypeOther:
            return NSLocalizedString("Others", comment: "Category of shared items in a conversation, for everything without its own category")
        case kSharedItemTypeVoice:
            return NSLocalizedString("Voice messages", comment: "")
        case kSharedItemTypePoll:
            return NSLocalizedString("Polls", comment: "")
        case kSharedItemTypeRecording:
            return NSLocalizedString("Recordings", comment: "")
        case kSharedItemTypePinned:
            return NSLocalizedString("Pinned messages", comment: "")
        default:
            return NSLocalizedString("Shared items", comment: "")
        }
    }

    func imageForMessage(message: NCChatMessage) -> UIImage {
        var image = UIImage(systemName: "bubble")

        if message.file() != nil {
            let imageName = NCUtils.previewImage(forMimeType: message.file().mimetype)
            image = UIImage(named: imageName)
        }

        if message.geoLocation() != nil {
            image = UIImage(systemName: "mappin")
        }

        if message.deckCard() != nil {
            image = UIImage(named: "deck-item")
        }

        if message.poll != nil {
            image = UIImage(systemName: "chart.bar")
        }

        return image ?? UIImage()
    }

    // MARK: - Media

    private func aspectRatio(of message: NCChatMessage) -> CGFloat {
        guard let file = message.file(), file.previewAvailable else { return 1 }

        if file.previewImageWidth > 0, file.previewImageHeight > 0 {
            return CGFloat(file.previewImageWidth) / CGFloat(file.previewImageHeight)
        }

        if file.width > 0, file.height > 0 {
            return CGFloat(file.width) / CGFloat(file.height)
        }

        return 1
    }

    private func mediaMessage(at indexPath: IndexPath) -> NCChatMessage? {
        guard indexPath.section < self.mediaSections.count,
              indexPath.item < self.mediaSections[indexPath.section].items.count
        else { return nil }

        return self.mediaSections[indexPath.section].items[indexPath.item]
    }

    private func presentMedia(of message: NCChatMessage) {
        guard let account = self.room.account else { return }

        // Formats only VLC can play keep going through the download
        guard NCMediaViewerViewController.canShowMedia(of: message) else {
            if let file = message.file() {
                downloadFile(file: file)
            }

            return
        }

        let mediaViewController = NCMediaViewerViewController(initialMessage: message, room: self.room, account: account, messageSource: self)
        let navController = CustomPresentableNavigationController(rootViewController: mediaViewController)

        self.present(navController, interactiveDismissalType: .standard)
    }

    // MARK: - MediaViewerMessageSource

    func mediaViewerMessage(before message: NCChatMessage) -> NCChatMessage? {
        guard let index = self.currentItems.firstIndex(where: { $0.messageId == message.messageId }) else { return nil }

        if self.currentItems.count - index <= Self.mediaViewerPrefetchDistance {
            self.loadMoreItems()
        }

        // The list is newest first, so older media come after
        return self.currentItems[(index + 1)...].first(where: { NCMediaViewerViewController.canShowMedia(of: $0) })
    }

    func mediaViewerMessage(after message: NCChatMessage) -> NCChatMessage? {
        guard let index = self.currentItems.firstIndex(where: { $0.messageId == message.messageId }) else { return nil }

        return self.currentItems[..<index].last(where: { NCMediaViewerViewController.canShowMedia(of: $0) })
    }

    // MARK: - Audio

    private func playAudio(of message: NCChatMessage) {
        if let audioPlayer, self.audioPlayerMessageId == message.messageId {
            self.startAudioPlayback(audioPlayer)
            return
        }

        guard let file = message.file(), let account = self.room.account else { return }

        self.pendingAudioMessageId = message.messageId

        ChatFileDownloader.shared.downloadFile(withFileId: file.parameterId, fromAccount: account) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.pendingAudioMessageId == message.messageId else { return }

                self.pendingAudioMessageId = nil

                switch result {
                case .success(let fileStatus):
                    guard let fileLocalPath = fileStatus.fileLocalPath,
                          let data = try? Data(contentsOf: URL(fileURLWithPath: fileLocalPath)),
                          let player = try? AVAudioPlayer(data: data)
                    else {
                        // Formats AVAudioPlayer can't play still open in QuickLook or VLC
                        self.didLoadFile(with: fileStatus)
                        return
                    }

                    self.stopAudio()

                    player.delegate = self
                    self.audioPlayer = player
                    self.audioPlayerMessageId = message.messageId
                    self.startAudioPlayback(player)
                case .failure(.fileUnavailable(let errorDescription)), .failure(.downloadFailed(let errorDescription)):
                    self.didFailLoadingFile(with: errorDescription)
                case .failure(.cancelled):
                    break
                }
            }
        }
    }

    private func startAudioPlayback(_ player: AVAudioPlayer) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback)
        try? session.setActive(true)

        player.play()

        self.audioProgressTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateVisibleAudioCells()
        }
        // The common modes keep the progress moving while the list is scrolled
        RunLoop.main.add(timer, forMode: .common)
        self.audioProgressTimer = timer

        self.updateVisibleAudioCells()
    }

    private func pauseAudio() {
        self.audioPlayer?.pause()
        self.audioProgressTimer?.invalidate()
        self.audioProgressTimer = nil
        self.updateVisibleAudioCells()
    }

    private func stopAudio() {
        self.pendingAudioMessageId = nil
        self.audioPlayer?.stop()
        self.audioPlayer = nil
        self.audioPlayerMessageId = nil
        self.audioProgressTimer?.invalidate()
        self.audioProgressTimer = nil
        self.updateVisibleAudioCells()
    }

    private func updateVisibleAudioCells() {
        for case let cell as SharedAudioCell in self.tableView.visibleCells {
            self.updatePlayerView(of: cell)
        }
    }

    private func updatePlayerView(of cell: SharedAudioCell) {
        if let audioPlayer, cell.messageId != nil, cell.messageId == self.audioPlayerMessageId {
            cell.playerView.setPlayerProgress(audioPlayer.currentTime, isPlaying: audioPlayer.isPlaying, maximumValue: audioPlayer.duration)
        } else {
            cell.playerView.resetPlayer()
        }
    }

    func sharedAudioCellWantsToPlay(_ cell: SharedAudioCell) {
        guard let message = self.currentItems.first(where: { $0.messageId == cell.messageId }) else { return }

        self.playAudio(of: message)
    }

    func sharedAudioCellWantsToPause(_ cell: SharedAudioCell) {
        guard cell.messageId == self.audioPlayerMessageId else { return }

        self.pauseAudio()
    }

    func sharedAudioCell(_ cell: SharedAudioCell, wantsToSeekTo time: TimeInterval) {
        guard let audioPlayer, cell.messageId == self.audioPlayerMessageId else { return }

        audioPlayer.currentTime = time
        self.updatePlayerView(of: cell)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.audioProgressTimer?.invalidate()
        self.audioProgressTimer = nil
        self.updateVisibleAudioCells()
    }

    // MARK: - File downloader

    func downloadFile(file: NCMessageFileParameter) {
        guard let account = self.room.account else { return }

        ChatFileDownloader.shared.downloadFile(withFileId: file.parameterId, fromAccount: account) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let fileStatus):
                self.didLoadFile(with: fileStatus)
            case .failure(.fileUnavailable(let errorDescription)), .failure(.downloadFailed(let errorDescription)):
                self.didFailLoadingFile(with: errorDescription)
            case .failure(.cancelled):
                break
            }
        }
    }

    private func didLoadFile(with fileStatus: NCChatFileStatus) {
        DispatchQueue.main.async {
            if self.isPreviewControllerShown {
                return
            }

            guard let fileLocalPath = fileStatus.fileLocalPath else { return }

            self.previewControllerFilePath = fileLocalPath
            self.isPreviewControllerShown = true

            let fileExtension = URL(fileURLWithPath: fileLocalPath).pathExtension.lowercased()

            // Use VLCKitVideoViewController for file formats unsupported by the native PreviewController
            if VLCKitVideoViewController.supportedFileExtensions.contains(fileExtension) {
                let vlcViewController = VLCKitVideoViewController(filePath: fileLocalPath)
                vlcViewController.delegate = self
                vlcViewController.modalPresentationStyle = .fullScreen

                self.present(vlcViewController, animated: true)

                return
            }

            // Use PKAddPassesViewController for Apple Wallet passes
            if fileExtension == "pkpass" {
                if let passData = try? Data(contentsOf: URL(fileURLWithPath: fileLocalPath)),
                   let pass = try? PKPass(data: passData),
                   let addPassVC = PKAddPassesViewController(pass: pass) {
                    self.present(addPassVC, animated: true)
                    self.isPreviewControllerShown = false
                    return
                }
            }

            let previewController = QLPreviewController()
            previewController.dataSource = self
            previewController.delegate = self
            self.present(previewController, animated: true)
        }
    }

    private func didFailLoadingFile(with errorDescription: String) {
        let alertTitle = NSLocalizedString("Unable to load file", comment: "")
        let alert = UIAlertController(
            title: alertTitle,
            message: errorDescription,
            preferredStyle: .alert)

        let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil)
        alert.addAction(okAction)

        self.present(alert, animated: true, completion: nil)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return NSURL(fileURLWithPath: previewControllerFilePath)
    }

    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        isPreviewControllerShown = false
    }

    func vlckitVideoViewControllerDismissed(_ controller: VLCKitVideoViewController) {
        isPreviewControllerShown = false
    }

    // MARK: - Locations

    func presentLocation(location: GeoLocationRichObject) {
        let mapViewController = MapViewController(geoLocationRichObject: location)
        let navigationViewController = NCNavigationController(rootViewController: mapViewController)
        self.present(navigationViewController, animated: true, completion: nil)
    }

    // MARK: - Polls

    func presentPoll(pollId: Int) {
        let pollViewController = PollVotingView(room: room)
        let navigationViewController = NCNavigationController(rootViewController: pollViewController)
        self.present(navigationViewController, animated: true, completion: nil)

        let activeAccount = NCDatabaseManager.sharedInstance().activeAccount()
        NCAPIController.sharedInstance().getPoll(withId: pollId, inRoom: room.token, forAccount: activeAccount) { poll, error in
            if let poll = poll, error == nil {
                pollViewController.updatePoll(poll: poll)
            }
        }
    }

    // MARK: - Other files

    func openLink(link: String) {
        NCUtils.openLinkInBrowser(link: link)
    }

    // MARK: - Message context

    private func contextMenuConfiguration(for message: NCChatMessage, identifier: NSCopying) -> UIContextMenuConfiguration? {
        // The preview shows the context of the message, which is not available without the context endpoint
        guard self.room.supportsMessageContext else { return nil }

        return UIContextMenuConfiguration(identifier: identifier, previewProvider: {

            // Init the BaseChatViewController without message to directly show a preview
            if let account = self.room.account, let chatViewController = ContextChatViewController(forRoom: self.room, withAccount: account, withMessage: [], withHighlightId: 0) {
                self.previewChatViewController = chatViewController

                // Fetch the context of the message and update the BaseChatViewController
                chatViewController.showContext(ofMessageId: message.messageId, withLimit: 50, withCloseButton: false)

                let navController = NCNavigationController(rootViewController: chatViewController)
                self.previewNavigationChatViewController = navController

                return navController
            }

            return nil
        }, actionProvider: { _ in
            UIMenu(children: [UIAction(title: NSLocalizedString("Open", comment: "Context menu action to open a shared file")) { _ in
                DispatchQueue.main.async {
                    self.presentPreviewChatViewController()
                }
            }])
        })
    }

    func presentPreviewChatViewController() {
        guard let previewNavigationChatViewController = self.previewNavigationChatViewController,
              let previewChatViewController = self.previewChatViewController
        else { return }

        self.present(previewNavigationChatViewController, animated: false)

        previewChatViewController.navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Close", comment: ""), primaryAction: UIAction { [weak previewChatViewController] _ in
            previewChatViewController?.dismiss(animated: true)
        })
    }

    // MARK: - Table view

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // The media type is shown by the collection view
        return self.isShowingMedia ? 0 : currentItems.count
    }

    private enum RowKind {
        case audio, file, location, other
    }

    private func rowKind(for message: NCChatMessage) -> RowKind {
        switch currentItemType {
        case kSharedItemTypeVoice, kSharedItemTypeAudio, kSharedItemTypeRecording:
            // Video recordings are listed like files and open in the media viewer
            return NCUtils.isAudio(fileType: message.file()?.mimetype ?? "") ? .audio : .file
        case kSharedItemTypeFile:
            return .file
        case kSharedItemTypeLocation:
            return .location
        default:
            return .other
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard indexPath.row < currentItems.count, self.rowKind(for: currentItems[indexPath.row]) == .other else {
            return UITableView.automaticDimension
        }

        return DirectoryTableViewCell.cellHeight
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let message = currentItems[indexPath.row]

        switch self.rowKind(for: message) {
        case .audio:
            let cell = tableView.dequeueReusableCell(withIdentifier: SharedAudioCell.identifier, for: indexPath)

            if let audioCell = cell as? SharedAudioCell {
                audioCell.delegate = self
                audioCell.configure(with: message)
                self.updatePlayerView(of: audioCell)
            }

            return cell
        case .file:
            let cell = tableView.dequeueReusableCell(withIdentifier: SharedFileCell.identifier, for: indexPath)

            if let fileCell = cell as? SharedFileCell, let account = self.room.account {
                fileCell.configure(with: message, showsServerPreview: !self.room.isClassified, account: account)
            }

            return cell
        case .location:
            let cell = tableView.dequeueReusableCell(withIdentifier: SharedLocationCell.identifier, for: indexPath)
            (cell as? SharedLocationCell)?.configure(with: message)

            return cell
        case .other:
            break
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: DirectoryTableViewCell.identifier) as? DirectoryTableViewCell ??
        DirectoryTableViewCell(style: .default, reuseIdentifier: DirectoryTableViewCell.identifier)

        if let file = message.file() {
            cell.fileNameLabel?.text = file.name
        } else {
            cell.fileNameLabel?.text = message.parsedMessage().string
        }

        var infoLabelText = NCUtils.relativeTimeFromDate(date: Date(timeIntervalSince1970: Double(message.timestamp)))
        if !message.actorDisplayName.isEmpty {
            infoLabelText += " ⸱ " + message.actorDisplayName
        }
        if let file = message.file(), let size = file.size, size > 0 {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let sizeString = formatter.string(fromByteCount: Int64(size))
            infoLabelText += " ⸱ " + sizeString
        }
        cell.fileInfoLabel?.text = infoLabelText

        let image = imageForMessage(message: message)
        cell.fileImageView?.image = image
        cell.fileImageView?.tintColor = .secondaryLabel
        if message.file()?.previewAvailable != nil {
            cell.fileImageView?.setPreview(forFileId: message.file().parameterId, withWidth: 40, withHeight: 40, usingAccount: .activeAccount)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard indexPath.row < currentItems.count else { return nil }

        return self.contextMenuConfiguration(for: currentItems[indexPath.row], identifier: indexPath as NSCopying)
    }

    func tableView(_ tableView: UITableView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
        animator.addAnimations {
            self.presentPreviewChatViewController()
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let message = currentItems[indexPath.row]

        self.tableView.deselectRow(at: indexPath, animated: true)

        switch self.rowKind(for: message) {
        case .audio:
            if self.audioPlayerMessageId == message.messageId, self.audioPlayer?.isPlaying == true {
                self.pauseAudio()
            } else {
                self.playAudio(of: message)
            }
        case .file:
            if NCMediaViewerViewController.canShowMedia(of: message) {
                presentMedia(of: message)
            } else if let file = message.file() {
                downloadFile(file: file)
            }
        case .location:
            if let geoLocation = message.geoLocation() {
                presentLocation(location: GeoLocationRichObject(from: geoLocation))
            }
        case .other:
            self.openOtherItem(message)
        }
    }

    private func openOtherItem(_ message: NCChatMessage) {
        switch currentItemType {
        case kSharedItemTypeDeckcard, kSharedItemTypeOther:
            if let link = message.objectShareLink() {
                openLink(link: link)
            }
        case kSharedItemTypePoll:
            if let poll = message.poll, let pollId = Int(poll.parameterId) {
                presentPoll(pollId: pollId)
            }
        default:
            return
        }
    }

    // MARK: - Collection view

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return self.mediaSections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard section < self.mediaSections.count else { return 0 }

        return self.mediaSections[section].items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SharedMediaCell.identifier, for: indexPath)

        guard let mediaCell = cell as? SharedMediaCell,
              let message = self.mediaMessage(at: indexPath),
              let account = self.room.account
        else { return cell }

        mediaCell.configure(with: message, aspectRatio: self.aspectRatio(of: message), showsServerPreview: !self.room.isClassified, account: account)

        return mediaCell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: SharedMediaSectionHeaderView.identifier, for: indexPath)

        if let headerView = view as? SharedMediaSectionHeaderView, indexPath.section < self.mediaSections.count {
            headerView.setTitle(self.mediaSections[indexPath.section].title)
        }

        return view
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let message = self.mediaMessage(at: indexPath) else { return }

        self.presentMedia(of: message)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard indexPaths.count == 1, let indexPath = indexPaths.first, let message = self.mediaMessage(at: indexPath) else { return nil }

        return self.contextMenuConfiguration(for: message, identifier: indexPath as NSCopying)
    }

    func collectionView(_ collectionView: UICollectionView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
        animator.addAnimations {
            self.presentPreviewChatViewController()
        }
    }

    // MARK: - WaterfallLayoutDelegate

    func waterfallLayout(_ layout: WaterfallLayout, aspectRatioForItemAt indexPath: IndexPath) -> CGFloat {
        guard let message = self.mediaMessage(at: indexPath) else { return 1 }

        return self.aspectRatio(of: message)
    }

    func waterfallLayout(_ layout: WaterfallLayout, heightForHeaderInSection section: Int) -> CGFloat {
        return SharedMediaSectionHeaderView.height
    }
}
