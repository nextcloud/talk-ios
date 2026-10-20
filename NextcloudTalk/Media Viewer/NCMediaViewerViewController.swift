//
// SPDX-FileCopyrightText: 2024 Nextcloud GmbH and Nextcloud contributors
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation
import UIKit

///
/// Implemented by the chat that opened the media viewer. Replying and deleting are done by the chat,
/// without a delegate, or when the chat answers "no", the viewer offers neither.
///
@objc protocol NCMediaViewerViewControllerDelegate: AnyObject {
    func mediaViewerViewControllerCanReply(_ viewController: NCMediaViewerViewController) -> Bool
    func mediaViewerViewController(_ viewController: NCMediaViewerViewController, canDelete message: NCChatMessage) -> Bool
    func mediaViewerViewController(_ viewController: NCMediaViewerViewController, deletesFileGroupWith message: NCChatMessage) -> Bool
    func mediaViewerViewController(_ viewController: NCMediaViewerViewController, didRequestReplyTo message: NCChatMessage)
    func mediaViewerViewController(_ viewController: NCMediaViewerViewController, didRequestDelete message: NCChatMessage)
}

/// Decides which media the viewer swipes to, instead of the chat messages stored for the room
@objc protocol MediaViewerMessageSource: AnyObject {
    /// The closest older message to show before `message`, or nil to stop there
    func mediaViewerMessage(before message: NCChatMessage) -> NCChatMessage?

    /// The closest newer message to show after `message`, or nil to stop there
    func mediaViewerMessage(after message: NCChatMessage) -> NCChatMessage?
}

@objcMembers class NCMediaViewerViewController: UIViewController,
                                                UIPageViewControllerDelegate,
                                                UIPageViewControllerDataSource,
                                                NCMediaViewerPageViewControllerDelegate,
                                                ShareViewControllerDelegate,
                                                ShareConfirmationViewControllerDelegate {

    public weak var delegate: NCMediaViewerViewControllerDelegate?

    /// The shared items list already is the "all media" view, so it is not offered again from there.
    /// The shown message is not necessarily stored, so there is no list to swipe through either.
    public var isOpenedFromSharedItems = false

    private let room: NCRoom
    private let account: TalkAccount
    private let thread: NCThread?
    private let pageController = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
    private var initialMessage: NCChatMessage
    private weak var messageSource: MediaViewerMessageSource?

    private var fileMessagesToken: RLMNotificationToken?
    private var chatBlocksToken: RLMNotificationToken?
    private var counterText: String?

    // Replacing the data source while pages move would break the transition, so it waits
    private var isTransitioning = false
    private var needsDataSourceReset = false

    // Ids of all media the viewer can show, from the oldest to the newest. Kept, so swiping only needs a lookup.
    private var displayableMessageIds: [Int] = []
    private var hasOlderHistory = false

    private lazy var counterLabel = {
        let counterLabel = UILabel()
        counterLabel.font = .preferredFont(forTextStyle: .headline)
        counterLabel.adjustsFontForContentSizeCategory = true
        counterLabel.textAlignment = .center

        return counterLabel
    }()

    private lazy var fileNameLabel = {
        let fileNameLabel = UILabel()
        fileNameLabel.font = .preferredFont(forTextStyle: .caption1)
        fileNameLabel.adjustsFontForContentSizeCategory = true
        fileNameLabel.textAlignment = .center
        fileNameLabel.lineBreakMode = .byTruncatingMiddle
        fileNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        return fileNameLabel
    }()

    private lazy var titleStackView = {
        let titleStackView = UIStackView(arrangedSubviews: [counterLabel, fileNameLabel])
        titleStackView.axis = .vertical
        titleStackView.alignment = .center

        return titleStackView
    }()

    private lazy var moreButton = {
        // Built when the menu opens, so it always matches the page that is shown
        let menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] completion in
            completion(self?.makeMenuElements() ?? [])
        }])

        let moreButton = UIBarButtonItem(title: nil, image: UIImage(systemName: "ellipsis.circle"), primaryAction: nil, menu: menu)
        moreButton.accessibilityLabel = NSLocalizedString("More", comment: "More menu elements")

        return moreButton
    }()

    private lazy var forwardButton = {
        let forwardButton = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)
        forwardButton.primaryAction = UIAction(title: "", image: .init(systemName: "arrowshape.turn.up.right"), handler: { [unowned self] _ in
            self.forwardCurrentMedia()
        })
        forwardButton.accessibilityLabel = NSLocalizedString("Forward", comment: "")

        return forwardButton
    }()

    private lazy var drawButton = {
        let drawButton = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)
        drawButton.primaryAction = UIAction(title: "", image: .init(systemName: "pencil.tip.crop.circle"), handler: { [unowned self] _ in
            self.startDrawingOnCopy()
        })
        drawButton.accessibilityLabel = NSLocalizedString("Draw", comment: "")

        return drawButton
    }()

    init(initialMessage: NCChatMessage, room: NCRoom, account: TalkAccount, thread: NCThread? = nil, messageSource: MediaViewerMessageSource? = nil) {
        self.room = room
        self.initialMessage = initialMessage
        self.account = account
        self.thread = thread
        self.messageSource = messageSource

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        NCAppBranding.styleViewController(self)

        self.view.backgroundColor = .systemBackground
        self.setupNavigationBar()

        self.pageController.delegate = self
        self.pageController.dataSource = self
        self.pageController.view.translatesAutoresizingMaskIntoConstraints = false

        self.view.addSubview(self.pageController.view)

        NSLayoutConstraint.activate([
            self.pageController.view.leftAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.leftAnchor),
            self.pageController.view.rightAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.rightAnchor),
            self.pageController.view.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            self.pageController.view.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor)
        ])

        self.pageController.didMove(toParent: self)

        let initialViewController = NCMediaViewerPageViewController(message: self.initialMessage, account: self.account)
        initialViewController.delegate = self
        self.pageController.setViewControllers([initialViewController], direction: .forward, animated: false)

        // Not called by the page controller delegate for the initial view controller
        initialViewController.didBecomeCurrentPage()

        self.refreshMediaList()
        self.updateToolbarButtons()
        self.observeFileMessages()

        AllocationTracker.shared.addAllocation("NCMediaViewerViewController")
    }

    deinit {
        self.fileMessagesToken?.invalidate()
        self.chatBlocksToken?.invalidate()
        AllocationTracker.shared.removeAllocation("NCMediaViewerViewController")
    }

    func setupNavigationBar() {
        let closeButton = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)
        closeButton.primaryAction = UIAction(title: NSLocalizedString("Close", comment: ""), handler: { [unowned self] _ in
            self.dismiss(animated: true)
        })
        self.navigationItem.rightBarButtonItems = [closeButton, moreButton]
        self.navigationItem.titleView = titleStackView

        if #available(iOS 26.0, *) {
            self.counterLabel.textColor = .label
            self.fileNameLabel.textColor = .secondaryLabel
        } else {
            self.counterLabel.textColor = NCAppBranding.themeTextColor()
            self.fileNameLabel.textColor = NCAppBranding.themeTextColor()
        }

        self.navigationController?.setToolbarHidden(false, animated: false)

        let appearance = UIToolbarAppearance()
        appearance.backgroundColor = .secondarySystemBackground

        self.navigationController?.toolbar.standardAppearance = appearance
        self.navigationController?.toolbar.compactAppearance = appearance
        self.navigationController?.toolbar.scrollEdgeAppearance = appearance
    }

    func getCurrentPageViewController() -> NCMediaViewerPageViewController? {
        return self.pageController.viewControllers?.first as? NCMediaViewerPageViewController
    }

    /// For a message source that got more messages after it reported the end
    func reloadAdjacentPages() {
        self.needsDataSourceReset = true
        self.resetDataSourceIfNeeded()
    }

    // MARK: - PageViewController delegate

    func getAllFileMessages() -> RLMResults<AnyObject>? {
        guard let accountId = self.initialMessage.accountId else { return nil }

        var query = NSPredicate(format: "accountId = %@ AND token = %@ AND messageParametersJSONString contains[cd] %@", accountId, self.initialMessage.token, "\"file\":")

        // Like the thread chat does, so paging and replying stay inside the thread
        if let thread = self.thread {
            let threadQuery = NSPredicate(format: "threadId = %ld", thread.threadId)
            query = NSCompoundPredicate(andPredicateWithSubpredicates: [query, threadQuery])
        }
        let messages = NCChatMessage.objects(with: query).sortedResults(usingKeyPath: "messageId", ascending: true)

        return messages
    }

    /// Whether the viewer can show the file of `message`, formats only VLC can play excluded
    static func canShowMedia(of message: NCChatMessage) -> Bool {
        guard let file = message.file(), let filePath = file.path else { return false }

        let fileType = file.mimetype ?? ""
        let isSupportedMedia = NCUtils.isImage(fileType: fileType) || NCUtils.isVideo(fileType: fileType)
        let isUnsupportedExtension = VLCKitVideoViewController.supportedFileExtensions.contains(URL(fileURLWithPath: filePath).pathExtension.lowercased())

        return isSupportedMedia && !isUnsupportedExtension
    }

    func getPreviousFileMessage(from message: NCChatMessage) -> NCChatMessage? {
        if let messageSource {
            return messageSource.mediaViewerMessage(before: message)
        }

        let prevQuery = NSPredicate(format: "messageId < %ld", message.messageId)

        guard let queriedObjects = self.getAllFileMessages()?.objects(with: prevQuery) else { return nil }
        let messageObject = queriedObjects.lastObject()

        if let message = messageObject as? NCChatMessage {
            if Self.canShowMedia(of: message) {
                return message
            }

            return self.getPreviousFileMessage(from: message)
        }

        return nil
    }

    func getNextFileMessage(from message: NCChatMessage) -> NCChatMessage? {
        if let messageSource {
            return messageSource.mediaViewerMessage(after: message)
        }

        let prevQuery = NSPredicate(format: "messageId > %ld", message.messageId)

        guard let messageObject = self.getAllFileMessages()?.objects(with: prevQuery).firstObject() else { return nil }

        if let message = messageObject as? NCChatMessage {
            if Self.canShowMedia(of: message) {
                return message
            }

            return self.getNextFileMessage(from: message)
        }

        return nil
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard !self.isOpenedFromSharedItems || self.messageSource != nil,
              let prevMediaPageVC = viewController as? NCMediaViewerPageViewController,
              !prevMediaPageVC.message.isInvalidated,
              let prevMessage = self.getPreviousFileMessage(from: prevMediaPageVC.message)
        else { return nil }

        let mediaPageViewController = NCMediaViewerPageViewController(message: prevMessage, account: self.account)
        mediaPageViewController.delegate = self
        return mediaPageViewController
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard !self.isOpenedFromSharedItems || self.messageSource != nil,
              let prevMediaPageVC = viewController as? NCMediaViewerPageViewController,
              !prevMediaPageVC.message.isInvalidated,
              let nextMessage = self.getNextFileMessage(from: prevMediaPageVC.message)
        else { return nil }

        let mediaPageViewController = NCMediaViewerPageViewController(message: nextMessage, account: self.account)
        mediaPageViewController.delegate = self
        return mediaPageViewController
    }

    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
        self.isTransitioning = true
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        self.isTransitioning = false
        self.resetDataSourceIfNeeded()
        guard let mediaPageViewController = self.getCurrentPageViewController() else { return }

        // On a cancelled swipe the previous view controller is the current one again
        for case let previousPageViewController as NCMediaViewerPageViewController in previousViewControllers
        where previousPageViewController != mediaPageViewController {
            previousPageViewController.didResignCurrentPage()
        }

        mediaPageViewController.didBecomeCurrentPage()

        self.updateCounter()
        self.updateToolbarButtons()
    }

    // MARK: - Title and counter

    private func updateTitleView() {
        let message = self.getCurrentMessage()

        self.fileNameLabel.text = message?.file()?.name
        self.counterLabel.text = self.counterText
        self.counterLabel.isHidden = self.counterText == nil
        self.navigationItem.title = message?.file()?.name

        self.titleStackView.setNeedsLayout()
    }

    private func getCurrentMessage() -> NCChatMessage? {
        guard let message = self.getCurrentPageViewController()?.message, !message.isInvalidated else { return nil }

        return message
    }

    private var chatBlocksPredicate: NSPredicate {
        return NSPredicate(format: "internalId = %@ AND threadId = 0", self.room.internalId)
    }

    ///
    /// Reads the media list again, which is the expensive part. Needed when the stored messages change.
    ///
    private func refreshMediaList() {
        var messageIds: [Int] = []

        if let fileMessages = self.getAllFileMessages() {
            // The results are sorted from the oldest to the newest message
            for case let message as NCChatMessage in fileMessages where Self.canShowMedia(of: message) {
                messageIds.append(message.messageId)
            }
        }

        self.displayableMessageIds = messageIds

        self.refreshHistoryState()
    }

    private func refreshHistoryState() {
        // The oldest stored block knows whether there is more history. Without any block there is nothing known to load.
        let firstBlock = NCChatBlock.objects(with: self.chatBlocksPredicate).sortedResults(usingKeyPath: "newestMessageId", ascending: true).firstObject() as? NCChatBlock
        self.hasOlderHistory = firstBlock?.hasHistory ?? false

        self.updateCounter()
    }

    ///
    /// Counts like Telegram does: the oldest media of the list is "1 of M", the newest is "M of M".
    /// The "+" after M tells that older media can still be loaded.
    ///
    private func updateCounter() {
        defer {
            self.updateTitleView()
        }

        // No counter in a thread: the history blocks of a thread are not read here, and the original
        // message of a thread can be stored with threadId 0, so the total would be wrong
        guard !self.isOpenedFromSharedItems, self.thread == nil,
              let currentMessageId = self.getCurrentMessage()?.messageId,
              let index = self.displayableMessageIds.firstIndex(of: currentMessageId)
        else {
            self.counterText = nil
            return
        }

        var totalText = NumberFormatter.localizedString(from: NSNumber(value: self.displayableMessageIds.count), number: .none)

        if self.hasOlderHistory {
            totalText += "+"
        }

        let positionText = NumberFormatter.localizedString(from: NSNumber(value: index + 1), number: .none)
        let format = NSLocalizedString("%1$@ of %2$@", comment: "Position of the shown media in the media viewer, e.g. '2 of 5'. The second value ends with '+' when older media can still be loaded")

        self.counterText = String(format: format, positionText, totalText)
    }

    // The page stays the one we show when media is added or removed, only the counter is recalculated
    private func observeFileMessages() {
        // Nothing is listed there, so there is nothing to follow
        guard !self.isOpenedFromSharedItems else { return }

        // The first call only reports what is already there, the list was read when the viewer opened
        self.fileMessagesToken = self.getAllFileMessages()?.addNotificationBlock { [weak self] _, change, _ in
            guard let self, let change else { return }

            self.refreshMediaList()

            // Only added or removed messages can change the neighbours of the shown page
            if !change.insertions.isEmpty || !change.deletions.isEmpty {
                self.needsDataSourceReset = true
                self.resetDataSourceIfNeeded()
            }
        }

        self.chatBlocksToken = NCChatBlock.objects(with: self.chatBlocksPredicate).addNotificationBlock { [weak self] _, change, _ in
            guard change != nil else { return }

            self?.refreshHistoryState()
        }
    }

    // Forces the page controller to ask for its neighbours again
    private func resetDataSourceIfNeeded() {
        guard self.needsDataSourceReset, !self.isTransitioning else { return }

        self.needsDataSourceReset = false
        self.pageController.dataSource = nil
        self.pageController.dataSource = self
    }

    // MARK: - Toolbar

    func canForward(_ message: NCChatMessage) -> Bool {
        guard let file = message.file(), file.path != nil, message.accountId == self.account.accountId else { return false }

        return !message.isDeletedMessage && !self.room.isFederated && !self.room.isClassified
    }

    private func canDraw(_ message: NCChatMessage) -> Bool {
        let mimetype = message.file()?.mimetype ?? ""
        let isDrawable = NCUtils.isImage(fileType: mimetype) && !NCUtils.isGif(fileType: mimetype) && !mimetype.contains("svg")

        return isDrawable && self.room.canChat && self.room.readOnlyState != .readOnly
    }

    private func updateToolbarButtons() {
        let mediaPageViewController = self.getCurrentPageViewController()
        let message = self.getCurrentMessage()

        var items: [UIBarButtonItem] = []

        if let message, self.canForward(message) {
            items.append(self.forwardButton)
        }

        items.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))

        if let message, self.canDraw(message) {
            // A copy of the downloaded file is edited, so the file has to be there
            self.drawButton.isEnabled = mediaPageViewController?.sharableFileURL != nil
            items.append(self.drawButton)
        }

        self.setToolbarItems(items, animated: false)
    }

    // MARK: - Menu

    private func makeMenuElements() -> [UIMenuElement] {
        guard let mediaPageViewController = self.getCurrentPageViewController(), let message = self.getCurrentMessage() else { return [] }

        var actions: [UIMenuElement] = []

        // Enabled as soon as we know where the file will be, saving and sharing wait for the download
        if mediaPageViewController.expectedFileURL != nil {
            actions.append(UIAction(title: NSLocalizedString("Save to Photos", comment: "Menu entry in the media viewer to save the shown picture or video to the photo library"), image: .init(systemName: "square.and.arrow.down")) { [weak self] _ in
                self?.saveCurrentMediaToPhotos()
            })
        }

        if !self.isOpenedFromSharedItems {
            actions.append(UIAction(title: NSLocalizedString("Show all media", comment: "Menu entry in the media viewer to open all pictures and videos of the conversation"), image: .init(systemName: "photo.on.rectangle.angled")) { [weak self] _ in
                self?.showAllMedia()
            })
        }

        // The message can only be shown when the server supports the context endpoint
        if self.room.supportsMessageContext {
            actions.append(UIAction(title: NSLocalizedString("Show in chat", comment: "Menu entry in the media viewer to show the message of the shown media in the chat"), image: .init(systemName: "text.magnifyingglass")) { [weak self] _ in
                self?.showCurrentMessageInChat()
            })
        }

        if let delegate = self.delegate, delegate.mediaViewerViewControllerCanReply(self), message.canReply(in: self.room) {
            actions.append(UIAction(title: NSLocalizedString("Reply", comment: ""), image: .init(systemName: "arrowshape.turn.up.left")) { [weak self] _ in
                self?.replyToCurrentMessage()
            })
        }

        if mediaPageViewController.expectedFileURL != nil {
            actions.append(UIAction(title: NSLocalizedString("Share media", comment: "Menu entry in the media viewer to share the shown picture or video with other apps"), image: .init(systemName: "square.and.arrow.up")) { [weak self] _ in
                self?.shareCurrentMedia()
            })
        }

        var elements = actions

        if let delegate = self.delegate, delegate.mediaViewerViewController(self, canDelete: message) {
            let deleteAction = UIAction(title: NSLocalizedString("Delete", comment: ""), image: .init(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.confirmDeletionOfCurrentMessage()
            }

            elements.append(UIMenu(options: [.displayInline], children: [deleteAction]))
        }

        return elements
    }

    // MARK: - Actions

    private func shareCurrentMedia() {
        guard self.getCurrentMessage() != nil,
              let mediaPageViewController = self.getCurrentPageViewController(),
              let placeholderURL = mediaPageViewController.expectedFileURL
        else { return }

        // Only ever the original file, never a preview. The provider waits for the download if
        // it is not finished yet, while the user picks a destination.
        let itemProvider = MediaShareItemProvider(placeholderURL: placeholderURL,
                                                  thumbnail: mediaPageViewController.displayedImage) { [weak mediaPageViewController] completion in
            guard let mediaPageViewController else {
                completion(nil)
                return
            }

            mediaPageViewController.requestSharableFile(completion: completion)
        }

        let activityViewController = UIActivityViewController(activityItems: [itemProvider], applicationActivities: nil)
        activityViewController.popoverPresentationController?.barButtonItem = self.moreButton
        // didFail stays false when the user simply dismissed the sheet, so no need to look at
        // whether an activity completed
        activityViewController.completionWithItemsHandler = { [weak self] _, _, _, _ in
            guard itemProvider.didFail else { return }

            self?.showSharingFailedAlert()
        }

        self.present(activityViewController, animated: true)
    }

    private func saveCurrentMediaToPhotos() {
        guard let mediaPageViewController = self.getCurrentPageViewController(), let message = self.getCurrentMessage() else { return }

        let isVideo = NCUtils.isVideo(fileType: message.file()?.mimetype ?? "")

        // Waits for the download when the original is not there yet
        mediaPageViewController.requestSharableFile { [weak self, weak mediaPageViewController] fileURL in
            guard let self, let mediaPageViewController else { return }

            guard let fileURL else {
                // A page we swiped away from gives up its waiting requests, that is not an error
                if mediaPageViewController === self.getCurrentPageViewController() {
                    self.showSharingFailedAlert()
                }

                return
            }

            MediaPhotoLibrarySaver.save(fileURL: fileURL, isVideo: isVideo) { [weak self] result in
                switch result {
                case .success:
                    NotificationPresenter.shared().present(text: NSLocalizedString("Saved to Photos", comment: "Shown after a picture or video was saved to the photo library"), dismissAfterDelay: 5.0, includedStyle: .success)
                case .failure(.accessDenied):
                    self?.showPhotosAccessDeniedAlert()
                case .failure(.failed):
                    self?.showSavingFailedAlert()
                }
            }
        }
    }

    private func showAllMedia() {
        // Opens on the media tab, as long as the conversation has any media
        let sharedItemsViewController = RoomSharedItemsViewController(room: self.room)
        sharedItemsViewController.navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Close", comment: ""), primaryAction: UIAction { [weak sharedItemsViewController] _ in
            sharedItemsViewController?.dismiss(animated: true)
        })

        self.present(NCNavigationController(rootViewController: sharedItemsViewController), animated: true)
    }

    private func showCurrentMessageInChat() {
        guard let message = self.getCurrentMessage() else { return }

        if let account = message.account, let chatViewController = ContextChatViewController(forRoom: self.room, withAccount: account, withMessage: [], withHighlightId: 0) {
            chatViewController.showContext(ofMessageId: message.messageId, withLimit: 50, withCloseButton: true)

            let navController = NCNavigationController(rootViewController: chatViewController)
            self.present(navController, animated: true)
        }
    }

    private func replyToCurrentMessage() {
        // The chat gets a copy, the stored message may be gone or replaced after the viewer is closed
        guard let message = self.getCurrentMessage(), let delegate = self.delegate else { return }

        let messageCopy = NCChatMessage(value: message)

        // The chat shows its reply bar, so the viewer has to get out of the way first
        self.dismiss(animated: true) {
            delegate.mediaViewerViewController(self, didRequestReplyTo: messageCopy)
        }
    }

    private func confirmDeletionOfCurrentMessage() {
        guard let message = self.getCurrentMessage(), let delegate = self.delegate else { return }

        let messageCopy = NCChatMessage(value: message)

        let title = delegate.mediaViewerViewController(self, deletesFileGroupWith: messageCopy)
            ? NSLocalizedString("Delete all files shared together?", comment: "Title of the confirmation shown before a group of files shared together is deleted from the media viewer")
            : NSLocalizedString("Delete this message?", comment: "Title of the confirmation shown before a picture or video message is deleted from the media viewer")

        let alert = UIAlertController(title: title,
                                      message: nil,
                                      preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: NSLocalizedString("Delete", comment: ""), style: .destructive) { [weak self] _ in
            guard let self else { return }

            self.dismiss(animated: true) {
                delegate.mediaViewerViewController(self, didRequestDelete: messageCopy)
            }
        })

        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))

        self.present(alert, animated: true)
    }

    // The file of the message is shared into the chosen conversation, nothing is uploaded again.
    // The path is read from the message object here, it is never taken from an outside source.
    private func forwardCurrentMedia() {
        guard let message = self.getCurrentMessage(), self.canForward(message) else { return }

        // The share screen stays open for a while, the stored message may be gone by then
        let shareViewController = ShareViewController(toForwardFile: NCChatMessage(value: message), fromChatViewController: self)
        shareViewController.delegate = self

        self.present(NCNavigationController(rootViewController: shareViewController), animated: true)
    }

    // QuickLook and the share controller move and change files, so the downloaded original is never handed over, only a copy
    private func startDrawingOnCopy() {
        guard let mediaPageViewController = self.getCurrentPageViewController(),
              let sourceURL = mediaPageViewController.sharableFileURL
        else { return }

        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent("MediaViewerDraw-\(UUID().uuidString)", isDirectory: true)
        let copyURL = directoryURL.appendingPathComponent(sourceURL.lastPathComponent)

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: copyURL)
        } catch {
            try? FileManager.default.removeItem(at: directoryURL)
            self.showErrorAlert(title: NSLocalizedString("An error occurred while sharing the file", comment: ""))
            return
        }

        guard let serverCapabilities = NCDatabaseManager.sharedInstance().serverCapabilities(forAccountId: self.account.accountId),
              let shareConfirmationViewController = ShareConfirmationViewController(room: self.room, thread: self.thread, account: self.account, serverCapabilities: serverCapabilities)
        else {
            try? FileManager.default.removeItem(at: directoryURL)
            return
        }

        shareConfirmationViewController.delegate = self
        shareConfirmationViewController.isModal = true

        self.present(NCNavigationController(rootViewController: shareConfirmationViewController), animated: true) {
            // The item controller moves the file into its own folder
            shareConfirmationViewController.shareItemController.addItem(with: copyURL)
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    // MARK: - Alerts

    private func showSharingFailedAlert() {
        self.showErrorAlert(title: NSLocalizedString("An error occurred downloading the picture", comment: ""))
    }

    private func showSavingFailedAlert() {
        self.showErrorAlert(title: NSLocalizedString("Unable to save to Photos", comment: "Title of the error shown when a picture or video could not be saved to the photo library"))
    }

    private func showErrorAlert(title: String) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default))

        self.present(alert, animated: true)
    }

    private func showPhotosAccessDeniedAlert() {
        let alert = UIAlertController(title: NSLocalizedString("Unable to save to Photos", comment: "Title of the error shown when a picture or video could not be saved to the photo library"),
                                      message: NSLocalizedString("Allow access to your photos in the settings of your device to save pictures and videos", comment: "Message of the error shown when saving to the photo library is not allowed"),
                                      preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: ""), style: .default) { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        })

        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))

        self.present(alert, animated: true)
    }

    // MARK: - ShareViewController delegate

    func shareViewControllerDidCancel(_ viewController: ShareViewController) {
        self.dismissSharingFlow()
    }

    // MARK: - ShareConfirmationViewController delegate

    func shareConfirmationViewControllerDidFail(_ viewController: ShareConfirmationViewController) {
        self.dismissSharingFlow { [weak self] in
            self?.showErrorAlert(title: NSLocalizedString("An error occurred while sharing the file", comment: ""))
        }
    }

    func shareConfirmationViewControllerDidFinish(_ viewController: ShareConfirmationViewController) {
        let isForwarding = viewController.forwardingMessage

        var userInfo: [String: String] = [:]
        userInfo["token"] = viewController.room.token
        userInfo["accountId"] = viewController.account.accountId

        // Everything is done, so close the viewer together with the sharing screens
        (self.presentingViewController ?? self).dismiss(animated: true) {
            if isForwarding {
                NotificationCenter.default.post(name: .NCChatViewControllerForwardNotification, object: nil, userInfo: userInfo)
            }
        }
    }

    func shareConfirmationViewControllerDidCancel(_ viewController: ShareConfirmationViewController) {
        self.dismissSharingFlow()
    }

    // Only closes what the viewer presented, the viewer itself stays
    private func dismissSharingFlow(completion: (() -> Void)? = nil) {
        guard let presentedViewController = self.presentedViewController else {
            completion?()
            return
        }

        presentedViewController.dismiss(animated: true, completion: completion)
    }

    // MARK: - NCMediaViewerPageViewController delegate

    func mediaViewerPageZoomDidChange(_ controller: NCMediaViewerPageViewController, _ scale: Double) {
        // Prevent the scrollView interfering with our pan gesture recognizer when the view is zoomed
        // Also disable dismissal gesture when the view is zoomed

        guard let navController = self.navigationController as? CustomPresentableNavigationController else { return }

        if scale == 1 {
            pageController.enableSwipeGesture()
            navController.dismissalGestureEnabled = true
        } else {
            pageController.disableSwipeGesture()
            navController.dismissalGestureEnabled = false
        }
    }

    func mediaViewerPageStateDidChange(_ controller: NCMediaViewerPageViewController) {
        guard let mediaPageViewController = self.getCurrentPageViewController(), mediaPageViewController.isEqual(controller) else { return }

        self.updateToolbarButtons()
    }
}
